import Combine
import Foundation
import GhostPinCore

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

let checks: [Check] = [
    ("TodoStore.add trims title and ignores empty input", checkAddTrimsTitleAndIgnoresEmptyInput),
    ("TodoStore orders open items by createdAt descending", checkOpenItemsAreCreatedAtDescending),
    ("TodoStore.updateTitle trims persists and ignores empty input", checkUpdateTitleTrimsPersistsAndIgnoresEmptyInput),
    ("TodoStore.add persists reminder time", checkAddPersistsReminderTime),
    ("TodoStore.add persists priority due date and description", checkAddPersistsNewFields),
    ("TodoStore.markTimedReminderSent persists sent time", checkMarkTimedReminderSentPersists),
    ("TodoStore.update changes reminder time and clears sent time", checkUpdateChangesReminderTimeAndClearsSentTime),
    ("TodoStore.update removes reminder time and clears sent time", checkUpdateRemovesReminderTimeAndClearsSentTime),
    ("TodoStore.update changes and clears due date while preserving fields", checkUpdateChangesAndClearsNewFields),
    ("TodoStore.setCompleted removes items from openItems", checkCompletedItemsAreRemovedFromOpenItems),
    ("TodoStore transitions Todo Doing Done and restores Todo", checkTodoStatusTransitions),
    ("TodoStore.hudItems filters today scope by day boundary", checkHudItemsTodayScopeUsesDayBoundary),
    ("TodoStore.hudItems all scope includes every open item", checkHudItemsAllScopeIncludesEveryOpenItem),
    ("TodoStore.hudItems truncates to maxCount keeping newest first", checkHudItemsTruncatesToMaxCount),
    ("TodoStore.hudItems excludes completed items", checkHudItemsExcludesCompletedItems),
    ("TodoItem decodes legacy data with default priority", checkDecodesLegacyTodoItemWithoutNewFields),
    ("TodoStore prioritizes Doing over Todo", checkDoingItemsAreSortedBeforeTodoItems),
    ("TodoStore sorts open items by priority then due date", checkSortsOpenItemsByPriorityThenDueDate),
    ("TodoStore sinks overdue items to bottom", checkSortsOverdueItemsToBottom),
    ("TodoStore sorts items without due date after those with", checkSortsItemsWithoutDueDateLast),
    ("TodoStore.load reflects external file changes", checkLoadReflectsExternalChange),
    ("TodoStore.load skips publish when content unchanged", checkLoadSkipsPublishWhenUnchanged),
    ("TodoStore.load clears items when file missing", checkLoadClearsItemsWhenFileMissing),
    ("TodoItem.hasPendingTimedReminder reflects reminder state", checkHasPendingTimedReminder),
    ("StorageLocations uses GhostPin for a fresh install", checkFreshStorageUsesGhostPin),
    ("StorageLocations migrates legacy data and preserves the source", checkMigratesLegacyStorage),
    ("StorageLocations prefers existing GhostPin data", checkPrefersExistingGhostPinStorage),
    ("StorageLocations rejects corrupt legacy data", checkRejectsCorruptLegacyStorage)
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
    print("All \(checks.count) GhostPinCore checks passed.")
} else {
    print("\(failures.count) GhostPinCore checks failed.")
    exit(1)
}

func checkAddTrimsTitleAndIgnoresEmptyInput() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)

    let empty = try store.add(title: "   \n  ")
    try check(empty == nil, "empty input should not create a todo")
    try check(store.items.isEmpty, "store should stay empty")

    let item = try require(try store.add(title: "  买牛奶  "), "expected a todo")
    try check(item.title == "买牛奶", "title should be trimmed")
    try check(store.items.map(\.title) == ["买牛奶"], "store should contain trimmed title")
}

