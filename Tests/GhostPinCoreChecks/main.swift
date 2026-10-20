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

// 仅测试程序使用的子进程入口；路径由父检查显式传入。
if CommandLine.arguments.count == 4, ["--storage-worker", "--app-worker"].contains(CommandLine.arguments[1]) {
    do {
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let store = makeStore(in: directory)
        if CommandLine.arguments[1] == "--app-worker" { try store.load() }
        let ready = directory.appendingPathComponent("ready-\(ProcessInfo.processInfo.processIdentifier)")
        try Data().write(to: ready)
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("go").path) {
            guard Date() < deadline else { throw CheckFailure(message: "等待并发检查超时") }
            Thread.sleep(forTimeInterval: 0.01)
        }
        if CommandLine.arguments[1] == "--app-worker" {
            let id = try require(Int64(CommandLine.arguments[3]), "应为整数 ID")
            _ = try store.advanceStatus(id)
            try store.markTimedReminderSent(id)
        } else {
            _ = try store.add(title: CommandLine.arguments[3], group: "并发")
        }
        exit(0)
    } catch {
        print(error)
        exit(1)
    }
}

let checkCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "zh_CN")
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
    return calendar
}()

let checks: [Check] = [
    ("Skill 首次安装和整目录覆盖保留其他 Skill", checkSkillInstallAndReplace),
    ("Skill 来源不完整时拒绝修改目标", checkInvalidSkillSources),
    ("Skill 解析链接和后续上级路径并保留链接文本", checkSkillSymbolicLinks),
    ("Skill 拒绝无效目标和无归属标记目录", checkInvalidSkillTargets),
    ("Skill 复制失败或副本不完整时保留旧目录", checkSkillCopyFailures),
    ("Skill 提交前复核复制期间变化的目标归属", checkSkillTargetChanges),
    ("Skill 提交失败恢复旧目录", checkSkillCommitFailure),
    ("Skill 恢复失败保留旧副本并报告路径", checkSkillRestoreFailure),
    ("Skill 提交后清理失败如实报告安装结果", checkSkillCleanupFailure),
    ("任务跨组递增编号且删除后不复用", checkSequentialIDsAcrossGroups),
    ("换组和旧快照写回保留最新字段", checkGroupAndStaleWrites),
    ("旧任务一次迁入默认组并稳定编号", checkLegacyGroupAndIDMigration),
    ("非法新文档和备份冲突不覆盖原文件", checkInvalidDocumentsAndBackupConflict),
    ("两个进程同时新增保留独立编号", checkConcurrentProcesses),
    ("提交失败不发布快照且可重试迁移", checkFailedCommitAndRetry),
    ("多组任务沿用统一 HUD 投影", checkGroupedHudProjection),
    ("共享夹具迁移与新文档编码一致", checkSharedGroupFixtures),
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
    ("TodoStore.hudProjection focuses Doing and hides Todo when enabled", checkHudProjectionFocusesDoing),
    ("TodoStore.hudProjection shows Todo when there is no Doing", checkHudProjectionWithoutDoingShowsTodo),
    ("TodoStore.hudProjection shows both sections when focus is disabled", checkHudProjectionDisabledShowsBothSections),
    ("TodoStore.hudProjection applies maxCount to rendered items only", checkHudProjectionLimitAppliesToRenderedItems),
    ("TodoStore.hudProjection counts sections independently of the limit", checkHudProjectionCountsAreIndependent),
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

    let empty = try store.add(title: "   \n  ", group: "默认")
    try check(empty == nil, "empty input should not create a todo")
    try check(store.items.isEmpty, "store should stay empty")

    let item = try require(try store.add(title: "  买牛奶  ", group: "默认"), "expected a todo")
    try check(item.title == "买牛奶", "title should be trimmed")
    try check(store.items.map(\.title) == ["买牛奶"], "store should contain trimmed title")
}

func checkOpenItemsAreCreatedAtDescending() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let older = makeDate(year: 2026, month: 6, day: 14, hour: 9, minute: 0)
    let newer = makeDate(year: 2026, month: 6, day: 14, hour: 10, minute: 0)

    _ = try store.add(title: "早一点", group: "默认", createdAt: older)
    _ = try store.add(title: "晚一点", group: "默认", createdAt: newer)

    try check(store.openItems().map(\.title) == ["晚一点", "早一点"], "newer todos should be listed first")

    let reloaded = makeStore(in: temporaryDirectory)
    try reloaded.load()
    try check(reloaded.openItems().map(\.title) == ["晚一点", "早一点"], "loaded todos should stay newest first")
}

func checkUpdateTitleTrimsPersistsAndIgnoresEmptyInput() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let item = try require(try store.add(title: "旧标题", group: "默认"), "expected a todo")

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
    let first = try require(try store.add(title: "完成的事", group: "默认"), "expected first todo")
    let second = try require(try store.add(title: "继续保留", group: "默认"), "expected second todo")

    try store.setCompleted(first.id, completed: true)

    try check(store.openItems().map(\.id) == [second.id], "completed todo should not be open")
}

func checkTodoStatusTransitions() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let startedAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 0)
    let completedAt = makeDate(year: 2026, month: 6, day: 20, hour: 10, minute: 5)

    let item = try require(try store.add(title: "状态任务", group: "默认"), "expected a todo")
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

    let item = try require(try store.add(title: "开会", group: "默认", reminderAt: reminderAt), "expected a todo")
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
        try store.add(title: "带字段", group: "默认", priority: .high, dueAt: dueAt, description: "准备周报"),
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
    let item = try require(try store.add(title: "开会", group: "默认", reminderAt: reminderAt), "expected a todo")

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
    let item = try require(try store.add(title: "开会", group: "默认", reminderAt: originalReminderAt), "expected a todo")
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
    let item = try require(try store.add(title: "开会", group: "默认", reminderAt: reminderAt), "expected a todo")
    try store.markTimedReminderSent(item.id, at: sentAt)

    let updated = try require(try store.update(item.id, title: "开会", clearReminder: true), "expected updated todo")

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
        try store.add(title: "原任务", group: "默认", priority: .high, dueAt: originalDueAt, description: "原描述"),
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
            clearDue: true,
            description: changed.description
        ),
        "expected cleared todo"
    )
    try check(cleared.dueAt == nil, "due date should clear")
    try check(cleared.priority == .low, "clearing due date should preserve priority")
    try check(cleared.description == "新描述", "clearing due date should preserve description")
}

