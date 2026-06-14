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
            items = try JSONFile.load([TodoItem].self, from: fileURL, fileManager: fileManager)
            items = Self.sortByCreatedAtDescending(items)
        } catch CocoaError.fileNoSuchFile {
            items = []
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
        reminderAt: Date? = nil
    ) throws -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let item = TodoItem(title: trimmed, createdAt: createdAt, source: source, reminderAt: reminderAt)
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
        try update(id, title: title, reminderAt: items.first { $0.id == id }?.reminderAt)
    }

    @discardableResult
    public func update(_ id: TodoItem.ID, title: String, reminderAt: Date?) throws -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = items.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        let oldReminderAt = items[index].reminderAt
        items[index].title = trimmed
        items[index].reminderAt = reminderAt
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

    public func openItems() -> [TodoItem] {
        Self.sortByCreatedAtDescending(items.filter { !$0.isCompleted })
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
}
