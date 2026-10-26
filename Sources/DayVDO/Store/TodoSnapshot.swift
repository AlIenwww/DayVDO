import Foundation

struct TodoSnapshot: Codable, Sendable, Equatable {
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
              Set(items.map(\.id)).count == items.count,
              Set(projects.map(\.id)).count == projects.count,
              Set(tags.map(\.id)).count == tags.count else {
            throw DecodingError.dataCorruptedError(forKey: .schedules, in: container, debugDescription: "Invalid schedule or duplicate identifier")
        }
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}

struct TodoLoadResult: Sendable {
    var snapshot: TodoSnapshot?
    var recoverySnapshot: TodoSnapshot?
    var recoveryDate: Date?
    var failedPrimary = false
}