func checkHasPendingTimedReminder() throws {
    let futureReminder = TodoItem(id: 10000, group: "默认", title: "开会", reminderAt: Date().addingTimeInterval(3600))
    try check(futureReminder.hasPendingTimedReminder, "item with future reminder should have pending timed reminder")

    let completed = TodoItem(id: 10000, group: "默认", title: "已完成", completedAt: Date(), reminderAt: Date().addingTimeInterval(3600))
    try check(!completed.hasPendingTimedReminder, "completed item should not have pending timed reminder")

    let sent = TodoItem(id: 10000, group: "默认", title: "已提醒", reminderAt: Date().addingTimeInterval(-3600), reminderSentAt: Date())
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
    let legacyData = Data("""
    [{"id":"00000000-0000-0000-0000-000000000001","title":"迁移任务","createdAt":"2026-06-20T02:00:00Z","priority":"high"}]
    """.utf8)
    try legacyData.write(to: legacyURL)

    let todosURL = try StorageLocations.todosURL(applicationSupportRoot: temporaryDirectory)
    let store = TodoStore(fileURL: todosURL, legacyFileURL: legacyURL)
    try check(try store.setStatus(99999, status: .doing) == nil, "未知任务不应触发目录迁移")
    try check(!FileManager.default.fileExists(atPath: todosURL.path), "业务失败不应复制任务")
    try check(!FileManager.default.fileExists(atPath: todosURL.deletingLastPathComponent().appendingPathComponent("todos.v1.backup.json").path), "业务失败不应备份")
    try store.load()
    try check(FileManager.default.fileExists(atPath: todosURL.path), "new storage should be created")
    let migratedData = try Data(contentsOf: todosURL)
    let preservedLegacyData = try Data(contentsOf: legacyURL)
    let migratedDirectoryContents = try FileManager.default.contentsOfDirectory(
        at: todosURL.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    )
    let document = try JSONDecoder.ghostPin.decode(TaskDocument.self, from: migratedData)
    try check(document.items.first?.id == 10000 && document.items.first?.group == "默认", "目录迁移应同时升级格式")
    try check(document.items.first?.priority == .high, "迁移应保留业务字段")
    try check(try Data(contentsOf: todosURL.deletingLastPathComponent().appendingPathComponent("todos.v1.backup.json")) == legacyData, "备份应保留源文件原始字节")
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
    let currentData = try JSONEncoder.ghostPin.encode(TaskDocument(nextID: 10001, items: [TodoItem(id: 10000, group: "当前组", title: "新任务")]))
    let legacyData = Data("[]".utf8)
    try currentData.write(to: newURL)
    try legacyData.write(to: legacyURL)

    let resolvedURL = try StorageLocations.todosURL(applicationSupportRoot: temporaryDirectory)
    let store = TodoStore(fileURL: resolvedURL, legacyFileURL: legacyURL)
    try store.load()
    try check(store.items.first?.title == "新任务", "应读取新目录任务")
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
        let file = try StorageLocations.todosURL(applicationSupportRoot: temporaryDirectory)
        try TodoStore(fileURL: file, legacyFileURL: legacyURL).load()
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
        try store.add(title: "今天任务", group: "默认", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 1, minute: 0)),
        "expected today todo"
    )
    _ = try require(
        try store.add(title: "昨天任务", group: "默认", createdAt: makeDate(year: 2026, month: 6, day: 14, hour: 23, minute: 59)),
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
        try store.add(title: "今天任务", group: "默认", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 1, minute: 0)),
        "expected today todo"
    )
    _ = try require(
        try store.add(title: "昨天任务", group: "默认", createdAt: makeDate(year: 2026, month: 6, day: 14, hour: 23, minute: 59)),
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
                title: "任务\(index)", group: "默认",
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

    let completedItem = try require(try store.add(title: "待完成", group: "默认"), "expected todo")
    _ = try require(try store.add(title: "保留", group: "默认"), "expected todo")
    try store.setCompleted(completedItem.id, completed: true)

    let hudItems = store.hudItems(scope: .all, maxCount: 10, now: now, calendar: checkCalendar)
    try check(hudItems.map(\.title) == ["保留"], "completed items should disappear from HUD")
}

func checkDecodesLegacyTodoItemWithoutNewFields() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let legacyURL = temporaryDirectory.appendingPathComponent("todos.json")
    let legacyData = Data("""
    [
      {"id":"00000000-0000-0000-0000-000000000001","title":"旧任务","createdAt":"2026-06-20T01:00:00Z"},
      {"id":"00000000-0000-0000-0000-000000000002","title":"旧完成任务","createdAt":"2026-06-20T02:00:00Z","completedAt":"2026-06-20T03:00:00Z"}
    ]
    """.utf8)
    try legacyData.write(to: legacyURL)
    let store = makeStore(in: temporaryDirectory)
    try store.load()
    let decoded = try require(store.items.first { $0.title == "旧任务" }, "应读取旧任务")
    try check(decoded.title == "旧任务", "旧数据标题应保留")
    try check(decoded.priority == .medium, "旧数据缺失 priority 应默认为中")
    try check(decoded.dueAt == nil, "旧数据缺失 dueAt 应为 nil")
    try check(decoded.description == nil, "旧数据缺失 description 应为 nil")
    try check(decoded.status == .todo, "旧的未完成任务应映射为 todo")

    let decodedCompleted = try require(store.items.first { $0.title == "旧完成任务" }, "应读取已完成旧任务")
    try check(decodedCompleted.status == .done, "旧的已完成任务应映射为 done")
    try check(decodedCompleted.isCompleted, "旧的已完成任务应保持完成")

    let migrated = makeStore(in: temporaryDirectory)
    try migrated.load()
    try check(migrated.items.first { $0.title == "旧任务" }?.status == .todo, "旧数据保存后应保留 todo 状态")
}

