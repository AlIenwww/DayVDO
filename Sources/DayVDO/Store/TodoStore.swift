import Foundation

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = [] {
        didSet { rebuildDayIndex() }
    }
    @Published private(set) var projects: [TodoProject] = []
    @Published private(set) var tags: [TaskTag] = []
    @Published var settings = AppSettings() {
        didSet {
            L10n.configure(language: settings.language)
            save()
        }
    }

    enum ProjectDeletionStrategy {
        case deleteTasks
        case keepTasks
    }

    private struct Snapshot: Codable {
        var items: [TodoItem]
        var projects: [TodoProject]
        var tags: [TaskTag]
        var settings: AppSettings

        private enum CodingKeys: String, CodingKey {
            case items
            case projects
            case tags
            case settings
        }

        init(
            items: [TodoItem],
            projects: [TodoProject],
            tags: [TaskTag],
            settings: AppSettings
        ) {
            self.items = items
            self.projects = projects
            self.tags = tags
            self.settings = settings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([TodoItem].self, forKey: .items) ?? []
            projects = try container.decodeIfPresent([TodoProject].self, forKey: .projects) ?? []
            tags = try container.decodeIfPresent([TaskTag].self, forKey: .tags) ?? []
            settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        }
    }

    private let fileURL: URL
    private var itemsByDay: [Date: [TodoItem]] = [:]
    private var isLoading = false

    init(fileURL: URL? = nil) {
        let resolvedURL = fileURL ?? Self.defaultFileURL
        if fileURL == nil {
            Self.migrateLegacyDataIfNeeded(to: resolvedURL)
        }
        self.fileURL = resolvedURL
        load()
        L10n.configure(language: settings.language)
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
        items.filter { $0.isDue(on: .now) }.sorted(by: TodoStore.areInIncreasingOrder)
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

    func items(on date: Date) -> [TodoItem] {
        let dayItems = itemsByDay[Calendar.current.startOfDay(for: date)] ?? []
        return settings.showCompleted ? dayItems : dayItems.filter { !$0.isCompleted }
    }

    func upsert(_ item: TodoItem) {
        var copy = item
        copy.title = copy.normalizedTitle
        guard !copy.title.isEmpty else { return }

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

        if let index = items.firstIndex(where: { $0.id == copy.id }) {
            items[index] = copy
        } else {
            items.append(copy)
        }
        save()
    }

    func upsertProject(_ project: TodoProject) {
        var copy = project
        copy.title = copy.normalizedTitle
        guard !copy.title.isEmpty else { return }
        if let tagID = copy.tagID, !tags.contains(where: { $0.id == tagID }) {
            copy.tagID = nil
        }

        if let index = projects.firstIndex(where: { $0.id == copy.id }) {
            projects[index] = copy
        } else {
            copy.sortOrder = (projects.map(\.sortOrder).max() ?? -1) + 1
            projects.append(copy)
        }
        save()
    }

    @discardableResult
    func upsertTag(_ tag: TaskTag) -> Bool {
        var copy = tag
        copy.name = copy.normalizedName
        guard !copy.name.isEmpty,
              isTagNameAvailable(copy.name, excluding: copy.id) else { return false }

        if let index = tags.firstIndex(where: { $0.id == copy.id }) {
            tags[index] = copy
        } else {
            copy.sortOrder = (tags.map(\.sortOrder).max() ?? -1) + 1
            tags.append(copy)
        }
        save()
        return true
    }

    func deleteTag(_ tag: TaskTag) {
        for index in items.indices where items[index].tagID == tag.id {
            items[index].tagID = nil
        }
        for index in projects.indices where projects[index].tagID == tag.id {
            projects[index].tagID = nil
        }
        tags.removeAll { $0.id == tag.id }
        save()
    }

    func moveTag(_ tagID: UUID, to targetID: UUID) {
        guard tagID != targetID else { return }
        var orderedIDs = sortedTags.map(\.id)
        guard let source = orderedIDs.firstIndex(of: tagID),
              let originalTarget = orderedIDs.firstIndex(of: targetID) else { return }

        orderedIDs.remove(at: source)
        orderedIDs.insert(tagID, at: originalTarget)
        for (order, id) in orderedIDs.enumerated() {
            guard let index = tags.firstIndex(where: { $0.id == id }) else { continue }
            tags[index].sortOrder = order
        }
        save()
    }

    func tag(withID id: UUID?) -> TaskTag? {
        guard let id else { return nil }
        return tags.first { $0.id == id }
    }

    func tagUsageCount(_ tag: TaskTag) -> Int {
        items.filter { $0.tagID == tag.id }.count + projects.filter { $0.tagID == tag.id }.count
    }

    func isTagNameAvailable(_ name: String, excluding id: UUID? = nil) -> Bool {
        let normalized = normalizedTagName(name)
        guard !normalized.isEmpty else { return false }
        return !tags.contains { tag in
            tag.id != id && normalizedTagName(tag.name) == normalized
        }
    }

    func toggle(_ item: TodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
        items[index].completedAt = items[index].isCompleted ? .now : nil
        save()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func deleteProject(_ project: TodoProject, strategy: ProjectDeletionStrategy) {
        switch strategy {
        case .deleteTasks:
            items.removeAll { $0.projectID == project.id }
        case .keepTasks:
            for index in items.indices where items[index].projectID == project.id {
                items[index].projectID = nil
                items[index].projectSortOrder = nil
            }
        }
        projects.removeAll { $0.id == project.id }
        save()
    }

    func project(withID id: UUID?) -> TodoProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func items(in project: TodoProject) -> [TodoItem] {
        let children = items.filter { $0.projectID == project.id }
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
        let children = items.filter { $0.projectID == project.id }
        return !children.isEmpty && children.allSatisfy(\.isCompleted)
    }

    func projectProgress(_ project: TodoProject) -> (completed: Int, total: Int) {
        let children = items.filter { $0.projectID == project.id }
        return (children.filter(\.isCompleted).count, children.count)
    }

    func moveProjectItem(_ itemID: UUID, before targetID: UUID, in projectID: UUID) {
        guard itemID != targetID,
              let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }

        let project = projects[projectIndex]
        var orderedIDs = items(in: project).map(\.id)
        guard let source = orderedIDs.firstIndex(of: itemID),
              let originalTarget = orderedIDs.firstIndex(of: targetID) else { return }

        orderedIDs.remove(at: source)
        let target = source < originalTarget ? originalTarget - 1 : originalTarget
        orderedIDs.insert(itemID, at: target)
        for (order, id) in orderedIDs.enumerated() {
            guard let itemIndex = items.firstIndex(where: { $0.id == id }) else { continue }
            items[itemIndex].projectSortOrder = order
        }
        projects[projectIndex].usesManualTaskOrder = true
        save()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        projects = snapshot.projects
        let validProjectIDs = Set(projects.map(\.id))
        tags = snapshot.tags
        let validTagIDs = Set(tags.map(\.id))
        projects = projects.map { project in
            guard let tagID = project.tagID, !validTagIDs.contains(tagID) else { return project }
            var copy = project
            copy.tagID = nil
            return copy
        }
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
        settings = snapshot.settings
    }

    private func save() {
        guard !isLoading else { return }
        let snapshot = Snapshot(items: items, projects: projects, tags: tags, settings: settings)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Unable to save DayVDO data: \(error)")
        }
    }

    private func rebuildDayIndex() {
        let calendar = Calendar.current
        var index: [Date: [TodoItem]] = [:]
        for item in items.sorted(by: TodoStore.areInIncreasingOrder) {
            guard let dueDate = item.dueDate else { continue }
            let day = calendar.startOfDay(for: dueDate)
            index[day, default: []].append(item)
        }
        itemsByDay = index
    }

    static func areInIncreasingOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
        if lhs.urgency != rhs.urgency { return lhs.urgency.rawValue > rhs.urgency.rawValue }
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?): return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.createdAt < rhs.createdAt
        }
    }

    private func areProjectItemsInDefaultOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
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
