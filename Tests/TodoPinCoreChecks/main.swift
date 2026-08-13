import Combine
import Foundation
import TodoPinCore
import TodoPinMCP

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
    ("TodoItem decodes legacy data with default priority", checkDecodesLegacyTodoItemWithoutNewFields),
    ("TodoStore sorts open items by priority then due date", checkSortsOpenItemsByPriorityThenDueDate),
    ("TodoStore sinks overdue items to bottom", checkSortsOverdueItemsToBottom),
    ("TodoStore sorts items without due date after those with", checkSortsItemsWithoutDueDateLast),
    ("MCP create_task accepts priority due_at description", checkMCPCreateTaskWithNewFields),
    ("MCP update_task changes priority due_at and clears due", checkMCPUpdateTaskWithNewFields),
    ("MCP rejects invalid priority and due_at", checkMCPInvalidPriorityAndDueDate),
    ("TodoStore.load reflects external file changes", checkLoadReflectsExternalChange),
    ("TodoStore.load skips publish when content unchanged", checkLoadSkipsPublishWhenUnchanged),
    ("TodoStore.load clears items when file missing", checkLoadClearsItemsWhenFileMissing),
    ("MCP JSONValue and MCPID codec round-trips", checkMCPCodecRoundTrips),
    ("MCP parse error maps to -32700 with null id", checkMCPParseError),
    ("MCP unknown method maps to -32601", checkMCPUnknownMethod),
    ("MCP initialize handshake and ping", checkMCPInitializeHandshake),
    ("MCP tools/list declares six tools with schemas", checkMCPToolsList),
    ("MCP tool lifecycle create list complete uncomplete update delete", checkMCPToolLifecycle),
    ("MCP tool errors use isError and -32602 layering", checkMCPToolErrors),
    ("MCP reads fresh store on every call", checkMCPFreshStore),
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

func checkDecodesLegacyTodoItemWithoutNewFields() throws {
    let item = TodoItem(title: "旧任务", source: .text, reminderAt: nil)
    let data = try JSONEncoder().encode(item)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CheckFailure(message: "编码失败")
    }
    object.removeValue(forKey: "priority")
    object.removeValue(forKey: "dueAt")
    object.removeValue(forKey: "description")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(TodoItem.self, from: legacyData)
    try check(decoded.title == "旧任务", "旧数据标题应保留")
    try check(decoded.priority == .medium, "旧数据缺失 priority 应默认为中")
    try check(decoded.dueAt == nil, "旧数据缺失 dueAt 应为 nil")
    try check(decoded.description == nil, "旧数据缺失 description 应为 nil")
}

func checkSortsOpenItemsByPriorityThenDueDate() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try store.add(title: "中-明天", source: .text, priority: .medium, dueAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 0))
    _ = try store.add(title: "高-无截止", source: .text, priority: .high)
    _ = try store.add(title: "低-今天", source: .text, priority: .low, dueAt: makeDate(year: 2026, month: 6, day: 15, hour: 18, minute: 0))
    _ = try store.add(title: "高-今天", source: .text, priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 15, hour: 18, minute: 0))

    let titles = store.openItems(now: now).map(\.title)
    try check(
        titles == ["高-今天", "高-无截止", "中-明天", "低-今天"],
        "应按优先级→截止日期排序，实际: \(titles)"
    )
}

func checkSortsOverdueItemsToBottom() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try store.add(title: "高-已过期", source: .text, priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 14, hour: 10, minute: 0))
    _ = try store.add(title: "低-未过期", source: .text, priority: .low, dueAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 0))

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["低-未过期", "高-已过期"], "过期任务应全局沉底，实际: \(titles)")
}

func checkSortsItemsWithoutDueDateLast() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try store.add(title: "有截止", source: .text, priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 20, hour: 9, minute: 0))
    _ = try store.add(title: "无截止", source: .text, priority: .high)

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["有截止", "无截止"], "同优先级无截止日期应排后，实际: \(titles)")
}