func checkDoingItemsAreSortedBeforeTodoItems() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    let doing = try require(
        try store.add(title: "Doing-低", group: "默认", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0), priority: .low),
        "expected doing task"
    )
    _ = try store.setStatus(doing.id, status: .doing, at: now)
    _ = try store.add(
        title: "Todo-高", group: "默认",
        createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 10, minute: 0),
        priority: .high
    )

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["Doing-低", "Todo-高"], "Doing 应排在所有 Todo 前，实际: \(titles)")

    let hudItems = store.hudItems(scope: .all, maxCount: 1, now: now, calendar: checkCalendar)
    try check(hudItems.map(\.title) == ["Doing-低"], "HUD 条数上限应优先保留 Doing")
}

func checkHudProjectionFocusesDoing() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
    let doing = try require(try store.add(title: "进行中", group: "默认"), "expected doing task")
    _ = try store.setStatus(doing.id, status: .doing, at: now)
    _ = try store.add(title: "待办一", group: "默认")
    _ = try store.add(title: "待办二", group: "默认")

    let projection = store.hudProjection(scope: .all, maxCount: 10, focusDoing: true, now: now, calendar: checkCalendar)
    try check(projection.doing.map(\.title) == ["进行中"], "聚焦时应渲染 Doing，实际: \(projection.doing.map(\.title))")
    try check(projection.todo.isEmpty, "聚焦时不应渲染任何 Todo，实际: \(projection.todo.map(\.title))")
    try check(projection.doingCount == 1, "Doing 计数应为 1，实际: \(projection.doingCount)")
    try check(projection.todoCount == 2, "Todo 计数应仍为 2（计数不受隐藏影响），实际: \(projection.todoCount)")
}

func checkHudProjectionWithoutDoingShowsTodo() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
    _ = try store.add(title: "待办一", group: "默认")

    let projection = store.hudProjection(scope: .all, maxCount: 10, focusDoing: true, now: now, calendar: checkCalendar)
    try check(projection.doing.isEmpty, "无 Doing 时 Doing 组应为空")
    try check(projection.todo.map(\.title) == ["待办一"], "无 Doing 时聚焦不应隐藏 Todo，实际: \(projection.todo.map(\.title))")
    try check(projection.todoCount == 1, "Todo 计数应为 1，实际: \(projection.todoCount)")
}

func checkHudProjectionDisabledShowsBothSections() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
    let doing = try require(
        try store.add(title: "进行中", group: "默认", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0), priority: .low),
        "expected doing task"
    )
    _ = try store.setStatus(doing.id, status: .doing, at: now)
    _ = try store.add(
        title: "待办-高", group: "默认",
        createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 10, minute: 0),
        priority: .high
    )

    let projection = store.hudProjection(scope: .all, maxCount: 10, focusDoing: false, now: now, calendar: checkCalendar)
    try check(
        projection.doing.map(\.title) == ["进行中"],
        "关闭聚焦时应渲染 Doing，实际: \(projection.doing.map(\.title))"
    )
    try check(
        projection.todo.map(\.title) == ["待办-高"],
        "关闭聚焦时应同时渲染 Todo，实际: \(projection.todo.map(\.title))"
    )
    try check(projection.doingCount == 1 && projection.todoCount == 1, "关闭聚焦时计数应为 1/1")
}

func checkHudProjectionLimitAppliesToRenderedItems() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
    let doing = try require(
        try store.add(title: "进行中", group: "默认", createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 9, minute: 0), priority: .low),
        "expected doing task"
    )
    _ = try store.setStatus(doing.id, status: .doing, at: now)
    for index in 0..<5 {
        _ = try store.add(
            title: "待办-高\(index)", group: "默认",
            createdAt: makeDate(year: 2026, month: 6, day: 15, hour: 10, minute: index),
            priority: .high
        )
    }

    // 上限为 3 时，聚焦模式必须把 3 个名额全部给 Doing 集合，而不是被 Todo 占满。
    let focused = store.hudProjection(scope: .all, maxCount: 3, focusDoing: true, now: now, calendar: checkCalendar)
    try check(focused.doing.map(\.title) == ["进行中"], "聚焦时上限应只作用于 Doing，实际: \(focused.doing.map(\.title))")
    try check(focused.todo.isEmpty, "聚焦时不应渲染 Todo，实际: \(focused.todo.map(\.title))")

    let unfocused = store.hudProjection(scope: .all, maxCount: 3, focusDoing: false, now: now, calendar: checkCalendar)
    let rendered = unfocused.doing + unfocused.todo
    try check(rendered.count == 3, "关闭聚焦时渲染总数应为 3，实际: \(rendered.count)")
    try check(
        unfocused.doing.map(\.title) == ["进行中"],
        "关闭聚焦时 Doing 应优先占用上限，实际: \(unfocused.doing.map(\.title))"
    )
    try check(
        unfocused.todo.count == 2,
        "关闭聚焦时剩余名额应给 Todo，实际: \(unfocused.todo.count)"
    )
}

func checkHudProjectionCountsAreIndependent() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)
    for index in 0..<2 {
        let doing = try require(try store.add(title: "进行中\(index)", group: "默认"), "expected doing task")
        _ = try store.setStatus(doing.id, status: .doing, at: now)
    }
    for index in 0..<5 {
        _ = try store.add(title: "待办\(index)", group: "默认")
    }

    // 上限设为 1：渲染集合被截断，但分区计数仍反映显示范围内的完整数量。
    let projection = store.hudProjection(scope: .all, maxCount: 1, focusDoing: true, now: now, calendar: checkCalendar)
    try check(projection.doingCount == 2, "Doing 计数应为 2，实际: \(projection.doingCount)")
    try check(projection.todoCount == 5, "Todo 计数应为 5，实际: \(projection.todoCount)")
    try check(projection.doing.count == 1, "上限为 1 时渲染的 Doing 应为 1，实际: \(projection.doing.count)")
    try check(projection.todo.isEmpty, "聚焦时不应渲染 Todo")
    try check(
        projection.doingCount > projection.doing.count && projection.todoCount > projection.todo.count,
        "分区计数应独立于截断且隐藏后的渲染集合"
    )
}