func checkOpenItemsAreCreatedAtDescending() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let older = makeDate(year: 2026, month: 6, day: 14, hour: 9, minute: 0)
    let newer = makeDate(year: 2026, month: 6, day: 14, hour: 10, minute: 0)

    _ = try store.add(title: "早一点", createdAt: older)
    _ = try store.add(title: "晚一点", createdAt: newer)

    try check(store.openItems().map(\.title) == ["晚一点", "早一点"], "newer todos should be listed first")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.openItems().map(\.title) == ["晚一点", "早一点"], "loaded todos should stay newest first")
}

func checkUpdateTitleTrimsPersistsAndIgnoresEmptyInput() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let item = try require(try store.add(title: "旧标题"), "expected a todo")

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
    let first = try require(try store.add(title: "完成的事"), "expected first todo")
    let second = try require(try store.add(title: "继续保留"), "expected second todo")

    try store.setCompleted(first.id, completed: true)

    try check(store.openItems() == [second], "completed todo should not be open")
}

func checkTodoStatusTransitions() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let startedAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 0)
    let completedAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 5)

    let item = try require(try store.add(title: "状态任务"), "expected a todo")
    try check(item.status == .todo, "new task should be todo")

    let doing = try require(
        try store.setStatus(item.id, status: .doing, at: startedAt),
        "expected doing task"
    )
    try check(doing.status == .doing, "task should be doing")
    try check(doing.completedAt == nil, "doing task should not have completedAt")
    try check(!doing.isCompleted, "doing task should not be completed")

    let done = try require(
        try store.setStatus(item.id, status: .done, at: completedAt),
        "expected completed task"
    )
    try check(done.status == .done, "task should be done")
    try check(done.completedAt == completedAt, "done task should keep completion time")
    try check(done.isCompleted, "done task should be completed")

    let todo = try require(
        try store.setStatus(item.id, status: .todo, at: completedAt),
        "expected restored task"
    )
    try check(todo.status == .todo, "restored task should be todo")
    try check(todo.completedAt == nil, "restored task should clear completion time")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.status == .todo, "restored status should persist")
}

func checkAddPersistsReminderTime() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let reminderAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 30)

    let item = try require(try store.add(title: "开会", reminderAt: reminderAt), "expected a todo")
    try check(item.reminderAt == reminderAt, "todo should keep reminder time")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.reminderAt == reminderAt, "reminder time should persist")
}

func checkAddPersistsNewFields() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let dueAt = makeDate(year: 2026, month: 6, day: 22, hour: 18, minute: 0)

    let item = try require(
        try store.add(title: "带字段", priority: .high, dueAt: dueAt, description: "准备周报"),
        "expected a todo"
    )
    try check(item.priority == .high, "priority should persist in memory")
    try check(item.dueAt == dueAt, "due date should persist in memory")
    try check(item.description == "准备周报", "description should persist in memory")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    guard let loaded = reloaded.items.first else {
        throw CheckFailure(message: "expected persisted todo")
    }
    try check(loaded.priority == .high, "priority should persist")
    try check(loaded.dueAt == dueAt, "due date should persist")
    try check(loaded.description == "准备周报", "description should persist")
}

func checkMarkTimedReminderSentPersists() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let reminderAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 30)
    let sentAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 31)
    let item = try require(try store.add(title: "开会", reminderAt: reminderAt), "expected a todo")

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
    let item = try require(try store.add(title: "开会", reminderAt: originalReminderAt), "expected a todo")
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
    let item = try require(try store.add(title: "开会", reminderAt: reminderAt), "expected a todo")
    try store.markTimedReminderSent(item.id, at: sentAt)

    let updated = try require(try store.update(item.id, title: "开会", reminderAt: nil), "expected updated todo")

    try check(updated.reminderAt == nil, "reminder time should be removed")
    try check(updated.reminderSentAt == nil, "removed reminder should clear sent time")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.items.first?.reminderAt == nil, "removed reminder time should persist")
    try check(reloaded.items.first?.reminderSentAt == nil, "cleared sent time should persist")
}

