import Foundation

public struct TodoItemPayload: Encodable {
    private let item: TodoItem

    public init(_ item: TodoItem) {
        self.item = item
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case group
        case title
        case createdAt
        case status
        case completedAt
        case reminderAt
        case reminderSentAt
        case important
        case urgent
        case dueAt
        case description
        case isCompleted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item.id, forKey: .id)
        try container.encode(item.group, forKey: .group)
        try container.encode(item.title, forKey: .title)
        try container.encode(item.createdAt, forKey: .createdAt)
        try container.encode(item.status, forKey: .status)
        try container.encode(item.completedAt, forKey: .completedAt)
        try container.encode(item.reminderAt, forKey: .reminderAt)
        try container.encode(item.reminderSentAt, forKey: .reminderSentAt)
        try container.encode(item.important, forKey: .important)
        try container.encode(item.urgent, forKey: .urgent)
        try container.encode(item.dueAt, forKey: .dueAt)
        try container.encode(item.description, forKey: .description)
        try container.encode(item.isCompleted, forKey: .isCompleted)
    }
}