func checkSortsOpenItemsByPriorityThenDueDate() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try store.add(title: "中-明天", group: "默认", priority: .medium, dueAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 0))
    _ = try store.add(title: "高-无截止", group: "默认", priority: .high)
    _ = try store.add(title: "低-今天", group: "默认", priority: .low, dueAt: makeDate(year: 2026, month: 6, day: 15, hour: 18, minute: 0))
    _ = try store.add(title: "高-今天", group: "默认", priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 15, hour: 18, minute: 0))

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

    _ = try store.add(title: "高-已过期", group: "默认", priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 14, hour: 10, minute: 0))
    _ = try store.add(title: "低-未过期", group: "默认", priority: .low, dueAt: makeDate(year: 2026, month: 6, day: 16, hour: 9, minute: 0))

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["低-未过期", "高-已过期"], "过期任务应全局沉底，实际: \(titles)")
}

func checkSortsItemsWithoutDueDateLast() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    let now = makeDate(year: 2026, month: 6, day: 15, hour: 12, minute: 0)

    _ = try store.add(title: "有截止", group: "默认", priority: .high, dueAt: makeDate(year: 2026, month: 6, day: 20, hour: 9, minute: 0))
    _ = try store.add(title: "无截止", group: "默认", priority: .high)

    let titles = store.openItems(now: now).map(\.title)
    try check(titles == ["有截止", "无截止"], "同优先级无截止日期应排后，实际: \(titles)")
}

func checkLoadReflectsExternalChange() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    _ = try require(try store.add(title: "初始任务", group: "默认"), "expected todo")

    let external = makeStore(in: temporaryDirectory)
    try external.load()
    _ = try require(try external.add(title: "外部任务", group: "默认"), "expected external todo")

    try store.load()
    try check(store.items.map(\.title) == ["外部任务", "初始任务"], "load should reflect external change")
}

func checkLoadSkipsPublishWhenUnchanged() throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let store = makeStore(in: temporaryDirectory)
    _ = try require(try store.add(title: "任务", group: "默认"), "expected todo")

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
    _ = try require(try store.add(title: "任务", group: "默认"), "expected todo")

    try FileManager.default.removeItem(at: temporaryDirectory.appendingPathComponent("todos.json"))

    try store.load()
    try check(store.items.isEmpty, "load should clear items when file missing")
}

func checkSequentialIDsAcrossGroups() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeStore(in: directory)
    let first = try require(try store.add(title: "默认任务", group: "默认"), "应创建任务")
    let second = try require(try store.add(title: "项目任务", group: "项目"), "应创建任务")
    try check([first.id, second.id] == [10000, 10001], "各组必须共享编号")
    try store.delete(second.id)
    let reloaded = makeStore(in: directory)
    let third = try require(try reloaded.add(title: "继续编号", group: "默认"), "应创建任务")
    try check(third.id == 10002, "删除最大 ID 后不得复用")
    try reloaded.delete(first.id)
    try reloaded.delete(third.id)
    let fourth = try require(try makeStore(in: directory).add(title: "清空后新增", group: "默认"), "应创建任务")
    try check(fourth.id == 10003, "清空任务后仍须继续编号")
}

func checkGroupAndStaleWrites() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stale = makeStore(in: directory)
    let task = try require(try stale.add(title: "原任务", group: "默认"), "应创建任务")
    let external = makeStore(in: directory)
    _ = try external.update(task.id, title: "外部标题", group: "  完整项目名称  ")
    let added = try require(try external.add(title: "外部新增", group: "另一组"), "应创建任务")
    _ = try stale.setStatus(task.id, status: .doing)
    try stale.markTimedReminderSent(task.id)
    let loaded = try require(stale.items.first { $0.id == task.id }, "应保留目标任务")
    try check(loaded.title == "外部标题" && loaded.group == "完整项目名称", "旧快照不能覆盖标题和组别")
    try check(stale.items.contains { $0.id == added.id }, "旧快照不能覆盖外部新增")
    try check(loaded.reminderSentAt != nil && loaded.status == .doing, "状态和提醒回写应保留")
    _ = try external.advanceStatus(task.id)
    _ = try stale.advanceStatus(task.id)
    try check(stale.items.first { $0.id == task.id }?.status == .done, "状态推进必须以最新文档为准，不重开已完成任务")
    try external.delete(task.id)
    try check(try stale.setStatus(task.id, status: .done) == nil, "不得恢复已删除任务")
    let before = try Data(contentsOf: directory.appendingPathComponent("todos.json"))
    do {
        _ = try stale.add(title: "无效组", group: " \n ")
        throw CheckFailure(message: "空组名应失败")
    } catch is CheckFailure {
        throw CheckFailure(message: "空组名未被拒绝")
    } catch {
        try check(try Data(contentsOf: directory.appendingPathComponent("todos.json")) == before, "无效输入不能改文件")
    }
}

