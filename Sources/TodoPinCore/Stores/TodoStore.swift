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
        source: TodoSource,
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
            source: source,
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

    public func setCompleted(_ id: TodoItem.ID, completed: Bool, at date: Date = Date()) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].completedAt = completed ? date : nil
        try save()
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
        let open = openItems(now: now)
        let scoped: [TodoItem]
        switch scope {
        case .all:
            scoped = open
        case .today:
            let dayStart = calendar.todoPinDayStart(for: now)
            scoped = open.filter { $0.createdAt >= dayStart }
        }
        return Array(scoped.prefix(max(maxCount, 0)))
    }

    public func completedItems(on date: Date, calendar: Calendar = .current) -> [TodoItem] {
        let start = calendar.todoPinDayStart(for: date)
        let end = calendar.todoPinDayEnd(for: date)
        return items.filter { item in
            guard let completedAt = item.completedAt else {
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