func checkUpdateChangesAndClearsNewFields() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let originalDueAt = makeDate(year: 2026, month: 6, day: 22, hour: 18, minute: 0)
    let changedDueAt = makeDate(year: 2026, month: 6, day: 23, hour: 9, minute: 30)
    let item = try require(
        try store.add(title: "原任务", priority: .high, dueAt: originalDueAt, description: "原描述"),
        "expected a todo"
    )

    let changed = try require(
        try store.update(
            item.id,
            title: item.title,
            reminderAt: item.reminderAt,
            priority: .low,
            dueAt: changedDueAt,
            description: "新描述"
        ),
        "expected updated todo"
    )
    try check(changed.priority == .low, "priority should change")
    try check(changed.dueAt == changedDueAt, "due date should change")
    try check(changed.description == "新描述", "description should change")

    let cleared = try require(
        try store.update(
            item.id,
            title: changed.title,
            reminderAt: changed.reminderAt,
            priority: changed.priority,
            dueAt: nil,
            description: changed.description
        ),
        "expected cleared todo"
    )
    try check(cleared.dueAt == nil, "due date should clear")
    try check(cleared.priority == .low, "clearing due date should preserve priority")
    try check(cleared.description == "新描述", "clearing due date should preserve description")
}

func checkHasPendingTimedReminder() throws {
    let futureReminder = TodoItem(title: "开会", reminderAt: Date().addingTimeInterval(3600))
    try check(futureReminder.hasPendingTimedReminder, "item with future reminder should have pending timed reminder")

    let completed = TodoItem(title: "已完成", completedAt: Date(), reminderAt: Date().addingTimeInterval(3600))
    try check(!completed.hasPendingTimedReminder, "completed item should not have pending timed reminder")

    let sent = TodoItem(title: "已提醒", reminderAt: Date().addingTimeInterval(-3600), reminderSentAt: Date())
    try check(!sent.hasPendingTimedReminder, "sent reminder should not be pending")
}

func checkFreshStorageUsesGhostPin() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let todosURL = try StorageLocations.todosURL(applicationSupportRoot: temporaryDirectory)
    try check(
        todosURL.path == temporaryDirectory.appendingPathComponent("GhostPin/todos.json").path,
        "fresh storage should use the GhostPin directory"
    )
    try check(
        !FileManager.default.fileExists(
            atPath: temporaryDirectory.appendingPathComponent("TodoPin").path
        ),
        "fresh storage should not create the legacy directory"
    )
}

func checkMigratesLegacyStorage() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let legacyURL = temporaryDirectory
        .appendingPathComponent("TodoPin", isDirectory: true)
        .appendingPathComponent("todos.json")
    try FileManager.default.createDirectory(
        at: legacyURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let item = TodoItem(title: "迁移任务", priority: .high)
    let legacyData = try JSONEncoder.ghostPin.encode([item])
    try legacyData.write(to: legacyURL)

    let todosURL = try StorageLocations.todosURL(applicationSupportRoot: temporaryDirectory)
    try check(FileManager.default.fileExists(atPath: todosURL.path), "new storage should be created")
    let migratedData = try Data(contentsOf: todosURL)
    let preservedLegacyData = try Data(contentsOf: legacyURL)
    let migratedDirectoryContents = try FileManager.default.contentsOfDirectory(
        at: todosURL.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    )
    try check(migratedData == legacyData, "migration should preserve the legacy JSON content")
    try check(preservedLegacyData == legacyData, "migration should preserve the legacy source")
    try check(
        migratedDirectoryContents.filter { $0.lastPathComponent.hasPrefix(".todos-") }.isEmpty,
        "migration should clean temporary files"
    )
}