func checkLegacyGroupAndIDMigration() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("todos.json")
    let data = Data("""
    [
      {"id":"00000000-0000-0000-0000-000000000002","title":"较晚","createdAt":"2026-06-20T02:00:00Z","status":"doing","priority":"high","description":"保留描述"},
      {"id":"00000000-0000-0000-0000-000000000003","title":"同日完成","createdAt":"2026-06-19T02:00:00Z","completedAt":"2026-06-20T02:00:00Z"},
      {"id":"00000000-0000-0000-0000-000000000001","title":"同日待办","createdAt":"2026-06-19T02:00:00Z","reminderAt":"2026-06-21T02:00:00Z"}
    ]
    """.utf8)
    try data.write(to: file)
    let store = makeStore(in: directory)
    try check(try store.setStatus(99999, status: .done) == nil, "不存在的目标应失败")
    try check(try Data(contentsOf: file) == data, "失败操作不得先迁移")
    try check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("todos.v1.backup.json").path), "失败操作不得先备份")
    try store.load()
    try check(store.items.allSatisfy { $0.group == "默认" }, "全部历史任务必须迁入默认组")
    try check(store.items.first { $0.title == "同日待办" }?.id == 10000, "同时间应按 UUID 稳定编号")
    try check(store.items.first { $0.title == "同日完成" }?.id == 10001, "已完成任务也应编号")
    try check(store.items.first { $0.title == "同日完成" }?.status == .done, "应兼容缺失 status")
    try check(store.items.first { $0.title == "较晚" }?.description == "保留描述", "业务字段不得丢失")
    try check(try Data(contentsOf: directory.appendingPathComponent("todos.v1.backup.json")) == data, "备份必须逐字节一致")
    let migrated = try Data(contentsOf: file)
    try store.load()
    try check(try Data(contentsOf: file) == migrated, "重复加载不得重新编号")
    let added = try require(try store.add(title: "迁移后新增", group: "项目"), "应新增")
    try check(added.id == 10003, "迁移后应接续编号")
}

func checkInvalidDocumentsAndBackupConflict() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("todos.json")
    let store = makeStore(in: directory)
    _ = try store.add(title: "有效任务", group: "默认")
    let valid = try Data(contentsOf: file)
    let object = try require(try JSONSerialization.jsonObject(with: valid) as? [String: Any], "应为文档对象")
    var invalidDocuments = [
        ["schemaVersion": 999, "nextID": 10001, "items": object["items"]!] as [String: Any],
        ["schemaVersion": 2, "nextID": 10000, "items": object["items"]!] as [String: Any]
    ]
    let originalItems = try require(object["items"] as? [[String: Any]], "应包含任务数组")
    for (key, value) in [("group", "" as Any), ("group", " 前导空格" as Any), ("id", 9999 as Any), ("id", 10000.5 as Any)] {
        var item = originalItems[0]
        item[key] = value
        invalidDocuments.append(["schemaVersion": 2, "nextID": 10001, "items": [item]])
    }
    invalidDocuments.append(["schemaVersion": 2, "nextID": 10001, "items": originalItems + originalItems])
    for invalid in invalidDocuments {
        let corrupt = try JSONSerialization.data(withJSONObject: invalid)
        try corrupt.write(to: file)
        do {
            try store.load()
            throw CheckFailure(message: "无效文档必须失败")
        } catch is CheckFailure {
            throw CheckFailure(message: "无效文档未被拒绝")
        } catch {
            try check(store.items.count == 1, "失败加载应保留有效快照")
            try check(try Data(contentsOf: file) == corrupt, "不得重置无效文档")
        }
    }
    let legacy = Data("[]".utf8)
    try legacy.write(to: file)
    try Data("旧备份".utf8).write(to: directory.appendingPathComponent("todos.v1.backup.json"))
    do {
        try store.load()
        throw CheckFailure(message: "备份冲突必须失败")
    } catch is CheckFailure {
        throw CheckFailure(message: "备份冲突未被拒绝")
    } catch {
        try check(try Data(contentsOf: file) == legacy, "冲突不能覆盖旧任务")
    }
}

func makeStore(in temporaryDirectory: URL) -> TodoStore {
    TodoStore(fileURL: temporaryDirectory.appendingPathComponent("todos.json"))
}

func checkSharedGroupFixtures() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("windows-native/tests/fixtures")
    let legacy = try Data(contentsOf: fixtures.appendingPathComponent("tasks-groups-legacy.json"))
    try legacy.write(to: directory.appendingPathComponent("todos.json"))
    let expected = try JSONFile.load(TaskDocument.self, from: fixtures.appendingPathComponent("tasks-groups-v2.json"))
    let store = makeStore(in: directory)
    try store.load()
    let actual = try JSONFile.load(TaskDocument.self, from: directory.appendingPathComponent("todos.json"))
    try check(actual == expected, "Swift 迁移应符合共享夹具的全部字段和稳定映射")
    let encoded = try JSONEncoder.ghostPin.encode(actual)
    try check(try JSONDecoder.ghostPin.decode(TaskDocument.self, from: encoded) == expected, "新文档应可往返编码")
    let payload = try JSONSerialization.jsonObject(with: JSONEncoder.ghostPin.encode(TodoItemPayload(actual.items[0]))) as? [String: Any]
    try check(payload?["id"] as? Int == 10000 && payload?["group"] as? String == "默认", "CLI payload 必须包含数字 ID 和完整组别")
    let docs = fixtures.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/task-storage.md")
    let example = try String(contentsOf: docs, encoding: .utf8).components(separatedBy: "```json\n")[1].components(separatedBy: "```\n")[0]
    try JSONDecoder.ghostPin.decode(TaskDocument.self, from: Data(example.utf8)).validate()
}

func checkConcurrentProcesses() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let workers = try (1...2).map { index in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--storage-worker", directory.path, "任务\(index)"]
        try process.run()
        return process
    }
    defer { workers.filter(\.isRunning).forEach { $0.terminate() } }
    let deadline = Date().addingTimeInterval(5)
    while try FileManager.default.contentsOfDirectory(atPath: directory.path).filter({ $0.hasPrefix("ready-") }).count < 2 {
        guard Date() < deadline else { throw CheckFailure(message: "工作进程未就绪") }
        Thread.sleep(forTimeInterval: 0.01)
    }
    try Data().write(to: directory.appendingPathComponent("go"))
    for worker in workers {
        worker.waitUntilExit()
        try check(worker.terminationStatus == 0, "并发进程应成功退出")
    }
    let store = makeStore(in: directory)
    try store.load()
    try check(store.items.map(\.id).sorted() == [10000, 10001], "并发写入不得丢失任务或重复 ID")
}