func checkMCPCreateTaskWithNewFields() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let server = makeMCPServer(in: temporaryDirectory)

    let createResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 1,
            name: "create_task",
            arguments: #"{"title":"带字段","priority":"high","due_at":"2026-08-20T18:00:00+08:00","description":"具体说明"}"#
        )),
        "create_task 应有响应"
    )
    let created = try toolResultPayload(createResponse)
    let createdTitle = try payloadString(created, "title")
    try check(createdTitle == "带字段", "create_task 标题错误")
    let createdPriority = try payloadString(created, "priority")
    try check(createdPriority == "high", "create_task priority 应为 high，实际: \(createdPriority)")
    let dueText = try payloadString(created, "dueAt")
    try check(dueText.hasPrefix("2026-08-20"), "create_task dueAt 应为 2026-08-20，实际: \(dueText)")
    let createdDescription = try payloadString(created, "description")
    try check(createdDescription == "具体说明", "create_task description 错误")
}

func checkMCPUpdateTaskWithNewFields() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let server = makeMCPServer(in: temporaryDirectory)

    let createResponse = try require(
        server.process(frame: mcpToolsCall(id: 1, name: "create_task", arguments: #"{"title":"待改"}"#)),
        "create_task 应有响应"
    )
    let created = try toolResultPayload(createResponse)
    let id = try payloadID(created)
    let defaultPriority = try payloadString(created, "priority")
    try check(defaultPriority == "medium", "默认优先级应为 medium，实际: \(defaultPriority)")

    let updateResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 2,
            name: "update_task",
            arguments: #"{"id":""# + id + #"","priority":"low","due_at":"2026-08-22T10:00:00+08:00","description":"新描述"}"#
        )),
        "update_task 应有响应"
    )
    let updated = try toolResultPayload(updateResponse)
    let updatedPriority = try payloadString(updated, "priority")
    try check(updatedPriority == "low", "update_task priority 应为 low，实际: \(updatedPriority)")
    let dueText = try payloadString(updated, "dueAt")
    try check(dueText.hasPrefix("2026-08-22"), "update_task dueAt 应为 2026-08-22，实际: \(dueText)")
    let updatedDescription = try payloadString(updated, "description")
    try check(updatedDescription == "新描述", "update_task description 错误")

    let clearResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 3,
            name: "update_task",
            arguments: #"{"id":""# + id + #"","clear_due":true}"#
        )),
        "update_task 应有响应"
    )
    let cleared = try toolResultPayload(clearResponse)
    guard case .object(let clearedObject) = cleared,
          clearedObject["dueAt"] == .null else {
        throw CheckFailure(message: "clear_due 后 dueAt 应为 null")
    }
    let clearedPriority = try payloadString(cleared, "priority")
    try check(clearedPriority == "low", "clear_due 不应影响优先级")
}

func checkMCPInvalidPriorityAndDueDate() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let server = makeMCPServer(in: temporaryDirectory)

    let badPriorityResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 1,
            name: "create_task",
            arguments: #"{"title":"x","priority":"urgent"}"#
        )),
        "非法优先级应有响应"
    )
    let badPriorityIsError = try toolResultIsError(badPriorityResponse)
    try check(badPriorityIsError, "非法 priority 应返回 isError")

    let badDueResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 2,
            name: "create_task",
            arguments: #"{"title":"x","due_at":"not-a-date"}"#
        )),
        "非法截止时间应有响应"
    )
    let badDueIsError = try toolResultIsError(badDueResponse)
    try check(badDueIsError, "非法 due_at 应返回 isError")

    let listResponse = try require(
        server.process(frame: mcpToolsCall(id: 3, name: "list_tasks", arguments: "{}")),
        "list_tasks 应有响应"
    )
    guard case .array(let items) = try toolResultPayload(listResponse) else {
        throw CheckFailure(message: "list_tasks 应返回数组")
    }
    try check(items.isEmpty, "非法参数不应创建任务")
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

func makeMCPServer(in temporaryDirectory: URL) -> MCPServer {
    MCPServer(storeURL: temporaryDirectory.appendingPathComponent("todos.json"))
}

func decodeResponse<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
    var stripped = data
    if stripped.last == 0x0A {
        stripped = stripped.dropLast()
    }
    return try JSONDecoder().decode(type, from: stripped)
}

