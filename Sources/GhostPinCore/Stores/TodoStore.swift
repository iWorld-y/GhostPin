import Combine
import Foundation

public final class TodoStore: ObservableObject {
    @Published public private(set) var items: [TodoItem]

    private let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        initialItems: [TodoItem] = []
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.items = Self.sortByCreatedAtDescending(initialItems)
    }

    public convenience init(fileManager: FileManager = .default) throws {
        try self.init(fileURL: StorageLocations.todosURL(fileManager: fileManager), fileManager: fileManager)
        try load()
    }

    public func load() throws {
        do {
            let loaded = Self.sortByCreatedAtDescending(
                try JSONFile.load([TodoItem].self, from: fileURL, fileManager: fileManager)
            )
            if try JSONFile.canonicalData(loaded) != JSONFile.canonicalData(items) {
                items = loaded
            }
        } catch CocoaError.fileNoSuchFile {
            if !items.isEmpty {
                items = []
            }
        }
    }

    public func save() throws {
        try JSONFile.save(items, to: fileURL, fileManager: fileManager)
    }

    @discardableResult
    public func add(
        title: String,
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

        let item = TodoItem(
            title: trimmed,
            createdAt: createdAt,
            reminderAt: reminderAt,
            priority: priority,
            dueAt: dueAt,
            description: description
        )
        items.append(item)
        items = Self.sortByCreatedAtDescending(items)
        try save()
        return item
    }

    @discardableResult
    public func setStatus(
        _ id: TodoItem.ID,
        status: TodoStatus,
        at date: Date = Date()
    ) throws -> TodoItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        guard items[index].status != status else {
            return items[index]
        }
        items[index].status = status
        items[index].completedAt = status == .done ? date : nil
        try save()
        return items[index]
    }

    public func setCompleted(_ id: TodoItem.ID, completed: Bool, at date: Date = Date()) throws {
        _ = try setStatus(id, status: completed ? .done : .todo, at: date)
    }

    public func markTimedReminderSent(_ id: TodoItem.ID, at date: Date = Date()) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].reminderSentAt = date
        try save()
    }

    @discardableResult
    public func updateTitle(_ id: TodoItem.ID, title: String) throws -> TodoItem? {
        guard let current = items.first(where: { $0.id == id }) else {
            return nil
        }
        return try update(
            id,
            title: title,
            reminderAt: current.reminderAt,
            priority: current.priority,
            dueAt: current.dueAt,
            description: current.description
        )
    }

    @discardableResult
    public func update(
        _ id: TodoItem.ID,
        title: String,
        reminderAt: Date?,
        priority: Priority = .medium,
        dueAt: Date? = nil,
        description: String? = nil
    ) throws -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let oldReminderAt = items[index].reminderAt
        items[index].title = trimmed
        items[index].reminderAt = reminderAt
        items[index].priority = priority
        items[index].dueAt = dueAt
        items[index].description = description
        if oldReminderAt != reminderAt {
            items[index].reminderSentAt = nil
        }
        try save()
        return items[index]
    }

    public func delete(_ id: TodoItem.ID) throws {
        items.removeAll { $0.id == id }
        try save()
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
        items.sorted { $0.createdAt > $1.createdAt }
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
            return lhs.createdAt > rhs.createdAt
        case (nil, nil):
            return lhs.createdAt > rhs.createdAt
        case (nil, _):
            return false
        case (_, nil):
            return true
        }
    }
}
