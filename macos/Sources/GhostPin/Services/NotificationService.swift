import Foundation
import GhostPinCore
import UserNotifications

final class NotificationService {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendTimedReminder(for item: TodoItem) {
        let content = UNMutableNotificationContent()
        content.title = "GhostPin 提醒"
        content.body = item.title
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "ghostpin.timed.\(item.id.uuidString).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