func mcpToolsCall(id: Int, name: String, arguments: String) -> Data {
    let body = "{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"tools/call\",\"params\":{\"name\":\"\(name)\",\"arguments\":\(arguments)}}"
    return Data(body.utf8)
}

func toolResultPayload(_ data: Data) throws -> JSONValue {
    let response = try decodeResponse(data, as: MCPSuccessResponse.self)
    guard case .object(let result) = response.result,
          case .array(let content)? = result["content"],
          case .object(let first)? = content.first,
          case .string(let text)? = first["text"] else {
        throw CheckFailure(message: "工具结果格式错误")
    }
    return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

func toolResultIsError(_ data: Data) throws -> Bool {
    let response = try decodeResponse(data, as: MCPSuccessResponse.self)
    guard case .object(let result) = response.result else {
        throw CheckFailure(message: "工具结果格式错误")
    }
    return result["isError"] == .bool(true)
}

func payloadBool(_ payload: JSONValue, _ key: String) throws -> Bool {
    guard case .object(let object) = payload,
          case .bool(let value)? = object[key] else {
        throw CheckFailure(message: "负载缺少布尔字段 \(key)")
    }
    return value
}

func payloadString(_ payload: JSONValue, _ key: String) throws -> String {
    guard case .object(let object) = payload,
          case .string(let value)? = object[key] else {
        throw CheckFailure(message: "负载缺少字段 \(key)")
    }
    return value
}

func payloadID(_ payload: JSONValue) throws -> String {
    try payloadString(payload, "id")
}

func checkMCPCodecRoundTrips() throws {
    let value = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(#"{"a":1,"b":[true,null,"x"]}"#.utf8)
    )
    try check(
        value == .object(["a": .int(1), "b": .array([.bool(true), .null, .string("x")])]),
        "JSONValue 解码错误"
    )

    let reencoded = try JSONEncoder().encode(value)
    let decodedAgain = try JSONDecoder().decode(JSONValue.self, from: reencoded)
    try check(decodedAgain == value, "JSONValue 编码往返应一致")

    let intID = try JSONDecoder().decode(MCPID.self, from: Data("1".utf8))
    try check(intID == .int(1), "整数 id 应解析为 int")
    let stringID = try JSONDecoder().decode(MCPID.self, from: Data(#""abc""#.utf8))
    try check(stringID == .string("abc"), "字符串 id 应解析为 string")
}

func checkMCPParseError() throws {
    let server = MCPServer(storeURL: URL(fileURLWithPath: "/tmp/unused-todos.json"))
    let response = try require(server.process(frame: Data("不是JSON".utf8)), "解析错误应有响应")
    let decoded = try decodeResponse(response, as: MCPErrorResponse.self)
    try check(decoded.error.code == -32700, "非法消息应返回 -32700")
    try check(decoded.id == nil, "解析错误的 id 应为 null")
}

func checkMCPUnknownMethod() throws {
    let server = MCPServer(storeURL: URL(fileURLWithPath: "/tmp/unused-todos.json"))
    let response = try require(
        server.process(frame: Data(#"{"jsonrpc":"2.0","id":7,"method":"nope"}"#.utf8)),
        "未知方法应有响应"
    )
    let decoded = try decodeResponse(response, as: MCPErrorResponse.self)
    try check(decoded.error.code == -32601, "未知方法应返回 -32601")
    try check(decoded.id == .int(7), "错误响应的 id 应原样返回")
}

func checkMCPInitializeHandshake() throws {
    let server = MCPServer(storeURL: URL(fileURLWithPath: "/tmp/unused-todos.json"))

    let initResponse = try require(
        server.process(frame: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8)),
        "initialize 应有响应"
    )
    let initDecoded = try decodeResponse(initResponse, as: MCPSuccessResponse.self)
    try check(initDecoded.id == .int(1), "initialize 响应 id 应原样返回")
    guard case .object(let result) = initDecoded.result else {
        throw CheckFailure(message: "initialize 结果应为对象")
    }
    try check(result["protocolVersion"] == .string("2025-06-18"), "协议版本应为 2025-06-18")
    guard case .object(let serverInfo)? = result["serverInfo"],
          serverInfo["name"] == .string("todopin") else {
        throw CheckFailure(message: "serverInfo 缺失或 name 错误")
    }

    let pingResponse = try require(
        server.process(frame: Data(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#.utf8)),
        "ping 应有响应"
    )
    let pingDecoded = try decodeResponse(pingResponse, as: MCPSuccessResponse.self)
    try check(pingDecoded.result == .object([:]), "ping 应返回空对象")
}

func checkMCPToolsList() throws {
    let server = MCPServer(storeURL: URL(fileURLWithPath: "/tmp/unused-todos.json"))
    let response = try require(
        server.process(frame: Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)),
        "tools/list 应有响应"
    )
    let decoded = try decodeResponse(response, as: MCPSuccessResponse.self)
    guard case .object(let result) = decoded.result,
          case .array(let tools)? = result["tools"] else {
        throw CheckFailure(message: "tools/list 结果格式错误")
    }

    let expectedNames: Set<String> = [
        "list_tasks", "create_task", "update_task",
        "complete_task", "uncomplete_task", "delete_task"
    ]
    var names: Set<String> = []
    for tool in tools {
        guard case .object(let object) = tool,
              case .string(let name)? = object["name"],
              case .object(let schema)? = object["inputSchema"],
              case .string(let schemaType)? = schema["type"] else {
            throw CheckFailure(message: "工具声明格式错误")
        }
        names.insert(name)
        try check(schemaType == "object", "inputSchema 应声明 type=object")
    }
    try check(names == expectedNames, "tools/list 应返回六个预期工具")
}

func checkMCPToolLifecycle() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let server = makeMCPServer(in: temporaryDirectory)

    let createResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 1,
            name: "create_task",
            arguments: #"{"title":"MCP 测试任务","reminder_at":"2026-08-14T09:00:00+08:00"}"#
        )),
        "create_task 应有响应"
    )
    let created = try toolResultPayload(createResponse)
    let createdTitle = try payloadString(created, "title")
    try check(createdTitle == "MCP 测试任务", "create_task 标题错误")
    let createdReminder = try payloadString(created, "reminderAt")
    try check(createdReminder.hasPrefix("2026-08-14"), "create_task 提醒时间错误")
    let id = try payloadID(created)

    let listResponse = try require(
        server.process(frame: mcpToolsCall(id: 2, name: "list_tasks", arguments: "{}")),
        "list_tasks 应有响应"
    )
    let listed = try toolResultPayload(listResponse)
    guard case .array(let items) = listed else {
        throw CheckFailure(message: "list_tasks 应返回数组")
    }
    try check(items.count == 1, "list_tasks 应包含 1 条任务")

    let completeResponse = try require(
        server.process(frame: mcpToolsCall(id: 3, name: "complete_task", arguments: #"{"id":""# + id + #""}"#)),
        "complete_task 应有响应"
    )
    let completed = try toolResultPayload(completeResponse)
    let completedFlag = try payloadBool(completed, "isCompleted")
    try check(completedFlag, "complete_task 后应已完成")

    let listAfterComplete = try toolResultPayload(try require(
        server.process(frame: mcpToolsCall(id: 4, name: "list_tasks", arguments: "{}")),
        "list_tasks 应有响应"
    ))
    guard case .array(let openItems) = listAfterComplete else {
        throw CheckFailure(message: "list_tasks 应返回数组")
    }
    try check(openItems.isEmpty, "完成后的默认 list_tasks 应为空")

    let uncompleteResponse = try require(
        server.process(frame: mcpToolsCall(id: 5, name: "uncomplete_task", arguments: #"{"id":""# + id + #""}"#)),
        "uncomplete_task 应有响应"
    )
    let uncompletedPayload = try toolResultPayload(uncompleteResponse)
    let uncompletedFlag = try payloadBool(uncompletedPayload, "isCompleted")
    try check(!uncompletedFlag, "uncomplete_task 后应未完成")

    let updateResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 6,
            name: "update_task",
            arguments: #"{"id":""# + id + #"","title":"改过的标题"}"#
        )),
        "update_task 应有响应"
    )
    let updated = try toolResultPayload(updateResponse)
    let updatedTitle = try payloadString(updated, "title")
    try check(updatedTitle == "改过的标题", "update_task 标题错误")
    let updatedReminder = try payloadString(updated, "reminderAt")
    try check(updatedReminder.hasPrefix("2026-08-14"), "只改标题时提醒时间应保留")

    let clearResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 7,
            name: "update_task",
            arguments: #"{"id":""# + id + #"","clear_reminder":true}"#
        )),
        "update_task 应有响应"
    )
    let cleared = try toolResultPayload(clearResponse)
    guard case .object(let clearedObject) = cleared,
          clearedObject["reminderAt"] == .null else {
        throw CheckFailure(message: "clear_reminder 后提醒时间应为 null")
    }

    let deleteResponse = try require(
        server.process(frame: mcpToolsCall(id: 8, name: "delete_task", arguments: #"{"id":""# + id + #""}"#)),
        "delete_task 应有响应"
    )
    let deleted = try toolResultPayload(deleteResponse)
    let deletedID = try payloadString(deleted, "id")
    try check(deletedID == id, "delete_task 返回的 id 应一致")

    let finalList = try toolResultPayload(try require(
        server.process(frame: mcpToolsCall(id: 9, name: "list_tasks", arguments: "{}")),
        "list_tasks 应有响应"
    ))
    guard case .array(let finalItems) = finalList else {
        throw CheckFailure(message: "list_tasks 应返回数组")
    }
    try check(finalItems.isEmpty, "删除后 list_tasks 应为空")
}

func checkMCPToolErrors() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let server = makeMCPServer(in: temporaryDirectory)

    let badDateResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 1,
            name: "create_task",
            arguments: #"{"title":"x","reminder_at":"not-a-date"}"#
        )),
        "非法日期应有响应"
    )
    let badDateIsError = try toolResultIsError(badDateResponse)
    try check(badDateIsError, "非法日期应返回 isError")

    let missingIDResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 2,
            name: "complete_task",
            arguments: #"{"id":"00000000-0000-0000-0000-000000000000"}"#
        )),
        "id 不存在应有响应"
    )
    let missingIDIsError = try toolResultIsError(missingIDResponse)
    try check(missingIDIsError, "id 不存在应返回 isError")

    let noParamResponse = try require(
        server.process(frame: mcpToolsCall(
            id: 3,
            name: "update_task",
            arguments: #"{"id":"00000000-0000-0000-0000-000000000000"}"#
        )),
        "无修改参数应有响应"
    )
    let noParamIsError = try toolResultIsError(noParamResponse)
    try check(noParamIsError, "update_task 无参数应返回 isError")

    let unknownToolResponse = try require(
        server.process(frame: mcpToolsCall(id: 4, name: "nope", arguments: "{}")),
        "未知工具应有响应"
    )
    let unknownDecoded = try decodeResponse(unknownToolResponse, as: MCPErrorResponse.self)
    try check(unknownDecoded.error.code == -32602, "未知工具应返回 -32602")

    let badParamsResponse = try require(
        server.process(frame: Data(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":[1,2]}"#.utf8)),
        "非法 params 应有响应"
    )
    let badParamsDecoded = try decodeResponse(badParamsResponse, as: MCPErrorResponse.self)
    try check(badParamsDecoded.error.code == -32602, "params 非对象应返回 -32602")
}

func checkMCPFreshStore() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let server = makeMCPServer(in: temporaryDirectory)

    _ = try toolResultPayload(try require(
        server.process(frame: mcpToolsCall(id: 1, name: "create_task", arguments: #"{"title":"第一条"}"#)),
        "create_task 应有响应"
    ))

    let externalStore = makeStore(in: temporaryDirectory)
    try externalStore.load()
    _ = try require(try externalStore.add(title: "外部写入", source: .text), "外部写入失败")

    let listResponse = try require(
        server.process(frame: mcpToolsCall(id: 2, name: "list_tasks", arguments: "{}")),
        "list_tasks 应有响应"
    )
    guard case .array(let items) = try toolResultPayload(listResponse) else {
        throw CheckFailure(message: "list_tasks 应返回数组")
    }
    try check(items.count == 2, "外部写入后 list_tasks 应读到最新数据（2 条）")
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
