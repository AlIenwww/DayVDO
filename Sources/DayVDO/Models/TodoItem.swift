import Foundation

struct TodoItem: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Identifiable, Sendable {
        case notStarted
        case inProgress
        case completed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .notStarted: "未开始"
            case .inProgress: "进行中"
            case .completed: "已完成"
            }
        }

        var symbolName: String {
            switch self {
            case .notStarted: "circle"
            case .inProgress: "circle.lefthalf.filled"
            case .completed: "checkmark.circle.fill"
            }
        }
    }

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
            case .canWait: "随意"
            case .today: "尽快"
            case .mustToday: "立刻"
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
    var startDay: LocalDay?
    var dueDay: LocalDay?
    var startDate: Date? {
        get { startDay?.date() }
        set {
            startDay = newValue.map { LocalDay($0) }
            if dueDay == nil { dueDay = startDay }
        }
    }
    var dueDate: Date? {
        get { dueDay?.date() }
        set {
            let previousDueDay = dueDay
            let newDay = newValue.map { LocalDay($0) }
            if newDay == nil || startDay == nil || startDay == previousDueDay {
                startDay = newDay
            }
            dueDay = newDay
        }
    }
    var priority: Priority
    var urgency: Urgency
    var estimatedMinutes: Int?
    var status: Status
    var previousIncompleteStatus: Status
    var isCompleted: Bool {
        get { status == .completed }
        set {
            if newValue {
                if status != .completed {
                    previousIncompleteStatus = status
                }
                status = .completed
            } else if status == .completed {
                status = previousIncompleteStatus == .inProgress ? .inProgress : .notStarted
            }
        }
    }
    var createdAt: Date
    var completedAt: Date?
    var projectID: UUID?
    var projectSortOrder: Int?
    var tagID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        startDate: Date? = nil,
        dueDate: Date? = nil,
        priority: Priority = .none,
        urgency: Urgency = .none,
        estimatedMinutes: Int? = nil,
        isCompleted: Bool = false,
        status: Status? = nil,
        previousIncompleteStatus: Status = .notStarted,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        projectID: UUID? = nil,
        projectSortOrder: Int? = nil,
        tagID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        dueDay = dueDate.map { LocalDay($0) }
        startDay = startDate.map { LocalDay($0) } ?? dueDay
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.urgency = urgency
        self.status = status ?? (isCompleted ? .completed : .notStarted)
        self.previousIncompleteStatus = previousIncompleteStatus == .inProgress ? .inProgress : .notStarted
        if self.status != .completed {
            self.previousIncompleteStatus = self.status
        }
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
        case startDate
        case dueDate
        case priority
        case urgency
        case estimatedMinutes
        case status
        case previousIncompleteStatus
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
        if let day = try? container.decodeIfPresent(LocalDay.self, forKey: .dueDate) {
            dueDay = day
        } else {
            let legacyDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
            dueDay = legacyDate.map { LocalDay($0) }
        }
        if let day = try? container.decodeIfPresent(LocalDay.self, forKey: .startDate) {
            startDay = day
        } else {
            let legacyDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
            startDay = legacyDate.map { LocalDay($0) } ?? dueDay
        }
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        if let estimatedMinutes, estimatedMinutes <= 0 { self.estimatedMinutes = nil }
        urgency = try container.decodeIfPresent(Urgency.self, forKey: .urgency) ?? .none
        let legacyCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        status = try container.decodeIfPresent(Status.self, forKey: .status)
            ?? (legacyCompleted ? .completed : .notStarted)
        let decodedPrevious = try container.decodeIfPresent(Status.self, forKey: .previousIncompleteStatus)
        previousIncompleteStatus = decodedPrevious == .inProgress ? .inProgress : .notStarted
        if status != .completed { previousIncompleteStatus = status }
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
        try container.encodeIfPresent(startDay, forKey: .startDate)
        try container.encodeIfPresent(dueDay, forKey: .dueDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(urgency, forKey: .urgency)
        try container.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encode(status, forKey: .status)
        try container.encode(previousIncompleteStatus, forKey: .previousIncompleteStatus)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(projectSortOrder, forKey: .projectSortOrder)
        try container.encodeIfPresent(tagID, forKey: .tagID)
    }
}

extension TodoItem {
    var hasValidDateRange: Bool {
        switch (startDay, dueDay) {
        case (nil, nil): true
        case let (start?, end?): start <= end
        default: false
        }
    }

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        guard let dueDay else { return false }
        return dueDay == LocalDay(date, timeZone: calendar.timeZone)
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
