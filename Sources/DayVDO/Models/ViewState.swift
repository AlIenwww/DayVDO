import Foundation

enum AllTodosFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "待完成"
    case completed = "已完成"

    var id: String { rawValue }

    func includes(isCompleted: Bool, showCompletedPreference: Bool) -> Bool {
        switch self {
        case .all: showCompletedPreference || !isCompleted
        case .active: !isCompleted
        case .completed: isCompleted
        }
    }
}

enum AllTodosTagFilter: Hashable {
    case all
    case untagged
    case tag(UUID)
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
