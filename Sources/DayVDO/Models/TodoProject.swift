import Foundation

struct TodoProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var createdAt: Date
    var sortOrder: Int
    var usesManualTaskOrder: Bool
    var tagID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        createdAt: Date = .now,
        sortOrder: Int = 0,
        usesManualTaskOrder: Bool = false,
        tagID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.usesManualTaskOrder = usesManualTaskOrder
        self.tagID = tagID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case dueDate
        case createdAt
        case sortOrder
        case usesManualTaskOrder
        case tagID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        usesManualTaskOrder = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesManualTaskOrder
        ) ?? false
        tagID = try container.decodeIfPresent(UUID.self, forKey: .tagID)
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
