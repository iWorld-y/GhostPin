import Foundation

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var reminderInterval: TimeInterval
    public var quietStartHour: Int
    public var quietEndHour: Int
    public var summaryHour: Int
    public var summaryMinute: Int

    public init(
        reminderInterval: TimeInterval = 3600,
        quietStartHour: Int = 0,
        quietEndHour: Int = 0,
        summaryHour: Int = 21,
        summaryMinute: Int = 30
    ) {
        self.reminderInterval = reminderInterval
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
        self.summaryHour = summaryHour
        self.summaryMinute = summaryMinute
    }
}
