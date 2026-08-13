import Combine
import Foundation
import TodoPinCore

struct CheckFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

typealias Check = (name: String, run: () throws -> Void)

let checkCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "zh_CN")
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    return calendar
}()
let policy = ReminderPolicy()
let settings = ReminderSettings(reminderInterval: 3600, quietStartHour: 0, quietEndHour: 0)
let timeParser = TodoTimeParser(calendar: checkCalendar)

let checks: [Check] = [
    ("TodoStore.add trims title and ignores empty input", checkAddTrimsTitleAndIgnoresEmptyInput),
    ("TodoStore orders open items by createdAt descending", checkOpenItemsAreCreatedAtDescending),
    ("TodoStore.updateTitle trims persists and ignores empty input", checkUpdateTitleTrimsPersistsAndIgnoresEmptyInput),
    ("TodoStore.add persists reminder time", checkAddPersistsReminderTime),
    ("TodoStore.markTimedReminderSent persists sent time", checkMarkTimedReminderSentPersists),
    ("TodoStore.update changes reminder time and clears sent time", checkUpdateChangesReminderTimeAndClearsSentTime),
    ("TodoStore.update removes reminder time and clears sent time", checkUpdateRemovesReminderTimeAndClearsSentTime),
    ("TodoStore.setCompleted removes items from openItems", checkCompletedItemsAreRemovedFromOpenItems),
    ("TodoStore.hudItems filters today scope by day boundary", checkHudItemsTodayScopeUsesDayBoundary),
    ("TodoStore.hudItems all scope includes every open item", checkHudItemsAllScopeIncludesEveryOpenItem),
    ("TodoStore.hudItems truncates to maxCount keeping newest first", checkHudItemsTruncatesToMaxCount),
    ("TodoStore.hudItems excludes completed items", checkHudItemsExcludesCompletedItems),
    ("TodoStore.load reflects external file changes", checkLoadReflectsExternalChange),
    ("TodoStore.load skips publish when content unchanged", checkLoadSkipsPublishWhenUnchanged),
    ("TodoStore.load clears items when file missing", checkLoadClearsItemsWhenFileMissing),
    ("ReminderPolicy does not remind with no open items", checkDoesNotRemindWhenThereAreNoOpenItems),
    ("ReminderPolicy does not immediately remind for new todo", checkDoesNotImmediatelyRemindForNewTodo),
    ("ReminderPolicy reminds after one hour", checkRemindsAfterTodoHasBeenOpenForOneHour),
    ("ReminderPolicy does not repeat before interval", checkDoesNotRepeatBeforeIntervalAfterReminder),
    ("ReminderPolicy repeats after one hour since last reminder", checkRepeatsAfterOneHourSinceLastReminder),
    ("HotKeyShortcut has stable defaults", checkHotKeyShortcutDefaults),
    ("HotKeyShortcut migrates legacy presets", checkHotKeyShortcutLegacyMigration),
    ("TodoTimeParser parses relative Chinese reminders", checkParsesRelativeChineseReminder),
    ("TodoTimeParser parses afternoon half-hour reminders", checkParsesAfternoonHalfHourReminder),
    ("TodoTimeParser parses absolute date reminders", checkParsesAbsoluteDateReminder),
    ("TodoTimeParser moves elapsed time-only reminders to tomorrow", checkMovesElapsedTimeOnlyReminderToTomorrow)
]

var failures: [String] = []

for check in checks {
    do {
        try check.run()
        print("PASS \(check.name)")
    } catch {
        failures.append("\(check.name): \(error)")
        print("FAIL \(check.name): \(error)")
    }
}

if failures.isEmpty {
    print("All \(checks.count) TodoPinCore checks passed.")
} else {
    print("\(failures.count) TodoPinCore checks failed.")
    exit(1)
}

func checkAddTrimsTitleAndIgnoresEmptyInput() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)

    let empty = try store.add(title: "   \n  ", source: .text)
    try check(empty == nil, "empty input should not create a todo")
    try check(store.items.isEmpty, "store should stay empty")

    let item = try require(try store.add(title: "  买牛奶  ", source: .text), "expected a todo")
    try check(item.title == "买牛奶", "title should be trimmed")
    try check(store.items.map(\.title) == ["买牛奶"], "store should contain trimmed title")
}

