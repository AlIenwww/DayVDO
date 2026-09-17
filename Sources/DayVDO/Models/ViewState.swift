import Foundation

struct AllTodosFilterState: Equatable {
    var statuses: Set<TodoItem.Status> = []
    var projectIDs: Set<UUID> = []
    var includesUnassignedProject = false
    var tagIDs: Set<UUID> = []
    var includesUntagged = false
    var priorities: Set<TodoItem.Priority> = []
    var urgencies: Set<TodoItem.Urgency> = []
    var overdueOnly = false

    var activeCategoryCount: Int {
        [
            !statuses.isEmpty,
            includesUnassignedProject || !projectIDs.isEmpty,
            includesUntagged || !tagIDs.isEmpty,
            !priorities.isEmpty,
            !urgencies.isEmpty,
            overdueOnly
        ].filter { $0 }.count
    }

    var isActive: Bool { activeCategoryCount > 0 }

    mutating func clear() {
        self = AllTodosFilterState()
    }

    mutating func sanitize(projectIDs validProjectIDs: Set<UUID>, tagIDs validTagIDs: Set<UUID>) {
        projectIDs.formIntersection(validProjectIDs)
        tagIDs.formIntersection(validTagIDs)
    }

    func includes(
        _ item: TodoItem,
        showCompletedPreference: Bool,
        matchesSearch: Bool = true,
        today: LocalDay = LocalDay(.now)
    ) -> Bool {
        guard matchesSearch else { return false }
        let matchesStatus = statuses.isEmpty
            ? showCompletedPreference || !item.isCompleted
            : statuses.contains(item.status)
        guard matchesStatus else { return false }

        if includesUnassignedProject || !projectIDs.isEmpty {
            guard let projectID = item.projectID
            else { return includesUnassignedProject }
            guard projectIDs.contains(projectID) else { return false }
        }

        if includesUntagged || !tagIDs.isEmpty {
            guard let tagID = item.tagID
            else { return includesUntagged }
            guard tagIDs.contains(tagID) else { return false }
        }

        if !priorities.isEmpty, !priorities.contains(item.priority) { return false }
        if !urgencies.isEmpty, !urgencies.contains(item.urgency) { return false }
        if overdueOnly,
           !TaskDateRangePolicy.isOverdue(item, on: today, today: today) { return false }
        return true
    }
}

@MainActor
final class ProjectExpansionState: ObservableObject {
    @Published private(set) var expandedIDs: Set<UUID>

    private var knownIDs: Set<UUID>
    private var completedIDs: Set<UUID>
    private let defaults: UserDefaults
    private let expandedKey = "DayVDO.expandedProjectIDs"
    private let knownKey = "DayVDO.knownProjectIDs"
    private let completedKey = "DayVDO.completedProjectIDs"
    private let behaviorVersionKey = "DayVDO.projectExpansionBehaviorVersion"
    private let currentBehaviorVersion = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        expandedIDs = Set(
            (defaults.stringArray(forKey: expandedKey) ?? []).compactMap(UUID.init(uuidString:))
        )
        knownIDs = Set(
            (defaults.stringArray(forKey: knownKey) ?? []).compactMap(UUID.init(uuidString:))
        )
        completedIDs = Set(
            (defaults.stringArray(forKey: completedKey) ?? []).compactMap(UUID.init(uuidString:))
        )
        if defaults.integer(forKey: behaviorVersionKey) < currentBehaviorVersion {
            // Earlier builds automatically expanded every new active project. Those entries
            // cannot be distinguished from a deliberate choice, so reset them once when
            // switching to the new default-collapsed behavior.
            expandedIDs.removeAll()
            defaults.set(currentBehaviorVersion, forKey: behaviorVersionKey)
            defaults.set([String](), forKey: expandedKey)
        }
    }

    func isExpanded(_ id: UUID) -> Bool {
        expandedIDs.contains(id)
    }

    func setExpanded(_ expanded: Bool, for id: UUID) {
        knownIDs.insert(id)
        if expanded {
            expandedIDs.insert(id)
        } else {
            expandedIDs.remove(id)
        }
        persist()
    }

    func synchronize(projectIDs: Set<UUID>, completedIDs: Set<UUID>) {
        let newlyCompletedProjects = completedIDs.subtracting(self.completedIDs)
        expandedIDs.subtract(newlyCompletedProjects)
        expandedIDs.formIntersection(projectIDs)
        knownIDs.formUnion(projectIDs)
        knownIDs.formIntersection(projectIDs)
        self.completedIDs = completedIDs.intersection(projectIDs)
        persist()
    }

    private func persist() {
        defaults.set(expandedIDs.map(\.uuidString).sorted(), forKey: expandedKey)
        defaults.set(knownIDs.map(\.uuidString).sorted(), forKey: knownKey)
        defaults.set(completedIDs.map(\.uuidString).sorted(), forKey: completedKey)
    }
}