final class CommitFailingFileManager: FileManager, @unchecked Sendable {
    private var directoryCalls = 0

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        directoryCalls += 1
        if directoryCalls == 2 { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

func checkFailedCommitAndRetry() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("todos.json")
    let legacy = Data("[]".utf8)
    try legacy.write(to: file)
    let failing = TodoStore(fileURL: file, fileManager: CommitFailingFileManager())
    var published = 0
    let subscription = failing.objectWillChange.sink { published += 1 }
    do {
        _ = try failing.add(title: "失败任务", group: "默认")
        throw CheckFailure(message: "模拟提交应失败")
    } catch is CheckFailure {
        throw CheckFailure(message: "模拟提交未失败")
    } catch {
        try check(failing.items.isEmpty && published == 0, "提交失败不得发布内存状态")
        try check(try Data(contentsOf: file) == legacy, "提交失败应保留原始任务")
        try check(try Data(contentsOf: directory.appendingPathComponent("todos.v1.backup.json")) == legacy, "提交前原始备份已完成")
    }
    withExtendedLifetime(subscription) {}
    let retry = makeStore(in: directory)
    let added = try require(try retry.add(title: "重试任务", group: "默认"), "重试应成功")
    try check(added.id == 10000, "失败不得消耗编号，空数组可重复迁移")
    let before = try Data(contentsOf: file)
    let failingUpdate = TodoStore(fileURL: file, fileManager: CommitFailingFileManager(), initialItems: retry.items)
    do {
        _ = try failingUpdate.add(title: "再次失败", group: "项目")
        throw CheckFailure(message: "模拟提交应失败")
    } catch is CheckFailure {
        throw CheckFailure(message: "模拟提交未失败")
    } catch {
        try check(try Data(contentsOf: file) == before, "新格式提交失败应保留计数器")
        try check(failingUpdate.items == retry.items, "新格式提交失败应保留快照")
    }
}

func checkGroupedHudProjection() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeStore(in: directory)
    let now = makeDate(year: 2026, month: 6, day: 20, hour: 12, minute: 0)
    let doing = try require(try store.add(title: "进行中", group: "项目甲", createdAt: now, priority: .low), "应创建")
    _ = try store.advanceStatus(doing.id)
    _ = try store.add(title: "高优先级", group: "项目乙", createdAt: now, priority: .high)
    _ = try store.add(title: "旧任务", group: "默认", createdAt: now.addingTimeInterval(-86400))
    let focused = store.hudProjection(scope: .all, maxCount: 1, focusDoing: true, now: now, calendar: checkCalendar)
    try check(focused.doing.map(\.group) == ["项目甲"] && focused.todoCount == 2, "聚焦和计数应跨组执行")
    let today = store.hudProjection(scope: .today, maxCount: 10, focusDoing: false, now: now, calendar: checkCalendar)
    try check(today.doing.count == 1 && today.todo.map(\.group) == ["项目乙"], "日期范围和分区不应按组分裂")
    try check(try store.listItems(group: "项目乙").map(\.title) == ["高优先级"], "组别查询应精确过滤")
    try check(try store.listItems(group: "不存在").isEmpty, "未知组应返回空列表")
}

func makeSkill(in directory: URL, content: String = "新版") throws {
    try FileManager.default.createDirectory(at: directory.appendingPathComponent("agents"), withIntermediateDirectories: true)
    try Data().write(to: directory.appendingPathComponent("ghostpin-cli"))
    try Data(content.utf8).write(to: directory.appendingPathComponent("SKILL.md"))
    try Data("配置 \(content)".utf8).write(to: directory.appendingPathComponent("agents/openai.yaml"))
}

func checkSkillInstallAndReplace() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    let target = directory.appendingPathComponent("home/.agents/skills/ghostpin-cli")
    try makeSkill(in: source)
    try FileManager.default.createDirectory(at: source.appendingPathComponent("nested/empty"), withIntermediateDirectories: true)
    try Data("辅助".utf8).write(to: source.appendingPathComponent("nested/.hidden"))
    try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("reference").path, withDestinationPath: "SKILL.md")
    let installer = SkillInstaller()
    let installed = try installer.install(from: source, at: target)
    try check(installed.path == physicalPath(target), "成功结果应为实际绝对路径")
    try check(try Data(contentsOf: target.appendingPathComponent("nested/.hidden")) == Data("辅助".utf8), "应复制完整目录")
    try check(try FileManager.default.destinationOfSymbolicLink(atPath: target.appendingPathComponent("reference").path) == "SKILL.md", "辅助链接应完整复制")
    try check(FileManager.default.fileExists(atPath: target.appendingPathComponent("nested/empty").path), "空子目录应保留")
    let other = target.deletingLastPathComponent().appendingPathComponent("other-skill")
    try FileManager.default.createSymbolicLink(atPath: other.path, withDestinationPath: "../untouched")
    try Data("旧文件".utf8).write(to: target.appendingPathComponent("old.txt"))
    try Data("本地修改".utf8).write(to: target.appendingPathComponent("SKILL.md"))
    try Data("旧标记内容不影响归属".utf8).write(to: target.appendingPathComponent("ghostpin-cli"))
    _ = try installer.install(from: source, at: target)
    _ = try installer.install(from: source, at: target)
    try check(try Data(contentsOf: target.appendingPathComponent("SKILL.md")) == Data("新版".utf8), "应覆盖本地修改且可重复执行")
    try check(!FileManager.default.fileExists(atPath: target.appendingPathComponent("old.txt").path), "应删除旧版多余文件")
    try check(try Data(contentsOf: target.appendingPathComponent("ghostpin-cli")).isEmpty, "应以随包空标记替换旧标记")
    try check(try FileManager.default.destinationOfSymbolicLink(atPath: other.path) == "../untouched", "其他 skill 应保持原样")
    try check(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path).sorted() == ["ghostpin-cli", "other-skill"], "成功后应清理临时项")
}

