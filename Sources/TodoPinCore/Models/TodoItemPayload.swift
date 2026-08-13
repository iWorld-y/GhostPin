import Foundation

public struct TodoItemPayload: Encodable {
    private let item: TodoItem

    public init(_ item: TodoItem) {
        self.item = item
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case completedAt
        case reminderAt
        case reminderSentAt
        case priority
        case dueAt
        case description
        case isCompleted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item.id, forKey: .id)
        try container.encode(item.title, forKey: .title)
        try container.encode(item.createdAt, forKey: .createdAt)
        try container.encode(item.completedAt, forKey: .completedAt)
        try container.encode(item.reminderAt, forKey: .reminderAt)
        try container.encode(item.reminderSentAt, forKey: .reminderSentAt)
        try container.encode(item.priority, forKey: .priority)
        try container.encode(item.dueAt, forKey: .dueAt)
        try container.encode(item.description, forKey: .description)
        try container.encode(item.isCompleted, forKey: .isCompleted)
    }
}
