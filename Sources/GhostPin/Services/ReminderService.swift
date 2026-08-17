import Foundation
import GhostPinCore

final class ReminderService {
    private let todoStore: TodoStore
    private let notificationService: NotificationService
    private var timer: Timer?

    init(
        todoStore: TodoStore,
        notificationService: NotificationService
    ) {
        self.todoStore = todoStore
        self.notificationService = notificationService
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func evaluate(now: Date = Date()) {
        let dueTimedItems = todoStore.openItems().filter { item in
            guard let reminderAt = item.reminderAt else {
                return false
            }
            return item.reminderSentAt == nil && reminderAt <= now
        }

        for item in dueTimedItems {
            notificationService.sendTimedReminder(for: item)
            do {
                try todoStore.markTimedReminderSent(item.id, at: now)
            } catch {
                // Runtime reminders should never interrupt adding todos.
            }
        }
    }
}