func checkInvalidSkillSources() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for missing in ["ghostpin-cli", "SKILL.md", "agents/openai.yaml", "agents", ""] {
        let fixture = directory.appendingPathComponent(UUID().uuidString)
        let source = fixture.appendingPathComponent("source")
        let target = fixture.appendingPathComponent("target")
        try makeSkill(in: source)
        try makeSkill(in: target, content: "旧版")
        try FileManager.default.removeItem(at: missing.isEmpty ? source : source.appendingPathComponent(missing))
        try expectSkillFailure { _ = try SkillInstaller().install(from: source, at: target) }
        try check(try Data(contentsOf: target.appendingPathComponent("SKILL.md")) == Data("旧版".utf8), "来源不完整不得替换旧目录")
        let fresh = fixture.appendingPathComponent("fresh/ghostpin-cli")
        try expectSkillFailure { _ = try SkillInstaller().install(from: source, at: fresh) }
        try check(!FileManager.default.fileExists(atPath: fresh.deletingLastPathComponent().path), "来源不完整不得创建目标父目录")
    }
    for invalid in ["directory", "link", "nonempty"] {
        let source = directory.appendingPathComponent("source-\(invalid)")
        try makeSkill(in: source)
        let marker = source.appendingPathComponent("ghostpin-cli")
        try FileManager.default.removeItem(at: marker)
        switch invalid {
        case "directory": try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
        case "link": try FileManager.default.createSymbolicLink(atPath: marker.path, withDestinationPath: "SKILL.md")
        default: try Data("非空".utf8).write(to: marker)
        }
        let target = directory.appendingPathComponent("fresh-\(invalid)/ghostpin-cli")
        try expectSkillFailure { _ = try SkillInstaller().install(from: source, at: target) }
        try check(!FileManager.default.fileExists(atPath: target.deletingLastPathComponent().path), "无效来源标记不得创建父目录")
    }
}

func checkSkillSymbolicLinks() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    try makeSkill(in: source)
    for mode in ["absolute", "relative", "chain", "parent", "dotdot", "input-dotdot", "repeated"] {
        let fixture = directory.appendingPathComponent(mode)
        let real = fixture.appendingPathComponent("real/skill")
        try makeSkill(in: real, content: "旧版")
        var target = fixture.appendingPathComponent("installed")
        var links: [String: String] = [:]
        switch mode {
        case "absolute": links[target.path] = real.path
        case "relative": links[target.path] = "real/skill"
        case "chain":
            links[target.path] = "middle"
            links[fixture.appendingPathComponent("middle").path] = "real/skill"
        case "parent":
            links[target.path] = "real"
            target.appendPathComponent("skill")
        case "dotdot", "input-dotdot":
            try FileManager.default.createDirectory(at: fixture.appendingPathComponent("real/inner"), withIntermediateDirectories: false)
            links[fixture.appendingPathComponent("shortcut").path] = "real/inner"
            // 词法规整会误选 fixture/skill；实际目标应是 real/skill。
            try makeSkill(in: fixture.appendingPathComponent("skill"), content: "不应替换")
            if mode == "dotdot" {
                links[target.path] = "shortcut/../skill"
            } else {
                target = URL(fileURLWithPath: fixture.path + "/shortcut/../skill")
            }
        default:
            links[fixture.appendingPathComponent("shortcut").path] = "real"
            target = URL(fileURLWithPath: fixture.path + "/shortcut/../shortcut/skill")
        }
        for (path, destination) in links {
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
        }
        let installed = try SkillInstaller().install(from: source, at: target)
        try check(installed.path == physicalPath(real), "\(mode) 应返回最终真实目录")
        try check(try Data(contentsOf: real.appendingPathComponent("SKILL.md")) == Data("新版".utf8), "\(mode) 应替换真实目录")
        for (path, text) in links {
            try check(try FileManager.default.destinationOfSymbolicLink(atPath: path) == text, "\(mode) 应保留全部链接文本")
        }
        if mode == "dotdot" || mode == "input-dotdot" {
            try check(try Data(contentsOf: fixture.appendingPathComponent("skill/SKILL.md")) == Data("不应替换".utf8), "不得替换词法规整所得目录")
        }
    }
}

func checkInvalidSkillTargets() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    try makeSkill(in: source)
    for mode in ["unmarked", "marker-directory", "marker-link", "unmarked-link", "file", "file-link", "broken", "cycle", "parent-broken", "parent-cycle"] {
        let fixture = directory.appendingPathComponent(mode)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        var target = fixture.appendingPathComponent("installed")
        let originalTarget = target
        var links: [String: String] = [:]
        let real = fixture.appendingPathComponent("real")
        if ["file", "file-link"].contains(mode) {
            try Data("保留文件".utf8).write(to: mode == "file" ? target : real)
            if mode == "file-link" { links[target.path] = "real" }
        } else if mode == "broken" || mode == "parent-broken" {
            links[target.path] = "missing"
        } else if mode == "cycle" || mode == "parent-cycle" {
            links[target.path] = "middle"
            links[fixture.appendingPathComponent("middle").path] = "installed"
        } else {
            let contentDirectory = mode == "unmarked-link" ? real : target
            try makeSkill(in: contentDirectory, content: "旧版")
            let marker = contentDirectory.appendingPathComponent("ghostpin-cli")
            try FileManager.default.removeItem(at: marker)
            if mode == "marker-directory" {
                try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
            } else if mode == "marker-link" {
                try FileManager.default.createSymbolicLink(atPath: marker.path, withDestinationPath: "SKILL.md")
            }
            if mode == "unmarked-link" { links[target.path] = "real" }
        }
        for (path, text) in links { try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: text) }
        if mode.hasPrefix("parent-") { target.appendPathComponent("ghostpin-cli") }
        try expectSkillFailure { _ = try SkillInstaller().install(from: source, at: target) }
        for (path, text) in links {
            try check(try FileManager.default.destinationOfSymbolicLink(atPath: path) == text, "拒绝时应保留 \(mode) 链接")
        }
        if mode == "file" || mode == "file-link" {
            try check(try Data(contentsOf: mode == "file" ? target : real) == Data("保留文件".utf8), "拒绝时应保留普通文件")
        } else if ["unmarked", "marker-directory", "marker-link", "unmarked-link"].contains(mode) {
            let contentDirectory = mode == "unmarked-link" ? real : originalTarget
            try check(try Data(contentsOf: contentDirectory.appendingPathComponent("SKILL.md")) == Data("旧版".utf8), "拒绝时应保留目录内容")
        }
        try check(!FileManager.default.fileExists(atPath: fixture.appendingPathComponent("missing").path), "断链不得被创建为新目录")
        try check(try FileManager.default.contentsOfDirectory(atPath: fixture.path).allSatisfy { !$0.hasPrefix(".ghostpin-cli-") }, "拒绝时不得创建临时项")
    }
}

