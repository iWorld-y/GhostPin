import Foundation

/// 只解析历史 UUID 任务；新任务不使用旧格式的默认值。
struct LegacyTodoItem: Decodable {
    let id: UUID
    let title: String
    let createdAt: Date
    let status: TodoStatus
    let completedAt: Date?
    let reminderAt: Date?
    let reminderSentAt: Date?
    let priority: Priority
    let dueAt: Date?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, createdAt, status, completedAt
        case reminderAt, reminderSentAt, priority, dueAt, description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        status = try container.decodeIfPresent(TodoStatus.self, forKey: .status)
            ?? (completedAt == nil ? .todo : .done)
        reminderAt = try container.decodeIfPresent(Date.self, forKey: .reminderAt)
        reminderSentAt = try container.decodeIfPresent(Date.self, forKey: .reminderSentAt)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    func migrated(id: Int64) -> TodoItem {
        TodoItem(
            id: id,
            group: TaskGroup.defaultName,
            title: title,
            createdAt: createdAt,
            status: status,
            completedAt: completedAt,
            reminderAt: reminderAt,
            reminderSentAt: reminderSentAt,
            priority: priority,
            dueAt: dueAt,
            description: description
        )
    }
}