func checkOpenItemsAreCreatedAtDescending() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let older = makeDate(year: 2026, month: 6, day: 14, hour: 9, minute: 0)
    let newer = makeDate(year: 2026, month: 6, day: 14, hour: 10, minute: 0)

    _ = try store.add(title: "早一点", source: .text, createdAt: older)
    _ = try store.add(title: "晚一点", source: .text, createdAt: newer)

    try check(store.openItems().map(\.title) == ["晚一点", "早一点"], "newer todos should be listed first")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.openItems().map(\.title) == ["晚一点", "早一点"], "loaded todos should stay newest first")
}

func checkUpdateTitleTrimsPersistsAndIgnoresEmptyInput() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let item = try require(try store.add(title: "旧标题", source: .text), "expected a todo")

    let updated = try require(try store.updateTitle(item.id, title: "  新标题  "), "expected an updated todo")
    try check(updated.title == "新标题", "updated title should be trimmed")
    try check(store.items.first?.title == "新标题", "store should update title")

    let empty = try store.updateTitle(item.id, title: "   ")
    try check(empty == nil, "empty update should be ignored")
    try check(store.items.first?.title == "新标题", "empty update should not overwrite title")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.title == "新标题", "updated title should persist")
}

func checkCompletedItemsAreRemovedFromOpenItems() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let first = try require(try store.add(title: "完成的事", source: .text), "expected first todo")
    let second = try require(try store.add(title: "继续保留", source: .voice), "expected second todo")

    try store.setCompleted(first.id, completed: true)

    try check(store.openItems() == [second], "completed todo should not be open")
}

func checkAddPersistsReminderTime() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let reminderAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 30)

    let item = try require(try store.add(title: "开会", source: .text, reminderAt: reminderAt), "expected a todo")
    try check(item.reminderAt == reminderAt, "todo should keep reminder time")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.reminderAt == reminderAt, "reminder time should persist")
}

func checkMarkTimedReminderSentPersists() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let reminderAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 30)
    let sentAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 31)
    let item = try require(try store.add(title: "开会", source: .text, reminderAt: reminderAt), "expected a todo")

    try store.markTimedReminderSent(item.id, at: sentAt)

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.reminderSentAt == sentAt, "sent time should persist")
}

func checkUpdateChangesReminderTimeAndClearsSentTime() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let originalReminderAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 30)
    let sentAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 31)
    let changedReminderAt = makeDate(year: 2026, month: 6, day: 21, hour: 9, minute: 0)
    let item = try require(try store.add(title: "开会", source: .text, reminderAt: originalReminderAt), "expected a todo")
    try store.markTimedReminderSent(item.id, at: sentAt)

    let updated = try require(
        try store.update(item.id, title: "  改时间开会  ", reminderAt: changedReminderAt),
        "expected updated todo"
    )

    try check(updated.title == "改时间开会", "updated title should be trimmed")
    try check(updated.reminderAt == changedReminderAt, "reminder time should change")
    try check(updated.reminderSentAt == nil, "changed reminder time should clear sent time")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.reminderAt == changedReminderAt, "changed reminder time should persist")
    try check(reloaded.items.first?.reminderSentAt == nil, "cleared sent time should persist")
}

func checkUpdateRemovesReminderTimeAndClearsSentTime() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let reminderAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 30)
    let sentAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 31)
    let item = try require(try store.add(title: "开会", source: .text, reminderAt: reminderAt), "expected a todo")
    try store.markTimedReminderSent(item.id, at: sentAt)

    let updated = try require(try store.update(item.id, title: "开会", reminderAt: nil), "expected updated todo")

    try check(updated.reminderAt == nil, "reminder time should be removed")
    try check(updated.reminderSentAt == nil, "removed reminder should clear sent time")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.reminderAt == nil, "removed reminder time should persist")
    try check(reloaded.items.first?.reminderSentAt == nil, "cleared sent time should persist")
}

func checkDoesNotRemindWhenThereAreNoOpenItems() throws {
    let now = Date(timeIntervalSinceReferenceDate: 10_000)

    try check(!policy.shouldSendHourlyReminder(
        openItemCount: 0,
        oldestOpenItemCreatedAt: now.addingTimeInterval(-7200),
        now: now,
        lastReminderAt: nil,
        settings: settings
    ), "zero open items should not remind")
}

