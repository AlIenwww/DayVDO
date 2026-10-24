import Foundation

struct TodoFilterState: Hashable, Sendable {
    var statuses: Set<TodoItem.Status> = []
    var projectIDs: Set<UUID> = []
    var includesUnassignedProject = false
    var tagIDs: Set<UUID> = []
    var includesUntagged = false
    var priorities: Set<TodoItem.Priority> = []
    var urgencies: Set<TodoItem.Urgency> = []
    var overdueOnly = false
    var date: TodoDateFilter = .any

    var activeCategoryCount: Int {
        [
            !statuses.isEmpty,
            includesUnassignedProject || !projectIDs.isEmpty,
            includesUntagged || !tagIDs.isEmpty,
            !priorities.isEmpty,
            !urgencies.isEmpty,
            overdueOnly,
            date != .any
        ].filter { $0 }.count
    }

    var isActive: Bool { activeCategoryCount > 0 }

    mutating func clear() {
        self = TodoFilterState()
    }

    mutating func sanitize(projectIDs validProjectIDs: Set<UUID>, tagIDs validTagIDs: Set<UUID>) {
        projectIDs.formIntersection(validProjectIDs)
        tagIDs.formIntersection(validTagIDs)
    }

    func includes(
        _ item: TodoItem,
        showCompletedPreference: Bool,
        matchesSearch: Bool = true,
        today: LocalDay? = nil,
        startsOnMonday: Bool = true
    ) -> Bool {
        guard matchesSearch else { return false }
        let matchesStatus = statuses.isEmpty
            ? showCompletedPreference || !item.isCompleted
            : statuses.contains(item.status)
        guard matchesStatus else { return false }

        if includesUnassignedProject || !projectIDs.isEmpty {
            if let projectID = item.projectID {
                guard projectIDs.contains(projectID) else { return false }
            } else if !includesUnassignedProject {
                return false
            }
        }

        if includesUntagged || !tagIDs.isEmpty {
            if let tagID = item.tagID {
                guard tagIDs.contains(tagID) else { return false }
            } else if !includesUntagged {
                return false
            }
        }

        if !priorities.isEmpty, !priorities.contains(item.priority) { return false }
        if !urgencies.isEmpty, !urgencies.contains(item.urgency) { return false }
        if date != .any && !date.includes(item, today: today ?? LocalDay(.now), startsOnMonday: startsOnMonday) {
            return false
        }
        if overdueOnly {
            let referenceDay = today ?? LocalDay(.now)
            guard TaskDateRangePolicy.isOverdue(item, on: referenceDay, today: referenceDay) else { return false }
        }
        return true
    }
}

/// Value criteria shared by date bars, inspectors, schedules and their caches.
/// Non-date-dependent filters keep the same cache identity across midnight.
struct TodoFilterContext: Hashable, Sendable {
    let filter: TodoFilterState
    var showCompleted: Bool
    let referenceDay: LocalDay?
    let weekStartsOnMonday: Bool?

    init(filter: TodoFilterState = .init(), showCompleted: Bool,
         today: LocalDay = LocalDay(.now), startsOnMonday: Bool = true) {
        self.filter = filter
        self.showCompleted = showCompleted
        referenceDay = filter.overdueOnly || filter.date.usesRelativeDate ? today : nil
        weekStartsOnMonday = filter.date.usesWeekStart ? startsOnMonday : nil
    }

    func includes(_ item: TodoItem) -> Bool {
        filter.includes(item, showCompletedPreference: showCompleted,
                        today: referenceDay, startsOnMonday: weekStartsOnMonday ?? true)
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
        let nextExpanded = expandedIDs.subtracting(newlyCompletedProjects).intersection(projectIDs)
        let nextKnown = projectIDs
        let nextCompleted = completedIDs.intersection(projectIDs)
        guard nextExpanded != expandedIDs || nextKnown != knownIDs
                || nextCompleted != self.completedIDs else { return }
        if nextExpanded != expandedIDs { expandedIDs = nextExpanded }
        knownIDs = nextKnown
        self.completedIDs = nextCompleted
        persist()
    }

    private func persist() {
        defaults.set(expandedIDs.map(\.uuidString).sorted(), forKey: expandedKey)
        defaults.set(knownIDs.map(\.uuidString).sorted(), forKey: knownKey)
        defaults.set(completedIDs.map(\.uuidString).sorted(), forKey: completedKey)
    }
}