func checkPrefersExistingGhostPinStorage() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let newURL = temporaryDirectory
        .appendingPathComponent("GhostPin", isDirectory: true)
        .appendingPathComponent("todos.json")
    let legacyURL = temporaryDirectory
        .appendingPathComponent("TodoPin", isDirectory: true)
        .appendingPathComponent("todos.json")
    try FileManager.default.createDirectory(
        at: newURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: legacyURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let currentData = try JSONEncoder.ghostPin.encode([TodoItem(title: "新任务")])
    let legacyData = try JSONEncoder.ghostPin.encode([TodoItem(title: "旧任务")])
    try currentData.write(to: newURL)
    try legacyData.write(to: legacyURL)

    let resolvedURL = try StorageLocations.todosURL(applicationSupportRoot: temporaryDirectory)
    let preservedCurrentData = try Data(contentsOf: newURL)
    let preservedLegacyData = try Data(contentsOf: legacyURL)
    try check(resolvedURL == newURL, "existing GhostPin storage should remain authoritative")
    try check(preservedCurrentData == currentData, "existing GhostPin data should not be overwritten")
    try check(preservedLegacyData == legacyData, "legacy data should remain untouched")
}

func checkRejectsCorruptLegacyStorage() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let legacyURL = temporaryDirectory
        .appendingPathComponent("TodoPin", isDirectory: true)
        .appendingPathComponent("todos.json")
    try FileManager.default.createDirectory(
        at: legacyURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let corruptData = Data("not-json".utf8)
    try corruptData.write(to: legacyURL)

    do {
        _ = try StorageLocations.todosURL(applicationSupportRoot: temporaryDirectory)
        throw CheckFailure(message: "corrupt legacy data should fail migration")
    } catch let failure as CheckFailure {
        throw failure
    } catch {
        try check(
            !FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent("GhostPin/todos.json").path
            ),
            "failed migration should not create a new task file"
        )
        let preservedLegacyData = try Data(contentsOf: legacyURL)
        try check(preservedLegacyData == corruptData, "failed migration should preserve source data")
    }
}

func checkHudItemsTodayScopeUsesDayBoundary() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try require(
        try store.add(title: "今天任务", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 1, minute: 0)),
        "expected today todo"
    )
    _ = try require(
        try store.add(title: "昨天任务", createdAt: makeDate(year: 2026, month: 6, day: 14, hour: 23, minute: 59)),
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
        try store.add(title: "今天任务", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 1, minute: 0)),
        "expected today todo"
    )
    _ = try require(
        try store.add(title: "昨天任务", createdAt: makeDate(year: 2026, month: 6, day: 14, hour: 23, minute: 59)),
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

    let completedItem = try require(try store.add(title: "待完成"), "expected todo")
    _ = try require(try store.add(title: "保留"), "expected todo")
    try store.setCompleted(completedItem.id, completed: true)

    let hudItems = store.hudItems(scope: .all, maxCount: 10, now: now, calendar: checkCalendar)
    try check(hudItems.map(\.title) == ["保留"], "completed items should disappear from HUD")
}

func checkDecodesLegacyTodoItemWithoutNewFields() throws {
    let item = TodoItem(title: "旧任务", reminderAt: nil)
    let data = try JSONEncoder().encode(item)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CheckFailure(message: "编码失败")
    }
    object.removeValue(forKey: "status")
    object.removeValue(forKey: "priority")
    object.removeValue(forKey: "dueAt")
    object.removeValue(forKey: "description")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(TodoItem.self, from: legacyData)
    try check(decoded.title == "旧任务", "旧数据标题应保留")
    try check(decoded.priority == .medium, "旧数据缺失 priority 应默认为中")
    try check(decoded.dueAt == nil, "旧数据缺失 dueAt 应为 nil")
    try check(decoded.description == nil, "旧数据缺失 description 应为 nil")
    try check(decoded.status == .todo, "旧的未完成任务应映射为 todo")

    let completedItem = TodoItem(title: "旧完成任务", completedAt: makeDate(year: 2026, month: 6, day: 20, hour: 11, minute: 0))
    let completedData = try JSONEncoder().encode(completedItem)
    guard var completedObject = try JSONSerialization.jsonObject(with: completedData) as? [String: Any] else {
        throw CheckFailure(message: "已完成旧数据编码失败")
    }
    completedObject.removeValue(forKey: "status")
    let legacyCompletedData = try JSONSerialization.data(withJSONObject: completedObject)
    let decodedCompleted = try JSONDecoder().decode(TodoItem.self, from: legacyCompletedData)
    try check(decodedCompleted.status == .done, "旧的已完成任务应映射为 done")
    try check(decodedCompleted.isCompleted, "旧的已完成任务应保持完成")

    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let legacyURL = temporaryDirectory.appendingPathComponent("todos.json")
    let fileEncoded = try JSONEncoder.ghostPin.encode(item)
    guard var fileObject = try JSONSerialization.jsonObject(with: fileEncoded) as? [String: Any] else {
        throw CheckFailure(message: "文件格式旧数据编码失败")
    }
    fileObject.removeValue(forKey: "status")
    fileObject.removeValue(forKey: "priority")
    fileObject.removeValue(forKey: "dueAt")
    fileObject.removeValue(forKey: "description")
    let legacyListData = try JSONSerialization.data(withJSONObject: [fileObject])
    try legacyListData.write(to: legacyURL)
    let store = makeStore(in: temporaryDirectory)
    try store.load()
    try store.save()
    let migrated = makeStore(in: temporaryDirectory)
    try migrated.load()
    try check(migrated.items.first?.status == .todo, "旧数据保存后应保留 todo 状态")
}

