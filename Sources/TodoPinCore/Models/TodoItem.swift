import Foundation

public struct TodoItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var completedAt: Date?
    public var source: TodoSource
    public var reminderAt: Date?
    public var reminderSentAt: Date?
    public var priority: Priority
    public var dueAt: Date?
    public var description: String?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        source: TodoSource,
        reminderAt: Date? = nil,
        reminderSentAt: Date? = nil,
        priority: Priority = .medium,
        dueAt: Date? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.source = source
        self.reminderAt = reminderAt
        self.reminderSentAt = reminderSentAt
        self.priority = priority
        self.dueAt = dueAt
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.source = try container.decode(TodoSource.self, forKey: .source)
        self.reminderAt = try container.decodeIfPresent(Date.self, forKey: .reminderAt)
        self.reminderSentAt = try container.decodeIfPresent(Date.self, forKey: .reminderSentAt)
        self.priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        self.dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    public var isCompleted: Bool {
        completedAt != nil
    }

    public var hasPendingTimedReminder: Bool {
        reminderAt != nil && reminderSentAt == nil && !isCompleted
    }

    public func isOverdue(now: Date = Date()) -> Bool {
        guard let dueAt, !isCompleted else {
            return false
        }
        return dueAt < now
    }
}