final class SkillFailingFileManager: FileManager, @unchecked Sendable {
    enum Failure { case copy, incompleteCopy, changedCopy, backup, commit, restore, cleanup }
    let failure: Failure

    init(_ failure: Failure) { self.failure = failure }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if failure == .copy {
            try createDirectory(at: dstURL, withIntermediateDirectories: false)
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.copyItem(at: srcURL, to: dstURL)
        if failure == .incompleteCopy { try removeItem(at: dstURL.appendingPathComponent("agents/openai.yaml")) }
        if failure == .changedCopy { try Data("错误副本".utf8).write(to: dstURL.appendingPathComponent("SKILL.md")) }
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if (failure == .backup && dstURL.path.hasSuffix(".backup")) ||
            ([.commit, .restore].contains(failure) && srcURL.path.hasSuffix(".staging")) ||
            (failure == .restore && srcURL.path.hasSuffix(".backup")) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at URL: URL) throws {
        if failure == .cleanup && URL.path.hasSuffix(".backup") { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: URL)
    }
}

func checkSkillCopyFailures() throws {
    for failure in [SkillFailingFileManager.Failure.copy, .incompleteCopy, .changedCopy, .backup] {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let target = directory.appendingPathComponent("target")
        try makeSkill(in: source)
        try makeSkill(in: target, content: "旧版")
        try expectSkillFailure { _ = try SkillInstaller(fileManager: SkillFailingFileManager(failure)).install(from: source, at: target) }
        try check(try Data(contentsOf: target.appendingPathComponent("SKILL.md")) == Data("旧版".utf8), "准备或备份失败应保留旧版")
        try check(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["source", "target"], "失败应清理临时项")
    }
}

final class SkillChangingTargetFileManager: FileManager, @unchecked Sendable {
    let target: URL
    let replaceDirectory: Bool

    init(target: URL, replaceDirectory: Bool) {
        self.target = target
        self.replaceDirectory = replaceDirectory
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: srcURL, to: dstURL)
        if replaceDirectory {
            try removeItem(at: target)
            try makeSkill(in: target, content: "外部新目录")
        }
        try removeItem(at: target.appendingPathComponent("ghostpin-cli"))
    }
}

func checkSkillTargetChanges() throws {
    for replaceDirectory in [false, true] {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let target = directory.appendingPathComponent("target")
        try makeSkill(in: source)
        try makeSkill(in: target, content: "旧版")
        let fileManager = SkillChangingTargetFileManager(target: target, replaceDirectory: replaceDirectory)
        try expectSkillFailure { _ = try SkillInstaller(fileManager: fileManager).install(from: source, at: target) }
        let expected = replaceDirectory ? "外部新目录" : "旧版"
        try check(try Data(contentsOf: target.appendingPathComponent("SKILL.md")) == Data(expected.utf8), "提交前发现无标记目标应保留现有目录")
        try check(!FileManager.default.fileExists(atPath: target.appendingPathComponent("ghostpin-cli").path), "不得自动补标记认领目标")
        try check(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["source", "target"], "拒绝后应清理临时项")
    }
}

func checkSkillCommitFailure() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    let real = directory.appendingPathComponent("real")
    let link = directory.appendingPathComponent("installed")
    try makeSkill(in: source)
    try makeSkill(in: real, content: "旧版")
    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "real")
    try expectSkillFailure { _ = try SkillInstaller(fileManager: SkillFailingFileManager(.commit)).install(from: source, at: link) }
    try check(try Data(contentsOf: link.appendingPathComponent("SKILL.md")) == Data("旧版".utf8), "提交失败后原链接应可访问恢复的旧目录")
    try check(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "real", "恢复后应保留链接文本")
    try check(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["installed", "real", "source"], "恢复后应清理临时项")
}

func checkSkillRestoreFailure() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    let target = directory.appendingPathComponent("target")
    try makeSkill(in: source)
    try makeSkill(in: target, content: "旧版")
    let message = try expectSkillFailure { _ = try SkillInstaller(fileManager: SkillFailingFileManager(.restore)).install(from: source, at: target) }
    let backupName = try require(try FileManager.default.contentsOfDirectory(atPath: directory.path).first { $0.hasSuffix(".backup") }, "应保留旧目录副本")
    let backup = directory.appendingPathComponent(backupName)
    try check(message.contains(try physicalPath(backup)), "恢复失败必须报告旧副本的绝对路径")
    try check(try Data(contentsOf: backup.appendingPathComponent("SKILL.md")) == Data("旧版".utf8), "旧副本应完整保留")
    try check(!FileManager.default.fileExists(atPath: target.path), "恢复失败不得伪造目标成功")
}

func checkSkillCleanupFailure() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source")
    let target = directory.appendingPathComponent("target")
    try makeSkill(in: source)
    try makeSkill(in: target, content: "旧版")
    let message = try expectSkillFailure { _ = try SkillInstaller(fileManager: SkillFailingFileManager(.cleanup)).install(from: source, at: target) }
    try check(message.contains("新 skill 已安装到") && message.contains(".backup"), "提交后清理失败应明确安装已完成并报告备份")
    try check(try Data(contentsOf: target.appendingPathComponent("SKILL.md")) == Data("新版".utf8), "清理失败时新目录已经提交")
}

@discardableResult
func expectSkillFailure(_ operation: () throws -> Void) throws -> String {
    do {
        try operation()
        throw CheckFailure(message: "操作应失败")
    } catch let failure as CheckFailure {
        throw failure
    } catch {
        return error.localizedDescription
    }
}

func physicalPath(_ url: URL) throws -> String {
    guard let path = realpath(url.path, nil) else { throw CocoaError(.fileReadNoSuchFile) }
    defer { free(path) }
    return String(cString: path)
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("GhostPinChecks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() {
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