func checkDoingItemsAreSortedBeforeTodoItems() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    let doing = try require(
        try store.add(title: "Doing-低", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0), priority: .low),
        "expected doing task"
    )
    _ = try store.setStatus(doing.id, status: .doing, at: now)
    _ = try store.add(
        title: "Todo-高",
        createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 10, minute: 0),
        priority: .high
    )

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["Doing-低", "Todo-高"], "Doing 应排在所有 Todo 前，实际: \(titles)")

    let hudItems = store.hudItems(scope: .all, maxCount: 1, now: now, calendar: checkCalendar)
    try check(hudItems.map(\.title) == ["Doing-低"], "HUD 条数上限应优先保留 Doing")
}

func checkSortsOpenItemsByPriorityThenDueDate() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try store.add(title: "中-明天", priority: .medium, dueAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 0))
    _ = try store.add(title: "高-无截止", priority: .high)
    _ = try store.add(title: "低-今天", priority: .low, dueAt: makeDate(year: 2026, month: 6, day: 15, hour: 18, minute: 0))
    _ = try store.add(title: "高-今天", priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 15, hour: 18, minute: 0))

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

    _ = try store.add(title: "高-已过期", priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 14, hour: 10, minute: 0))
    _ = try store.add(title: "低-未过期", priority: .low, dueAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 0))

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["低-未过期", "高-已过期"], "过期任务应全局沉底，实际: \(titles)")
}

func checkSortsItemsWithoutDueDateLast() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try store.add(title: "有截止", priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 20, hour: 9, minute: 0))
    _ = try store.add(title: "无截止", priority: .high)

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["有截止", "无截止"], "同优先级无截止日期应排后，实际: \(titles)")
}

func checkLoadReflectsExternalChange() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    _ = try require(try store.add(title: "初始任务"), "expected todo")

    let external = makeStore(in: temporaryDirectory)
    try external.load()
    _ = try require(try external.add(title: "外部任务"), "expected external todo")

    try store.load()
    try check(store.items.map(\.title) == ["外部任务", "初始任务"], "load should reflect external change")
}

func checkLoadSkipsPublishWhenUnchanged() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    _ = try require(try store.add(title: "任务"), "expected todo")

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
    _ = try require(try store.add(title: "任务"), "expected todo")

    try FileManager.default.removeItem(at: temporaryDirectory.appendingPathComponent("todos.json"))

    try store.load()
    try check(store.items.isEmpty, "load should clear items when file missing")
}

func makeStore(in temporaryDirectory: URL) -> TodoStore {
    TodoStore(fileURL: temporaryDirectory.appendingPathComponent("todos.json"))
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("GhostPinChecks-\(UUID().uuidString)", isDirectory: true)
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
