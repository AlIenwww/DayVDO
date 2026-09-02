import Foundation

struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    enum Priority: Int, Codable, CaseIterable, Identifiable, Sendable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .none: "无"
            case .low: "可做"
            case .medium: "需做"
            case .high: "必做"
            }
        }

        var symbolName: String {
            switch self {
            case .none: "minus"
            case .low: "flag"
            case .medium: "flag.fill"
            case .high: "flag.fill"
            }
        }
    }

    enum Urgency: Int, Codable, CaseIterable, Identifiable, Sendable {
        case none = 0
        case canWait = 1
        case today = 2
        case mustToday = 3

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .none: "无"
            case .canWait: "改天也没关系"
            case .today: "最好当天完成"
            case .mustToday: "当天必须完成"
            }
        }

        var symbolName: String {
            switch self {
            case .none: "minus"
            case .canWait: "clock"
            case .today: "clock.badge.exclamationmark"
            case .mustToday: "exclamationmark.triangle.fill"
            }
        }
    }

    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var priority: Priority
    var urgency: Urgency
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?
    var projectID: UUID?
    var projectSortOrder: Int?
    var tagID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        priority: Priority = .none,
        urgency: Urgency = .none,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        projectID: UUID? = nil,
        projectSortOrder: Int? = nil,
        tagID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.urgency = urgency
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.projectID = projectID
        self.projectSortOrder = projectSortOrder
        self.tagID = tagID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case dueDate
        case priority
        case urgency
        case isCompleted
        case createdAt
        case completedAt
        case projectID
        case projectSortOrder
        case tagID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        urgency = try container.decodeIfPresent(Urgency.self, forKey: .urgency) ?? .none
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        projectSortOrder = try container.decodeIfPresent(Int.self, forKey: .projectSortOrder)
        tagID = try container.decodeIfPresent(UUID.self, forKey: .tagID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(urgency, forKey: .urgency)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(projectSortOrder, forKey: .projectSortOrder)
        try container.encodeIfPresent(tagID, forKey: .tagID)
    }
}

extension TodoItem {
    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return calendar.isDate(dueDate, inSameDayAs: date)
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
