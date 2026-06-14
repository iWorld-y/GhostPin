import Foundation
import TodoPinCore
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendHourlyReminder(openItems: [TodoItem]) {
        guard !openItems.isEmpty else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "还有 \(openItems.count) 个待办"
        content.body = openItems.prefix(3).map(\.title).joined(separator: " / ")
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "todopin.hourly.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendTimedReminder(for item: TodoItem) {
        let content = UNMutableNotificationContent()
        content.title = "TodoPin 提醒"
        content.body = item.title
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "todopin.timed.\(item.id.uuidString).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendSummary(_ summary: DailySummary) {
        let content = UNMutableNotificationContent()
        content.title = "TodoPin 今日总结"
        content.body = "新增 \(summary.addedCount)，完成 \(summary.completedCount)，继续保留 \(summary.carriedOpenCount)。"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "todopin.summary.\(summary.dayStart.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
