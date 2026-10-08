import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = [] {
        didSet {
            guard !isLoading else { return }
            rebuildIndexes()
        }
    }
    @Published private(set) var projects: [TodoProject] = [] {
        didSet {
            guard !isLoading else { return }
            rebuildIndexes()
        }
    }
    @Published private(set) var tags: [TaskTag] = [] {
        didSet {
            guard !isLoading else { return }
            rebuildIndexes()
        }
    }
    @Published var settings = AppSettings() {
        didSet {
            L10n.configure(language: settings.language)
            scheduleSave()
        }
    }
    @Published private(set) var schedules: [DaySchedule] = []
    @Published private(set) var contentRevision: UInt64 = 0

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

    private struct Snapshot: Codable, Sendable, Equatable {
        static let currentVersion = 4

        var version: Int
        var items: [TodoItem]
        var projects: [TodoProject]
        var tags: [TaskTag]
        var settings: AppSettings
        var schedules: [DaySchedule]

        private enum CodingKeys: String, CodingKey {
            case version
            case items
            case projects
            case tags
            case settings
            case schedules
        }

        init(
            items: [TodoItem],
            projects: [TodoProject],
            tags: [TaskTag],
            settings: AppSettings,
            schedules: [DaySchedule] = []
        ) {
            version = Self.currentVersion
            self.items = items
            self.projects = projects
            self.tags = tags
            self.settings = settings
            self.schedules = schedules
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            guard version <= Self.currentVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .version,
                    in: container,
                    debugDescription: "Unsupported DayVDO data version \(version)"
                )
            }
            items = try container.decodeIfPresent([TodoItem].self, forKey: .items) ?? []
            projects = try container.decodeIfPresent([TodoProject].self, forKey: .projects) ?? []
            tags = try container.decodeIfPresent([TaskTag].self, forKey: .tags) ?? []
            schedules = try container.decodeIfPresent([DaySchedule].self, forKey: .schedules) ?? []
            guard schedules.allSatisfy(\.isValid),
                  items.allSatisfy(\.hasValidDateRange),
                  Set(schedules.map(\.id)).count == schedules.count,
                  Set(items.map(\.id)).count == items.count else {
                throw DecodingError.dataCorruptedError(forKey: .schedules, in: container, debugDescription: "Invalid schedule or duplicate identifier")
            }
            settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        }
    }

    private struct ProjectSummary: Sendable {
        var completed = 0
        var total = 0

        var isCompleted: Bool { total > 0 && completed == total }
    }

    private struct LoadResult {
        var snapshot: Snapshot?
        var recoverySnapshot: Snapshot?
        var recoveryDate: Date?
        var failedPrimary = false
    }

    private let fileURL: URL
    private let persistenceWriter: PersistenceWriter
    private var itemsByProject: [UUID: [TodoItem]] = [:]
    private var itemsByID: [UUID: TodoItem] = [:]
    private var projectSummaries: [UUID: ProjectSummary] = [:]
    private var projectsByID: [UUID: TodoProject] = [:]
    private var tagsByID: [UUID: TaskTag] = [:]
    private var tagUsageCounts: [UUID: Int] = [:]
    private var isLoading = false
    private var isApplyingUndo = false
    private var pendingSaveTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoverySnapshot: Snapshot?
    private var hasUnsavedChanges = false

    init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL
        if fileURL == nil {
            Self.migrateLegacyDataIfNeeded(to: resolvedURL)
        }
        self.fileURL = resolvedURL
        persistenceWriter = PersistenceWriter(fileURL: resolvedURL)
        L10n.configure(language: settings.language)
        if fileURL == nil {
            isInitialLoading = true
            Task { [weak self] in
                let result = await Task.detached(priority: .userInitiated) {
                    PersistenceWriter.load(from: resolvedURL)
                }.value
                self?.applyLoadResult(result)
            }
        } else {
            applyLoadResult(PersistenceWriter.load(from: resolvedURL))
        }
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
        items.filter { settings.showCompleted || !$0.isCompleted }.sorted(by: TodoStore.areInIncreasingOrder)
    }

    var sortedProjects: [TodoProject] {
        projects.sorted {
            if projectIsCompleted($0) != projectIsCompleted($1) {
                return !projectIsCompleted($0)
            }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    var sortedTags: [TaskTag] {
        tags.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    func allItems(on day: LocalDay) -> [TodoItem] {
        allItems(on: day, today: LocalDay(.now, timeZone: Calendar.current.timeZone))
    }

    func allItems(on day: LocalDay, today: LocalDay) -> [TodoItem] {
        items.filter {
            TaskDateRangePolicy.isVisible(
                $0,
                on: day,
                today: today,
                includeCompleted: true,
                timeZone: Calendar.current.timeZone
            )
        }.sorted(by: Self.areInIncreasingOrder)
    }

    func planningItems(on day: LocalDay, today: LocalDay) -> [TodoItem] {
        let scheduledIDs = Set(schedules(on: day).compactMap(\.todoID))
        var result = allItems(on: day, today: today)
        let includedIDs = Set(result.map(\.id))
        result.append(contentsOf: items.filter {
            scheduledIDs.contains($0.id) && !includedIDs.contains($0.id)
        })
        return result.sorted(by: Self.areInIncreasingOrder)
    }

    func schedules(on day: LocalDay) -> [DaySchedule] {
        schedules.filter { $0.interval(on: day) != nil }
    }

    func schedules(for todoID: UUID) -> [DaySchedule] {
        schedules.filter { $0.todoID == todoID }.sorted {
            if $0.startDay != $1.startDay { return $0.startDay < $1.startDay }
            return $0.startMinute < $1.startMinute
        }
    }

    func scheduledMinutes(for todoID: UUID) -> Int {
        schedules(for: todoID).reduce(0) { $0 + $1.durationMinutes }
    }

    @discardableResult
    func upsertSchedule(_ schedule: DaySchedule) -> Bool {
        guard schedule.isValid else { return false }
        if let id = schedule.todoID {
            guard items.contains(where: { $0.id == id }) else { return false }
        }
        var normalized = schedule
        if case .independent(let title, let notes) = normalized.content {
            normalized.content = .independent(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes)
        }
        return performUndoable(L10n.string(schedules.contains { $0.id == schedule.id } ? "编辑安排" : "添加安排")) {
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
        return items.filter {
            TaskDateRangePolicy.isVisible(
                $0,
                on: day,
                today: today,
                includeCompleted: settings.showCompleted,
                timeZone: timeZone
            )
        }.sorted(by: Self.areInIncreasingOrder)
    }

    func calendarItems(on date: Date, visibility: TodoFilterContext? = nil) -> [TodoItem] {
        let timeZone = Calendar.current.timeZone
        let day = LocalDay(date, timeZone: timeZone)
        let today = LocalDay(.now, timeZone: timeZone)
        let criteria = visibility ?? TodoFilterContext(showCompleted: settings.showCompleted, today: today)
        return items.filter {
            criteria.includes($0) && TaskDateRangePolicy.isVisibleInCalendar(
                $0,
                on: day,
                today: today,
                includeCompleted: true,
                timeZone: timeZone
            )
        }.sorted(by: Self.areInIncreasingOrder)
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
        guard let current = items.first(where: { $0.id == item.id }) else { return false }
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
        let children = itemsByProject[project.id] ?? []
        if project.usesManualTaskOrder {
            return children.sorted(by: areProjectItemsManuallyOrdered)
        }
        return children.sorted(by: areProjectItemsInDefaultOrder)
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
    func moveProjectItem(_ itemID: UUID, before targetID: UUID, in projectID: UUID) -> Bool {
        guard itemID != targetID,
              let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return false }

        let project = projects[projectIndex]
        var orderedIDs = items(in: project).map(\.id)
        guard let source = orderedIDs.firstIndex(of: itemID),
              orderedIDs.contains(targetID) else { return false }

        orderedIDs.remove(at: source)
        guard let target = orderedIDs.firstIndex(of: targetID) else { return false }
        orderedIDs.insert(itemID, at: target)
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
        let empty = Snapshot(items: [], projects: [], tags: [], settings: settings)
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
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard !isReadOnly else {
            if case .saveFailed = persistenceIssue { return false }
            return true
        }
        do {
            try await persistenceWriter.save(currentSnapshot())
            hasUnsavedChanges = false
            if case .saveFailed = persistenceIssue { persistenceIssue = nil }
            return true
        } catch {
            persistenceIssue = .saveFailed(message: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func prepareForTermination() async -> Bool {
        if let recoveryTask {
            await recoveryTask.value
        }
        return await flushPersistence()
    }

    private func applyLoadResult(_ result: LoadResult) {
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
            needsDateMigration = snapshot.version < Snapshot.currentVersion
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

    private func applyLoadedSnapshot(_ snapshot: Snapshot, preservingSettings: Bool = false) {
        let currentSettings = settings
        isLoading = true
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
        isLoading = false
        rebuildIndexes()
    }

    private func scheduleSave(delayNanoseconds: UInt64 = 150_000_000) {
        guard !isLoading, !isReadOnly else { return }
        hasUnsavedChanges = true
        pendingSaveTask?.cancel()
        let snapshot = currentSnapshot()
        pendingSaveTask = Task { [weak self] in
            guard let self else { return }
            do {
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                try Task.checkCancellation()
                try await persistenceWriter.save(snapshot)
                guard !Task.isCancelled else { return }
                pendingSaveTask = nil
                hasUnsavedChanges = false
                if case .saveFailed = persistenceIssue { persistenceIssue = nil }
            } catch is CancellationError {
                // A newer snapshot superseded this pending write.
            } catch {
                pendingSaveTask = nil
                persistenceIssue = .saveFailed(message: error.localizedDescription)
            }
        }
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(items: items, projects: projects, tags: tags, settings: settings, schedules: schedules)
    }

    @discardableResult
    private func performUndoable(_ actionName: String, mutation: () -> Void) -> Bool {
        guard canModify else { return false }
        let before = currentSnapshot()
        isLoading = true
        mutation()
        isLoading = false
        rebuildIndexes()
        let after = currentSnapshot()
        guard before != after else { return false }

        if !isApplyingUndo, let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                target.restoreSnapshot(before, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
        scheduleSave()
        return true
    }

    private func restoreSnapshot(_ snapshot: Snapshot, actionName: String) {
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
        var projectIndex: [UUID: [TodoItem]] = [:]
        var summaries: [UUID: ProjectSummary] = [:]
        var usageCounts: [UUID: Int] = [:]

        for item in items {
            if let projectID = item.projectID {
                projectIndex[projectID, default: []].append(item)
                summaries[projectID, default: ProjectSummary()].total += 1
                if item.isCompleted {
                    summaries[projectID, default: ProjectSummary()].completed += 1
                }
            }
            if let tagID = item.tagID {
                usageCounts[tagID, default: 0] += 1
            }
        }
        for project in projects {
            if let tagID = project.tagID {
                usageCounts[tagID, default: 0] += 1
            }
        }
        itemsByProject = projectIndex
        itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        projectSummaries = summaries
        projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        tagUsageCounts = usageCounts
        contentRevision &+= 1
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

    private actor PersistenceWriter {
        private let fileURL: URL
        private let fileManager = FileManager.default
        private let encoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return encoder
        }()

        init(fileURL: URL) {
            self.fileURL = fileURL
        }

        static func load(from fileURL: URL) -> LoadResult {
            let manager = FileManager.default
            guard manager.fileExists(atPath: fileURL.path) else { return LoadResult() }
            if let data = try? Data(contentsOf: fileURL),
               let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
                return LoadResult(snapshot: snapshot)
            }

            let backupDirectory = fileURL.deletingLastPathComponent()
                .appendingPathComponent("Backups", isDirectory: true)
            let candidates = ((try? manager.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []).sorted { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return leftDate > rightDate
            }
            for url in candidates {
                guard let data = try? Data(contentsOf: url),
                      let recovery = try? JSONDecoder().decode(Snapshot.self, from: data) else {
                    continue
                }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return LoadResult(
                    recoverySnapshot: recovery,
                    recoveryDate: date,
                    failedPrimary: true
                )
            }
            return LoadResult(failedPrimary: true)
        }

        func save(_ snapshot: Snapshot) throws {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let newData = try encoder.encode(snapshot)

            if fileManager.fileExists(atPath: fileURL.path),
               let oldData = try? Data(contentsOf: fileURL),
               oldData != newData,
               (try? JSONDecoder().decode(Snapshot.self, from: oldData)) != nil {
                try createBackup(from: oldData)
            }
            try newData.write(to: fileURL, options: .atomic)
        }

        func replaceCorruptPrimary(with snapshot: Snapshot) throws {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: fileURL.path) {
                let corruptDirectory = directory.appendingPathComponent("Corrupt", isDirectory: true)
                try fileManager.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
                let destination = corruptDirectory.appendingPathComponent(
                    "todos-corrupt-\(Self.timestamp()).json"
                )
                try fileManager.moveItem(at: fileURL, to: destination)
            }
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        }

        private func createBackup(from data: Data) throws {
            let directory = fileURL.deletingLastPathComponent()
                .appendingPathComponent("Backups", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("todos-\(Self.timestamp()).json")
            try data.write(to: destination, options: .atomic)

            let backups = ((try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []).sorted { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return leftDate > rightDate
            }
            for oldBackup in backups.dropFirst(5) {
                try? fileManager.removeItem(at: oldBackup)
            }
        }

        nonisolated private static func timestamp() -> String {
            "\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString)"
        }
    }
}