func checkDoesNotImmediatelyRemindForNewTodo() throws {
    let now = Date(timeIntervalSinceReferenceDate: 10_000)

    try check(!policy.shouldSendHourlyReminder(
        openItemCount: 1,
        oldestOpenItemCreatedAt: now.addingTimeInterval(-3599),
        now: now,
        lastReminderAt: nil,
        settings: settings
    ), "new todo should wait for one hour")
}

func checkRemindsAfterTodoHasBeenOpenForOneHour() throws {
    let now = Date(timeIntervalSinceReferenceDate: 10_000)

    try check(policy.shouldSendHourlyReminder(
        openItemCount: 1,
        oldestOpenItemCreatedAt: now.addingTimeInterval(-3600),
        now: now,
        lastReminderAt: nil,
        settings: settings
    ), "todo open for one hour should remind")
}

func checkDoesNotRepeatBeforeIntervalAfterReminder() throws {
    let now = Date(timeIntervalSinceReferenceDate: 10_000)

    try check(!policy.shouldSendHourlyReminder(
        openItemCount: 1,
        oldestOpenItemCreatedAt: now.addingTimeInterval(-7200),
        now: now,
        lastReminderAt: now.addingTimeInterval(-3599),
        settings: settings
    ), "reminder should not repeat before one hour")
}

func checkRepeatsAfterOneHourSinceLastReminder() throws {
    let now = Date(timeIntervalSinceReferenceDate: 10_000)

    try check(policy.shouldSendHourlyReminder(
        openItemCount: 1,
        oldestOpenItemCreatedAt: now.addingTimeInterval(-7200),
        now: now,
        lastReminderAt: now.addingTimeInterval(-3600),
        settings: settings
    ), "reminder should repeat after one hour")
}

func checkHotKeyShortcutDefaults() throws {
    try check(HotKeyShortcut.defaultShortcut.displayName == "Option + Space", "default shortcut should be Option + Space")
    try check(HotKeyShortcut.defaultShortcut.keyCode == 49, "default shortcut should use Space key code")
    try check(HotKeyShortcut.defaultShortcut.modifiers == 2_048, "default shortcut should use Option modifier")
    try check(HotKeyShortcut.defaultTextShortcut == .optionSpace, "text shortcut should default to Option + Space")
    try check(HotKeyShortcut.defaultVoiceShortcut == .f8, "voice shortcut should default to F8")
    try check(HotKeyShortcut.defaultTextShortcut != HotKeyShortcut.defaultVoiceShortcut, "text and voice defaults should not conflict")
}

func checkHotKeyShortcutLegacyMigration() throws {
    try check(HotKeyShortcut.legacyPreset(rawValue: "optionSpace") == .optionSpace, "legacy optionSpace should migrate")
    try check(HotKeyShortcut.legacyPreset(rawValue: "optionN") == .optionN, "legacy optionN should migrate")
    try check(HotKeyShortcut.legacyPreset(rawValue: "f8") == .f8, "legacy f8 should migrate")
    try check(HotKeyShortcut.legacyPreset(rawValue: "missing") == nil, "unknown legacy shortcut should not migrate")
}

func checkParsesRelativeChineseReminder() throws {
    let now = makeDate(year: 2026, month: 6, day: 14, hour: 8, minute: 0)
    let parsed = try require(timeParser.parse("明天9点提醒我交材料", now: now), "expected reminder time")
    try check(parsed.date == makeDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0), "should parse tomorrow at 9")
}

func checkParsesAfternoonHalfHourReminder() throws {
    let now = makeDate(year: 2026, month: 6, day: 14, hour: 8, minute: 0)
    let parsed = try require(timeParser.parse("下午3点半联系客户", now: now), "expected reminder time")
    try check(parsed.date == makeDate(year: 2026, month: 6, day: 14, hour: 15, minute: 30), "should parse afternoon half-hour")
}

func checkParsesAbsoluteDateReminder() throws {
    let now = makeDate(year: 2026, month: 6, day: 14, hour: 8, minute: 0)
    let parsed = try require(timeParser.parse("2026-06-20 10:30 复查", now: now), "expected reminder time")
    try check(parsed.date == makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 30), "should parse absolute date")
}

