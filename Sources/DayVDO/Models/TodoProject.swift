import Foundation

struct TodoProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var notes: String
    var dueDay: LocalDay?
    var dueDate: Date? {
        get { dueDay?.date() }
        set { dueDay = newValue.map { LocalDay($0) } }
    }
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
        dueDay = dueDate.map { LocalDay($0) }
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
        if let day = try? container.decodeIfPresent(LocalDay.self, forKey: .dueDate) {
            dueDay = day
        } else {
            let legacyDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
            dueDay = legacyDate.map { LocalDay($0) }
        }
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        usesManualTaskOrder = try container.decodeIfPresent(
            Bool.self,
            forKey: .usesManualTaskOrder
        ) ?? false
        tagID = try container.decodeIfPresent(UUID.self, forKey: .tagID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(dueDay, forKey: .dueDate)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(usesManualTaskOrder, forKey: .usesManualTaskOrder)
        try container.encodeIfPresent(tagID, forKey: .tagID)
    }

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
