import Foundation

private enum LegacyPriority: String, Decodable {
    case high, medium, low
}

/// 解码 v1 与 v2 任务共用的历史字段。
struct LegacyTodoItem<ID: Decodable>: Decodable {
    let id: ID
    let title: String
    let createdAt: Date
    let status: TodoStatus
    let completedAt: Date?
    let reminderAt: Date?
    let reminderSentAt: Date?
    private let priority: LegacyPriority?
    let dueAt: Date?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, status, completedAt
        case reminderAt, reminderSentAt, priority, dueAt, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decodeIfPresent(TodoStatus.self, forKey: .status)
            ?? (completedAt == nil ? .todo : .done)
        reminderAt = try container.decodeIfPresent(Date.self, forKey: .reminderAt)
        reminderSentAt = try container.decodeIfPresent(Date.self, forKey: .reminderSentAt)
        priority = try container.decodeIfPresent(LegacyPriority.self, forKey: .priority)
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func migrated(id: Int64, group: String) -> TodoItem {
        TodoItem(
            id: id,
            group: group,
            title: title,
            important: priority == .high,
            urgent: false,
            createdAt: createdAt,
            status: status,
            completedAt: completedAt,
            reminderAt: reminderAt,
            reminderSentAt: reminderSentAt,
            dueAt: dueAt,
            description: description
        )
    }
}

struct LegacyV2TaskDocument: Decodable {
    let nextID: Int64
    let items: [LegacyV2TodoItem]

    func migrated() -> TaskDocument {
        TaskDocument(nextID: nextID, items: items.map(\.item))
    }
}

struct LegacyV2TodoItem: Decodable {
    let item: TodoItem

    private enum CodingKeys: CodingKey {
        case group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let group = try container.decode(String.self, forKey: .group)
        let legacy = try LegacyTodoItem<Int64>(from: decoder)
        item = legacy.migrated(id: legacy.id, group: group)
    }
}
