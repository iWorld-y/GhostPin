import Foundation
import TodoPinCore
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
}
