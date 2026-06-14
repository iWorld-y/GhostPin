import Foundation

public struct TodoItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var completedAt: Date?
    public var source: TodoSource
    public var reminderAt: Date?
    public var reminderSentAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        source: TodoSource,
        reminderAt: Date? = nil,
        reminderSentAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.source = source
        self.reminderAt = reminderAt
        self.reminderSentAt = reminderSentAt
    }

    public var isCompleted: Bool {
        completedAt != nil
    }

    public var hasPendingTimedReminder: Bool {
        reminderAt != nil && reminderSentAt == nil && !isCompleted
    }
}
