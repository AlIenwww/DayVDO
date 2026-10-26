import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = [] {
        didSet {
            guard items != oldValue else { return }
            itemIndexDirty = true
            guard !isLoading else { return }
            rebuildIndexes()
        }
    }
    @Published private(set) var projects: [TodoProject] = [] {
        didSet {
            guard projects != oldValue else { return }
            projectIndexDirty = true
            guard !isLoading else { return }
            rebuildIndexes()
        }
    }
    @Published private(set) var tags: [TaskTag] = [] {
        didSet {
            guard tags != oldValue else { return }
            tagIndexDirty = true
            guard !isLoading else { return }
            rebuildIndexes()
        }
    }
    @Published var settings = AppSettings() {
        didSet {
            L10n.configure(language: settings.language)
            if settings != oldValue { scheduleSave() }
        }
    }
    @Published private(set) var schedules: [DaySchedule] = [] {
        didSet {
            guard schedules != oldValue else { return }
            scheduleIndexDirty = true
            if !isLoading { rebuildIndexes() }
        }
    }
    @Published private(set) var contentRevision: UInt64 = 0
    /// Date bars do not depend on arrangements or project metadata.
    @Published private(set) var dateContentRevision: UInt64 = 0
    /// Arrangement presentation also depends on task filtering and labels.
    @Published private(set) var timelineContentRevision: UInt64 = 0

    @Published private(set) var persistenceIssue: PersistenceIssue?
    @Published private(set) var isReadOnly = false
    @Published private(set) var isInitialLoading = false

    var canModify: Bool { !isInitialLoading && !isReadOnly }

    weak var undoManager: UndoManager?

    enum ProjectDeletionStrategy {
        case deleteTasks
        case keepTasks
    }

    enum RecoveryAction: Equatable {
        case restoreBackup
        case replaceWithEmptyData
    }

    enum PersistenceIssue: Identifiable, Equatable {
        case recoveryRequired(hasBackup: Bool, backupDate: Date?)
        case recoveryFailed(action: RecoveryAction, message: String)
        case saveFailed(message: String)

        var id: String {
            switch self {
            case .recoveryRequired(let hasBackup, let backupDate):
                "recovery-\(hasBackup)-\(backupDate?.timeIntervalSince1970 ?? 0)"
            case .recoveryFailed(let action, _): "recovery-failed-\(String(describing: action))"
            case .saveFailed: "save-failed"
            }
        }
    }

    private struct ProjectSummary: Sendable {
        var completed = 0
        var total = 0

        var isCompleted: Bool { total > 0 && completed == total }
    }

    private let fileURL: URL
    private let persistenceWriter: TodoPersistence
    private var itemsByProject: [UUID: [TodoItem]] = [:]
    private var itemsByID: [UUID: TodoItem] = [:]
    private var projectSummaries: [UUID: ProjectSummary] = [:]
    private var projectsByID: [UUID: TodoProject] = [:]
    private var tagsByID: [UUID: TaskTag] = [:]
    private var tagUsageCounts: [UUID: Int] = [:]
    private var schedulesByID: [UUID: DaySchedule] = [:]
    private var schedulesByDay: [LocalDay: [DaySchedule]] = [:]
    private var schedulesByTodo: [UUID: [DaySchedule]] = [:]
    private var scheduledMinutesByTodo: [UUID: Int] = [:]
    private var orderedProjectItems: [UUID: [TodoItem]] = [:]
    private var orderedItems: [TodoItem] = []
    private var orderedProjects: [TodoProject] = []
    private var orderedTags: [TaskTag] = []
    private var itemIndexDirty = true
    private var projectIndexDirty = true
    private var tagIndexDirty = true
    private var scheduleIndexDirty = true
    private var isLoading = false
    private var isApplyingUndo = false
    private var saveGeneration: UInt64 = 0
    private var pendingSaveTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoverySnapshot: TodoSnapshot?
    private var hasUnsavedChanges = false

    init(fileURL: URL? = nil, loadsAsynchronously: Bool? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL
        if fileURL == nil {
            Self.migrateLegacyDataIfNeeded(to: resolvedURL)
        }
        self.fileURL = resolvedURL
        persistenceWriter = TodoPersistence(fileURL: resolvedURL)
        L10n.configure(language: settings.language)
        if loadsAsynchronously ?? (fileURL == nil) {
            // Read only preferences before any window is built. Decoding the
            // task graph and rebuilding its indexes stays off the launch path.
            isLoading = true
            settings = Self.startupSettings(from: resolvedURL)
            isLoading = false
            isInitialLoading = true
            Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) {
                    TodoPersistence.load(from: resolvedURL)
                }.value
                self?.applyLoadResult(result)
            }
        } else {
            applyLoadResult(TodoPersistence.load(from: resolvedURL))
        }
    }

    private static func startupSettings(from fileURL: URL) -> AppSettings {
        struct Preferences: Decodable { var settings: AppSettings? }
        return (try? JSONDecoder().decode(Preferences.self,
            from: Data(contentsOf: fileURL, options: .mappedIfSafe)))?.settings ?? AppSettings()
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("DayVDO", isDirectory: true)
            .appendingPathComponent("todos.json")
    }

    private static func migrateLegacyDataIfNeeded(to destination: URL) {
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let legacyURL = destination.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Daymark", isDirectory: true)
            .appendingPathComponent("todos.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL) else { return }

        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: destination, options: .atomic)
    }

    var todayItems: [TodoItem] {
        allItems(on: LocalDay(.now, timeZone: Calendar.current.timeZone))
    }

    var visibleItems: [TodoItem] {
        settings.showCompleted ? orderedItems : orderedItems.filter { !$0.isCompleted }
    }

    var sortedProjects: [TodoProject] { orderedProjects }
    var sortedTags: [TaskTag] { orderedTags }

    func allItems(on day: LocalDay) -> [TodoItem] {
        allItems(on: day, today: LocalDay(.now, timeZone: Calendar.current.timeZone))
    }

    func allItems(on day: LocalDay, today: LocalDay) -> [TodoItem] {
        let timeZone = Calendar.current.timeZone
        return orderedItems.filter {
            TaskDateRangePolicy.isVisible($0, on: day, today: today, includeCompleted: true, timeZone: timeZone)
        }
    }

    func planningItems(on day: LocalDay, today: LocalDay) -> [TodoItem] {
        let scheduledIDs = Set(schedules(on: day).compactMap(\.todoID))
        var result = allItems(on: day, today: today)
        let includedIDs = Set(result.map(\.id))
        result.append(contentsOf: orderedItems.filter {
            scheduledIDs.contains($0.id) && !includedIDs.contains($0.id)
        })
        // Keep date-visible tasks ahead of schedule-only tasks when all sort
        // fields tie, as the previous stable ordering did.
        return result.sorted(by: Self.areInIncreasingOrder)
    }

    func schedule(withID id: UUID?) -> DaySchedule? {
        guard let id else { return nil }
        return schedulesByID[id]
    }

    func schedules(on day: LocalDay) -> [DaySchedule] { schedulesByDay[day] ?? [] }

    func schedules(for todoID: UUID) -> [DaySchedule] { schedulesByTodo[todoID] ?? [] }

    func scheduledMinutes(for todoID: UUID) -> Int { scheduledMinutesByTodo[todoID] ?? 0 }

    @discardableResult
    func upsertSchedule(_ schedule: DaySchedule) -> Bool {
        guard schedule.isValid else { return false }
        if let id = schedule.todoID {
            guard itemsByID[id] != nil else { return false }
        }
        var normalized = schedule
        if case .independent(let title, let notes) = normalized.content {
            normalized.content = .independent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes)
        }
        return performUndoable(L10n.string(schedulesByID[schedule.id] != nil ? "编辑安排" : "添加安排")) {
            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                schedules[index] = normalized
            } else {
                schedules.append(normalized)
            }
        }
    }

    @discardableResult
    func deleteSchedule(_ id: UUID) -> Bool {
        performUndoable(L10n.string("移除安排")) { schedules.removeAll { $0.id == id } }
    }

    func items(on date: Date) -> [TodoItem] {
        let timeZone = Calendar.current.timeZone
        let day = LocalDay(date, timeZone: timeZone)
        let today = LocalDay(.now, timeZone: timeZone)
        return orderedItems.filter {
            TaskDateRangePolicy.isVisible(
                $0,
                on: day,
                today: today,
                includeCompleted: settings.showCompleted,
                timeZone: timeZone
            )
        }
    }

    func calendarItems(on date: Date, visibility: TodoFilterContext? = nil) -> [TodoItem] {
        let timeZone = Calendar.current.timeZone
        let day = LocalDay(date, timeZone: timeZone)
        let today = LocalDay(.now, timeZone: timeZone)
        let criteria = visibility ?? TodoFilterContext(showCompleted: settings.showCompleted, today: today)
        return orderedItems.filter {
            criteria.includes($0) && TaskDateRangePolicy.isVisibleInCalendar(
                $0,
                on: day,
                today: today,
                includeCompleted: true,
                timeZone: timeZone
            )
        }
    }

    /// A confirmation authorizes exactly the displayed item and schedule versions.
    struct DateChangeConfirmation: Equatable {
        let original: TodoItem
        let candidate: TodoItem
        let schedules: [DaySchedule]
        let affectedSchedules: [DaySchedule]
    }

    enum DateChangeScheduleAction {
        case keepAsIndependent
        case delete
    }

    func dateChangeConfirmation(for candidate: TodoItem) -> DateChangeConfirmation? {
        guard candidate.hasValidDateRange, let original = item(withID: candidate.id),
              original.startDay != candidate.startDay || original.dueDay != candidate.dueDay else { return nil }
        let linked = schedules(for: candidate.id)
        let affected: [DaySchedule]
        if let start = candidate.startDay, let end = candidate.dueDay {
            affected = linked.filter { !$0.isContained(in: start...end) }
        } else {
            affected = linked
        }
        guard !affected.isEmpty else { return nil }
        return DateChangeConfirmation(original: original, candidate: candidate,
                                      schedules: linked, affectedSchedules: affected)
    }

    @discardableResult
    func confirmDateChange(_ request: DateChangeConfirmation, scheduleAction: DateChangeScheduleAction) -> Bool {
        guard dateChangeConfirmation(for: request.candidate) == request else { return false }
        return saveItem(request.candidate, scheduleChange: (Set(request.affectedSchedules.map(\.id)), scheduleAction))
    }

    @discardableResult
    func upsert(_ item: TodoItem) -> Bool {
        guard dateChangeConfirmation(for: item) == nil else { return false }
        return saveItem(item)
    }

    private func saveItem(_ item: TodoItem,
                          scheduleChange: (ids: Set<UUID>, action: DateChangeScheduleAction)? = nil) -> Bool {
        var copy = item
        copy.title = copy.normalizedTitle
        guard !copy.title.isEmpty,
              copy.estimatedMinutes.map({ $0 > 0 }) ?? true,
              copy.hasValidDateRange else { return false }

        if copy.status == .completed {
            copy.completedAt = copy.completedAt ?? .now
            if copy.previousIncompleteStatus == .completed {
                copy.previousIncompleteStatus = .notStarted
            }
        } else {
            copy.previousIncompleteStatus = copy.status
            copy.completedAt = nil
        }

        let isEditing = items.contains { $0.id == copy.id }

        let previousProjectID = items.first(where: { $0.id == copy.id })?.projectID
        if previousProjectID != copy.projectID {
            copy.projectSortOrder = nil
        }

        if let projectID = copy.projectID, projects.contains(where: { $0.id == projectID }) {
            if copy.projectSortOrder == nil {
                copy.projectSortOrder = (items
                    .filter { $0.projectID == projectID }
                    .compactMap(\.projectSortOrder)
                    .max() ?? -1) + 1
            }
        } else {
            copy.projectID = nil
            copy.projectSortOrder = nil
        }
        if let tagID = copy.tagID, !tags.contains(where: { $0.id == tagID }) {
            copy.tagID = nil
        }

        return performUndoable(L10n.string(isEditing ? "编辑待办" : "添加待办")) {
            if let change = scheduleChange {
                switch change.action {
                case .delete:
                    schedules.removeAll { change.ids.contains($0.id) }
                case .keepAsIndependent:
                    schedules = schedules.map { schedule in
                        guard change.ids.contains(schedule.id) else { return schedule }
                        var independent = schedule
                        independent.content = .independent(title: copy.title, notes: copy.notes)
                        return independent
                    }
                }
            }
            if let index = items.firstIndex(where: { $0.id == copy.id }) {
                items[index] = copy
            } else {
                items.append(copy)
            }
        }
    }

    @discardableResult
    func upsertProject(_ project: TodoProject) -> Bool {
        var copy = project
        copy.title = copy.normalizedTitle
        guard !copy.title.isEmpty else { return false }
        if let tagID = copy.tagID, !tags.contains(where: { $0.id == tagID }) {
            copy.tagID = nil
        }

        let isEditing = projects.contains { $0.id == copy.id }
        return performUndoable(L10n.string(isEditing ? "编辑大项目" : "新建大项目")) {
            if let index = projects.firstIndex(where: { $0.id == copy.id }) {
                projects[index] = copy
            } else {
                copy.sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
                projects.append(copy)
            }
        }
    }

    @discardableResult
    func upsertTag(_ tag: TaskTag) -> Bool {
        var copy = tag
        copy.name = copy.normalizedName
        guard !copy.name.isEmpty,
              isTagNameAvailable(copy.name, excluding: copy.id) else { return false }

        let isEditing = tags.contains { $0.id == copy.id }
        return performUndoable(L10n.string(isEditing ? "编辑标签" : "新建标签")) {
            if let index = tags.firstIndex(where: { $0.id == copy.id }) {
                tags[index] = copy
            } else {
                copy.sortOrder = (tags.map(\.sortOrder).max() ?? -1) + 1
                tags.append(copy)
            }
        }
    }

    func deleteTag(_ tag: TaskTag) {
        performUndoable(L10n.string("删除标签")) {
            items = items.map { item in
                guard item.tagID == tag.id else { return item }
                var copy = item
                copy.tagID = nil
                return copy
            }
            projects = projects.map { project in
                guard project.tagID == tag.id else { return project }
                var copy = project
                copy.tagID = nil
                return copy
            }
            tags.removeAll { $0.id == tag.id }
        }
    }

    func moveTag(_ tagID: UUID, to targetID: UUID) {
        guard tagID != targetID else { return }
        var orderedIDs = sortedTags.map(\.id)
        guard let source = orderedIDs.firstIndex(of: tagID),
              orderedIDs.contains(targetID) else { return }

        orderedIDs.remove(at: source)
        guard let target = orderedIDs.firstIndex(of: targetID) else { return }
        orderedIDs.insert(tagID, at: target)
        performUndoable(L10n.string("重新排序")) {
            var updated = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
            for (order, id) in orderedIDs.enumerated() {
                updated[id]?.sortOrder = order
            }
            tags = tags.compactMap { updated[$0.id] }
        }
    }

    func tag(withID id: UUID?) -> TaskTag? {
        guard let id else { return nil }
        return tagsByID[id]
    }

    func item(withID id: UUID?) -> TodoItem? {
        guard let id else { return nil }
        return itemsByID[id]
    }

    func tagUsageCount(_ tag: TaskTag) -> Int {
        tagUsageCounts[tag.id, default: 0]
    }

    func isTagNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let normalized = normalizedTagName(name)
        guard !normalized.isEmpty else { return false }
        return !tags.contains { tag in
            tag.id != id && normalizedTagName(tag.name) == normalized
        }
    }

    @discardableResult
    func toggle(_ item: TodoItem) -> Bool {
        guard let current = itemsByID[item.id] else { return false }
        let nextStatus: TodoItem.Status = current.isCompleted
            ? current.previousIncompleteStatus
            : .completed
        return setStatus(nextStatus, for: current)
    }

    @discardableResult
    func setStatus(_ status: TodoItem.Status, for item: TodoItem) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        let current = items[index]
        guard current.status != status else { return false }

        let actionName: String
        switch status {
        case .notStarted: actionName = L10n.string("标记为未开始")
        case .inProgress: actionName = L10n.string("标记为进行中")
        case .completed: actionName = L10n.string("标记为已完成")
        }

        return performUndoable(actionName) {
            if status == .completed {
                if items[index].status != .completed {
                    items[index].previousIncompleteStatus = items[index].status
                }
                items[index].status = .completed
                items[index].completedAt = .now
            } else {
                items[index].status = status
                items[index].previousIncompleteStatus = status
                items[index].completedAt = nil
            }
        }
    }

    @discardableResult
    func delete(_ item: TodoItem) -> Bool {
        performUndoable(L10n.string("删除待办")) {
            items.removeAll { $0.id == item.id }
            schedules.removeAll { $0.todoID == item.id }
        }
    }

    @discardableResult
    func deleteProject(_ project: TodoProject, strategy: ProjectDeletionStrategy) -> Bool {
        performUndoable(L10n.string("删除项目")) {
            switch strategy {
            case .deleteTasks:
                let removedIDs = Set(items.filter { $0.projectID == project.id }.map(\.id))
                schedules.removeAll { $0.todoID.map(removedIDs.contains) ?? false }
                items.removeAll { $0.projectID == project.id }
            case .keepTasks:
                items = items.map { item in
                    guard item.projectID == project.id else { return item }
                    var copy = item
                    copy.projectID = nil
                    copy.projectSortOrder = nil
                    return copy
                }
            }
            projects.removeAll { $0.id == project.id }
        }
    }

    func project(withID id: UUID?) -> TodoProject? {
        guard let id else { return nil }
        return projectsByID[id]
    }

    func items(in project: TodoProject) -> [TodoItem] {
        // Callers can retain an older project value across an edit or undo.
        guard project.usesManualTaskOrder == projectsByID[project.id]?.usesManualTaskOrder else {
            let children = itemsByProject[project.id] ?? []
            return children.sorted(by: project.usesManualTaskOrder
                ? areProjectItemsManuallyOrdered : areProjectItemsInDefaultOrder)
        }
        return orderedProjectItems[project.id] ?? []
    }

    func newItem(in project: TodoProject) -> TodoItem {
        TodoItem(
            title: "",
            priority: settings.defaultPriority,
            projectID: project.id,
            tagID: project.tagID
        )
    }

    func projectIsCompleted(_ project: TodoProject) -> Bool {
        projectSummaries[project.id]?.isCompleted ?? false
    }

    func projectProgress(_ project: TodoProject) -> (completed: Int, total: Int) {
        let summary = projectSummaries[project.id] ?? ProjectSummary()
        return (summary.completed, summary.total)
    }

    @discardableResult
    func moveProjectItem(_ itemID: UUID, before targetID: UUID?, in projectID: UUID) -> Bool {
        guard itemID != targetID,
              let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return false }

        let project = projects[projectIndex]
        var orderedIDs = items(in: project).map(\.id)
        guard let source = orderedIDs.firstIndex(of: itemID),
              targetID.map({ orderedIDs.contains($0) }) ?? true else { return false }

        orderedIDs.remove(at: source)
        let target = targetID.flatMap { orderedIDs.firstIndex(of: $0) } ?? orderedIDs.endIndex
        orderedIDs.insert(itemID, at: target)
        guard orderedIDs != items(in: project).map(\.id) else { return false }
        return performUndoable(L10n.string("重新排序")) {
            var updatedItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            for (order, id) in orderedIDs.enumerated() {
                updatedItems[id]?.projectSortOrder = order
            }
            items = items.compactMap { updatedItems[$0.id] }
            projects[projectIndex].usesManualTaskOrder = true
        }
    }

    var dataDirectoryURL: URL { fileURL.deletingLastPathComponent() }

    var hasPendingPersistence: Bool {
        pendingSaveTask != nil || recoveryTask != nil || hasUnsavedChanges
    }

    func retryPersistence() {
        switch persistenceIssue {
        case .recoveryFailed(let action, _):
            switch action {
            case .restoreBackup: restoreLatestBackup()
            case .replaceWithEmptyData: continueWithEmptyData()
            }
        case .saveFailed:
            guard !isReadOnly else { return }
            scheduleSave(delayNanoseconds: 0)
        case .recoveryRequired, nil:
            break
        }
    }

    func restoreLatestBackup() {
        guard recoveryTask == nil else { return }
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            await restoreLatestBackupNow()
            recoveryTask = nil
        }
    }

    func restoreLatestBackupNow() async {
        guard let recoverySnapshot else { return }
        do {
            try await persistenceWriter.replaceCorruptPrimary(with: recoverySnapshot)
            applyLoadedSnapshot(recoverySnapshot)
            self.recoverySnapshot = nil
            isReadOnly = false
            hasUnsavedChanges = false
            persistenceIssue = nil
        } catch {
            isReadOnly = true
            persistenceIssue = .recoveryFailed(
                action: .restoreBackup,
                message: error.localizedDescription
            )
        }
    }

    func continueWithEmptyData() {
        guard recoveryTask == nil else { return }
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            await continueWithEmptyDataNow()
            recoveryTask = nil
        }
    }

    func continueWithEmptyDataNow() async {
        let empty = TodoSnapshot(items: [], projects: [], tags: [], settings: settings)
        do {
            try await persistenceWriter.replaceCorruptPrimary(with: empty)
            applyLoadedSnapshot(empty)
            recoverySnapshot = nil
            isReadOnly = false
            hasUnsavedChanges = false
            persistenceIssue = nil
        } catch {
            isReadOnly = true
            persistenceIssue = .recoveryFailed(
                action: .replaceWithEmptyData,
                message: error.localizedDescription
            )
        }
    }

    @discardableResult
    func flushPersistence() async -> Bool {
        saveGeneration &+= 1
        while true {
            let generation = saveGeneration
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            guard !isReadOnly else {
                if case .saveFailed = persistenceIssue { return false }
                return true
            }
            do {
                try await persistenceWriter.save(currentSnapshot(), generation: generation)
                // Edits may arrive while the writer is working. Flush their
                // snapshot too; never mark a newer edit as already saved.
                guard generation == saveGeneration else { continue }
                hasUnsavedChanges = false
                if case .saveFailed = persistenceIssue { persistenceIssue = nil }
                return true
            } catch {
                guard generation == saveGeneration else { continue }
                persistenceIssue = .saveFailed(message: error.localizedDescription)
                return false
            }
        }
    }

    @discardableResult
    func prepareForTermination() async -> Bool {
        if let recoveryTask {
            await recoveryTask.value
        }
        return await flushPersistence()
    }

    private func applyLoadResult(_ result: TodoLoadResult) {
        var needsDateMigration = false
        isLoading = true
        defer {
            isLoading = false
            isInitialLoading = false
            rebuildIndexes()
            if needsDateMigration {
                scheduleSave(delayNanoseconds: 0)
            }
        }

        if let snapshot = result.snapshot {
            needsDateMigration = snapshot.version < TodoSnapshot.currentVersion
            applyLoadedSnapshot(snapshot)
        } else if result.failedPrimary {
            recoverySnapshot = result.recoverySnapshot
            if let recoverySnapshot {
                applyLoadedSnapshot(recoverySnapshot)
            }
            isReadOnly = true
            persistenceIssue = .recoveryRequired(
                hasBackup: recoverySnapshot != nil,
                backupDate: result.recoveryDate
            )
        }
    }

    private func applyLoadedSnapshot(_ snapshot: TodoSnapshot, preservingSettings: Bool = false) {
        let currentSettings = settings
        let wasLoading = isLoading
        isLoading = true
        defer {
            isLoading = wasLoading
            if !wasLoading { rebuildIndexes() }
        }
        tags = snapshot.tags
        let validTagIDs = Set(tags.map(\.id))
        projects = snapshot.projects.map { project in
            guard let tagID = project.tagID, !validTagIDs.contains(tagID) else { return project }
            var copy = project
            copy.tagID = nil
            return copy
        }
        let validProjectIDs = Set(projects.map(\.id))
        items = snapshot.items.map { item in
            var copy = item
            if let projectID = copy.projectID, !validProjectIDs.contains(projectID) {
                copy.projectID = nil
                copy.projectSortOrder = nil
            }
            if let tagID = copy.tagID, !validTagIDs.contains(tagID) {
                copy.tagID = nil
            }
            return copy
        }
        let validItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        schedules = snapshot.schedules.filter { schedule in
            guard let id = schedule.todoID else { return true }
            return validItems[id] != nil
        }
        settings = preservingSettings ? currentSettings : snapshot.settings
    }

    private func scheduleSave(delayNanoseconds: UInt64 = 150_000_000) {
        guard !isLoading, !isReadOnly else { return }
        hasUnsavedChanges = true
        saveGeneration &+= 1
        let generation = saveGeneration
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            do {
                if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
                try Task.checkCancellation()
                // Capture only after debouncing, without retaining the store
                // or its arrays throughout the wait.
                guard let self, generation == self.saveGeneration else { return }
                try await self.persistenceWriter.save(self.currentSnapshot(), generation: generation)
                guard !Task.isCancelled, generation == self.saveGeneration else { return }
                self.pendingSaveTask = nil
                self.hasUnsavedChanges = false
                if case .saveFailed = self.persistenceIssue { self.persistenceIssue = nil }
            } catch is CancellationError {
                // A newer request superseded this write.
            } catch {
                guard let self, !Task.isCancelled, generation == self.saveGeneration else { return }
                self.pendingSaveTask = nil
                self.persistenceIssue = .saveFailed(message: error.localizedDescription)
            }
        }
    }

    private func currentSnapshot() -> TodoSnapshot {
        TodoSnapshot(items: items, projects: projects, tags: tags, settings: settings, schedules: schedules)
    }

    @discardableResult
    private func performUndoable(_ actionName: String, mutation: () -> Void) -> Bool {
        guard canModify else { return false }
        let before = currentSnapshot()
        isLoading = true
        mutation()
        isLoading = false
        let after = currentSnapshot()
        // A mutation can assign and then normalize back to its original value.
        // Decide the actual changes before invalidating any derived cache.
        itemIndexDirty = before.items != after.items
        projectIndexDirty = before.projects != after.projects
        tagIndexDirty = before.tags != after.tags
        scheduleIndexDirty = before.schedules != after.schedules
        guard before != after else { return false }
        rebuildIndexes()

        if !isApplyingUndo, let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                target.restoreSnapshot(before, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
        scheduleSave()
        return true
    }

    private func restoreSnapshot(_ snapshot: TodoSnapshot, actionName: String) {
        let inverse = currentSnapshot()
        isApplyingUndo = true
        applyLoadedSnapshot(snapshot, preservingSettings: true)
        isApplyingUndo = false

        if let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                target.restoreSnapshot(inverse, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
        scheduleSave()
    }

    private func rebuildIndexes() {
        guard itemIndexDirty || projectIndexDirty || tagIndexDirty || scheduleIndexDirty else { return }
        let datesChanged = itemIndexDirty || tagIndexDirty
        let timelineChanged = datesChanged || scheduleIndexDirty
        if itemIndexDirty {
            itemsByProject = [:]
            itemsByID = [:]
            projectSummaries = [:]
            for item in items {
                itemsByID[item.id] = item
                if let id = item.projectID {
                    itemsByProject[id, default: []].append(item)
                    projectSummaries[id, default: ProjectSummary()].total += 1
                    if item.isCompleted { projectSummaries[id, default: ProjectSummary()].completed += 1 }
                }
            }
            orderedItems = items.sorted(by: Self.areInIncreasingOrder)
        }
        if projectIndexDirty {
            projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        }
        if itemIndexDirty || projectIndexDirty {
            orderedProjectItems = itemsByProject.mapValues { children in
                let manual = children.first?.projectID.flatMap { projectsByID[$0] }?.usesManualTaskOrder == true
                return children.sorted(by: manual ? areProjectItemsManuallyOrdered : areProjectItemsInDefaultOrder)
            }
            orderedProjects = projects.sorted {
                if projectIsCompleted($0) != projectIsCompleted($1) { return !projectIsCompleted($0) }
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
            tagUsageCounts = [:]
            for item in items {
                if let id = item.tagID { tagUsageCounts[id, default: 0] += 1 }
            }
            for project in projects {
                if let id = project.tagID { tagUsageCounts[id, default: 0] += 1 }
            }
        }
        if tagIndexDirty {
            tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
            orderedTags = tags.sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt < $1.createdAt
            }
        }
        if scheduleIndexDirty {
            schedulesByID = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0) })
            schedulesByDay = [:]
            schedulesByTodo = [:]
            scheduledMinutesByTodo = [:]
            for schedule in schedules {
                // Valid persisted arrangements occupy at most two local days.
                for offset in 0...((schedule.endMinute - 1) / 1440) {
                    let day = offset == 0 ? schedule.startDay : schedule.startDay.adding(days: offset)
                    schedulesByDay[day, default: []].append(schedule)
                }
                if let id = schedule.todoID {
                    schedulesByTodo[id, default: []].append(schedule)
                    scheduledMinutesByTodo[id, default: 0] += schedule.durationMinutes
                }
            }
            for id in schedulesByTodo.keys {
                schedulesByTodo[id]?.sort {
                    if $0.startDay != $1.startDay { return $0.startDay < $1.startDay }
                    return $0.startMinute < $1.startMinute
                }
            }
        }
        itemIndexDirty = false
        projectIndexDirty = false
        tagIndexDirty = false
        scheduleIndexDirty = false
        contentRevision &+= 1
        if datesChanged { dateContentRevision &+= 1 }
        if timelineChanged { timelineContentRevision &+= 1 }
    }

    static func areInIncreasingOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.urgency != rhs.urgency { return lhs.urgency.rawValue > rhs.urgency.rawValue }
        switch (lhs.dueDay, rhs.dueDay) {
        case let (left?, right?): return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.createdAt < rhs.createdAt
        }
    }

    private func areProjectItemsInDefaultOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        switch (lhs.dueDay, rhs.dueDay) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.urgency != rhs.urgency { return lhs.urgency.rawValue > rhs.urgency.rawValue }
        return lhs.createdAt < rhs.createdAt
    }

    private func areProjectItemsManuallyOrdered(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        let leftOrder = lhs.projectSortOrder ?? .max
        let rightOrder = rhs.projectSortOrder ?? .max
        if leftOrder != rightOrder { return leftOrder < rightOrder }
        return lhs.createdAt < rhs.createdAt
    }

    private func normalizedTagName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

}
