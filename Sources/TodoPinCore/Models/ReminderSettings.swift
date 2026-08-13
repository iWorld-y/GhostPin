import Foundation

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var reminderInterval: TimeInterval
    public var quietStartHour: Int
    public var quietEndHour: Int

    public init(
        reminderInterval: TimeInterval = 3600,
        quietStartHour: Int = 0,
        quietEndHour: Int = 0
    ) {
        self.reminderInterval = reminderInterval
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
    }
}
