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
            case .low: "低"
            case .medium: "中"
            case .high: "高"
            }
        }

        var symbolName: String {
            switch self {
            case .none: "minus"
            case .low: "flag"
            case .medium: "flag.fill"
            case .high: "exclamationmark.2"
            }
        }
    }

    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var priority: Priority
    var isCompleted: Bool
    var createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        priority: Priority = .none,
        isCompleted: Bool = false,
        createdAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
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
