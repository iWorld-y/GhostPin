import Foundation
import TodoPinCore

final class ReminderService {
    private let todoStore: TodoStore
    private let summaryStore: SummaryStore
    private let preferences: AppPreferences
    private let notificationService: NotificationService
    private let policy = ReminderPolicy()
    private var timer: Timer?
    private var lastReminderAt: Date?

    init(
        todoStore: TodoStore,
        summaryStore: SummaryStore,
        preferences: AppPreferences,
        notificationService: NotificationService
    ) {
        self.todoStore = todoStore
        self.summaryStore = summaryStore
        self.preferences = preferences
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
        let openItems = todoStore.openItems()
        let dueTimedItems = openItems.filter { item in
            guard let reminderAt = item.reminderAt else {
                return false
            }
            return item.reminderSentAt == nil && reminderAt <= now
        }

        var didSendTimedReminder = false
        for item in dueTimedItems {
            notificationService.sendTimedReminder(for: item)
            didSendTimedReminder = true
            do {
                try todoStore.markTimedReminderSent(item.id, at: now)
            } catch {
                // Runtime reminders should never interrupt adding todos.
            }
        }

        if didSendTimedReminder {
            lastReminderAt = now
        }

        let hourlyItems = openItems.filter { item in
            guard let reminderAt = item.reminderAt else {
                return true
            }
            return reminderAt <= now
        }

        if policy.shouldSendHourlyReminder(
            openItemCount: hourlyItems.count,
            oldestOpenItemCreatedAt: hourlyItems.map(\.createdAt).min(),
            now: now,
            lastReminderAt: lastReminderAt,
            settings: preferences.reminderSettings
        ) {
            notificationService.sendHourlyReminder(openItems: hourlyItems)
            lastReminderAt = now
        }

        do {
            try summaryStore.generateMissingSummaries(upTo: now, todos: todoStore.items)
            let lastSummaryDay = summaryStore.summary(for: now)?.dayStart
            if policy.shouldGenerateDailySummary(
                now: now,
                lastSummaryDay: lastSummaryDay,
                settings: preferences.reminderSettings
            ) {
                let summary = try summaryStore.generateSummary(for: now, todos: todoStore.items, generatedAt: now)
                notificationService.sendSummary(summary)
            }
        } catch {
            // Runtime reminders should never interrupt adding todos.
        }
    }
}
