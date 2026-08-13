import Foundation

public struct ReminderPolicy: Sendable {
    public init() {}

    public func isInQuietHours(
        _ date: Date,
        settings: ReminderSettings,
        calendar: Calendar = .current
    ) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let start = settings.quietStartHour
        let end = settings.quietEndHour

        if start == end {
            return false
        }

        if start < end {
            return hour >= start && hour < end
        }

        return hour >= start || hour < end
    }

    public func shouldSendHourlyReminder(
        openItemCount: Int,
        oldestOpenItemCreatedAt: Date? = nil,
        now: Date,
        lastReminderAt: Date?,
        settings: ReminderSettings = ReminderSettings(),
        calendar: Calendar = .current
    ) -> Bool {
        guard openItemCount > 0 else {
            return false
        }
        guard !isInQuietHours(now, settings: settings, calendar: calendar) else {
            return false
        }
        guard let lastReminderAt else {
            guard let oldestOpenItemCreatedAt else {
                return true
            }
            return now.timeIntervalSince(oldestOpenItemCreatedAt) >= settings.reminderInterval
        }
        return now.timeIntervalSince(lastReminderAt) >= settings.reminderInterval
    }
}