func checkMovesElapsedTimeOnlyReminderToTomorrow() throws {
    let now = makeDate(year: 2026, month: 6, day: 14, hour: 10, minute: 0)
    let parsed = try require(timeParser.parse("9点提醒我", now: now), "expected reminder time")
    try check(parsed.date == makeDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0), "elapsed time-only reminder should move to tomorrow")
}

func checkHudItemsTodayScopeUsesDayBoundary() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try require(
        try store.add(title: "今天任务", source: .text, createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 1, minute: 0)),
        "expected today todo"
    )
    _ = try require(
        try store.add(title: "昨天任务", source: .text, createdAt: makeDate(year: 2026, month: 6, day: 14, hour: 23, minute: 59)),
        "expected yesterday todo"
    )

    let hudItems = store.hudItems(scope: .today, maxCount: 10, now: now, calendar: checkCalendar)
    try check(hudItems.map(\.title) == ["今天任务"], "today scope should only include items created today")
}

func checkHudItemsAllScopeIncludesEveryOpenItem() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try require(
        try store.add(title: "今天任务", source: .text, createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 1, minute: 0)),
        "expected today todo"
    )
    _ = try require(
        try store.add(title: "昨天任务", source: .text, createdAt: makeDate(year: 2026, month: 6, day: 14, hour: 23, minute: 59)),
        "expected yesterday todo"
    )

    let hudItems = store.hudItems(scope: .all, maxCount: 10, now: now, calendar: checkCalendar)
    try check(hudItems.map(\.title) == ["今天任务", "昨天任务"], "all scope should include every open item")
}

func checkHudItemsTruncatesToMaxCount() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    for index in 1...5 {
        _ = try require(
            try store.add(
                title: "任务\(index)",
                source: .text,
                createdAt: makeDate(year: 2026, month: 6, day: 15, hour: index, minute: 0)
            ),
            "expected todo"
        )
    }

    let hudItems = store.hudItems(scope: .all, maxCount: 3, now: now, calendar: checkCalendar)
    try check(hudItems.count == 3, "hudItems should truncate to maxCount")
    try check(hudItems.map(\.title) == ["任务5", "任务4", "任务3"], "hudItems should keep newest first")
}

func checkHudItemsExcludesCompletedItems() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    let completedItem = try require(try store.add(title: "待完成", source: .text), "expected todo")
    _ = try require(try store.add(title: "保留", source: .text), "expected todo")
    try store.setCompleted(completedItem.id, completed: true)

    let hudItems = store.hudItems(scope: .all, maxCount: 10, now: now, calendar: checkCalendar)
    try check(hudItems.map(\.title) == ["保留"], "completed items should disappear from HUD")
}

func checkLoadReflectsExternalChange() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    _ = try require(try store.add(title: "初始任务", source: .text), "expected todo")

    let external = makeStore(in: temporaryDirectory)
    try external.load()
    _ = try require(try external.add(title: "外部任务", source: .text), "expected external todo")

    try store.load()
    try check(store.items.map(\.title) == ["外部任务", "初始任务"], "load should reflect external change")
}

func checkLoadSkipsPublishWhenUnchanged() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    _ = try require(try store.add(title: "任务", source: .text), "expected todo")

    var publishCount = 0
    let cancellable = store.objectWillChange.sink { publishCount += 1 }

    try store.load()
    try check(publishCount == 0, "load with unchanged content should not publish")
    try check(store.items.map(\.title) == ["任务"], "items should stay intact")
    withExtendedLifetime(cancellable) {}
}

func checkLoadClearsItemsWhenFileMissing() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    _ = try require(try store.add(title: "任务", source: .text), "expected todo")

    try FileManager.default.removeItem(at: temporaryDirectory.appendingPathComponent("todos.json"))

    try store.load()
    try check(store.items.isEmpty, "load should clear items when file missing")
}

func makeStore(in temporaryDirectory: URL) -> TodoStore {
    TodoStore(fileURL: temporaryDirectory.appendingPathComponent("todos.json"))
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("TodoPinChecks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw CheckFailure(message: message)
    }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
        throw CheckFailure(message: message)
    }
    return value
}

func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    let components = DateComponents(
        calendar: checkCalendar,
        timeZone: checkCalendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    )
    return checkCalendar.date(from: components)!
}
