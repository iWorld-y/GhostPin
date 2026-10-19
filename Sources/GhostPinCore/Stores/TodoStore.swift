import Combine
import Foundation

public final class TodoStore: ObservableObject {
    @Published public private(set) var items: [TodoItem]

    private let storage: TaskStorage

    public init(
        fileURL: URL,
        legacyFileURL: URL? = nil,
        fileManager: FileManager = .default,
        initialItems: [TodoItem] = []
    ) {
        self.storage = TaskStorage(fileURL: fileURL, legacyFileURL: legacyFileURL, fileManager: fileManager)
        self.items = Self.sortByCreatedAtDescending(initialItems)
    }

    public convenience init(fileManager: FileManager = .default) throws {
        try self.init(
            fileURL: StorageLocations.todosURL(fileManager: fileManager),
            legacyFileURL: StorageLocations.legacyTodosURL(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    public func load() throws {
        try transact(write: false) { _ in () }
    }

    private func transact<Result>(
        write: Bool = true,
        _ operation: (inout TaskDocument) throws -> Result
    ) throws -> Result {
        let (result, document) = try storage.access(write: write, operation)
        let loaded = Self.sortByCreatedAtDescending(document.items)
        if try JSONFile.canonicalData(loaded) != JSONFile.canonicalData(items) {
            items = loaded
        }
        return result
    }

    @discardableResult
    public func add(
        title: String,
        group: String,
        createdAt: Date = Date(),
        reminderAt: Date? = nil,
        priority: Priority = .medium,
        dueAt: Date? = nil,
        description: String? = nil
    ) throws -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalizedGroup = try TaskGroup.normalize(group)
        return try transact { document in
            guard document.nextID <= TaskDocument.maximumID else {
                throw TaskStorageError.invalidDocument("任务编号已用尽")
            }
            let item = TodoItem(
                id: document.nextID,
                group: normalizedGroup,
                title: trimmed,
                createdAt: createdAt,
                reminderAt: reminderAt,
                priority: priority,
                dueAt: dueAt,
                description: description
            )
            document.nextID += 1
            document.items.append(item)
            return item
        }
    }

    private func change(
        _ id: TodoItem.ID,
        _ operation: (inout TodoItem) -> Void
    ) throws -> TodoItem? {
        do {
            return try transact { document in
                guard let index = document.items.firstIndex(where: { $0.id == id }) else {
                    throw TaskStorageError.itemNotFound(id)
                }
                operation(&document.items[index])
                return document.items[index]
            }
        } catch TaskStorageError.itemNotFound {
            return nil
        }
    }

    @discardableResult
    public func setStatus(
        _ id: TodoItem.ID,
        status: TodoStatus,
        at date: Date = Date()
    ) throws -> TodoItem? {
        try change(id) { item in
            guard item.status != status else { return }
            item.status = status
            item.completedAt = status == .done ? date : nil
        }
    }

    @discardableResult
    public func advanceStatus(_ id: TodoItem.ID, at date: Date = Date()) throws -> TodoItem? {
        try change(id) { item in
            switch item.status {
            case .todo:
                item.status = .doing
            case .doing:
                item.status = .done
                item.completedAt = date
            case .done:
                break
            }
        }
    }

    public func setCompleted(_ id: TodoItem.ID, completed: Bool, at date: Date = Date()) throws {
        _ = try setStatus(id, status: completed ? .done : .todo, at: date)
    }

    public func markTimedReminderSent(_ id: TodoItem.ID, at date: Date = Date()) throws {
        _ = try change(id) { $0.reminderSentAt = date }
    }

    @discardableResult
    public func updateTitle(_ id: TodoItem.ID, title: String) throws -> TodoItem? {
        try update(id, title: title)
    }

    @discardableResult
    public func update(
        _ id: TodoItem.ID,
        title: String? = nil,
        reminderAt: Date? = nil,
        clearReminder: Bool = false,
        priority: Priority? = nil,
        dueAt: Date? = nil,
        clearDue: Bool = false,
        description: String? = nil,
        group: String? = nil
    ) throws -> TodoItem? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed?.isEmpty == true { return nil }
        let normalizedGroup = try group.map(TaskGroup.normalize)
        return try change(id) { item in
            if let trimmed { item.title = trimmed }
            if reminderAt != nil || clearReminder {
                let newReminder = clearReminder ? nil : reminderAt
                if item.reminderAt != newReminder { item.reminderSentAt = nil }
                item.reminderAt = newReminder
            }
            if let priority { item.priority = priority }
            if dueAt != nil || clearDue { item.dueAt = clearDue ? nil : dueAt }
            if let description { item.description = description }
            if let normalizedGroup { item.group = normalizedGroup }
        }
    }

    public func delete(_ id: TodoItem.ID) throws {
        try transact { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else {
                throw TaskStorageError.itemNotFound(id)
            }
            document.items.remove(at: index)
        }
    }

    public func listItems(includeCompleted: Bool = false, group: String? = nil, now: Date = Date()) throws -> [TodoItem] {
        let normalizedGroup = try group.map(TaskGroup.normalize)
        let selected = includeCompleted ? items : openItems(now: now)
        return selected.filter { normalizedGroup == nil || $0.group == normalizedGroup }
    }

    public func openItems(now: Date = Date()) -> [TodoItem] {
        items.filter { !$0.isCompleted }
            .sorted { Self.isOrderedBefore($0, $1, now: now) }
    }

    public func hudItems(
        scope: HudScope,
        maxCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodoItem] {
        Array(scopedOpenItems(scope: scope, now: now, calendar: calendar).prefix(max(maxCount, 0)))
    }

    /// HUD 分区投影：返回实际渲染的 Doing / Todo 卡片与显示范围内的完整计数。
    ///
    /// `focusDoing` 开启且范围内存在 Doing 任务时只渲染 Doing，否则先保留 Doing
    /// 再补 Todo。条数上限只作用于实际渲染的集合，计数则不受上限影响，因此
    /// 隐藏 Todo 卡片时用户仍能看到被隐藏的数量。
    public func hudProjection(
        scope: HudScope,
        maxCount: Int,
        focusDoing: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HudProjection {
        let scoped = scopedOpenItems(scope: scope, now: now, calendar: calendar)
        let doingAll = scoped.filter { $0.status == .doing }
        let todoAll = scoped.filter { $0.status == .todo }
        let limit = max(maxCount, 0)

        if focusDoing, !doingAll.isEmpty {
            return HudProjection(
                doing: Array(doingAll.prefix(limit)),
                todo: [],
                doingCount: doingAll.count,
                todoCount: todoAll.count
            )
        }

        let rendered = Array(scoped.prefix(limit))
        return HudProjection(
            doing: rendered.filter { $0.status == .doing },
            todo: rendered.filter { $0.status == .todo },
            doingCount: doingAll.count,
            todoCount: todoAll.count
        )
    }

    /// 应用显示范围后的未完成任务，沿用 `openItems` 的既有排序。
    private func scopedOpenItems(scope: HudScope, now: Date, calendar: Calendar) -> [TodoItem] {
        let open = openItems(now: now)
        switch scope {
        case .all:
            return open
        case .today:
            let dayStart = calendar.ghostPinDayStart(for: now)
            return open.filter { $0.createdAt >= dayStart }
        }
    }

    public func completedItems(on date: Date, calendar: Calendar = .current) -> [TodoItem] {
        let start = calendar.ghostPinDayStart(for: date)
        let end = calendar.ghostPinDayEnd(for: date)
        return items.filter { item in
            guard item.isCompleted, let completedAt = item.completedAt else {
                return false
            }
            return completedAt >= start && completedAt <= end
        }
        .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    private static func sortByCreatedAtDescending(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { isNewer($0, than: $1) }
    }

    private static func isNewer(_ lhs: TodoItem, than rhs: TodoItem) -> Bool {
        lhs.createdAt == rhs.createdAt ? lhs.id > rhs.id : lhs.createdAt > rhs.createdAt
    }

    private static func isOrderedBefore(_ lhs: TodoItem, _ rhs: TodoItem, now: Date) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status == .doing
        }
        let lhsOverdue = lhs.isOverdue(now: now)
        let rhsOverdue = rhs.isOverdue(now: now)
        if lhsOverdue != rhsOverdue {
            return !lhsOverdue
        }
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        switch (lhs.dueAt, rhs.dueAt) {
        case let (lhsDue?, rhsDue?):
            if lhsDue != rhsDue {
                return lhsDue < rhsDue
            }
            return isNewer(lhs, than: rhs)
        case (nil, nil):
            return isNewer(lhs, than: rhs)
        case (nil, _):
            return false
        case (_, nil):
            return true
        }
    }
}
