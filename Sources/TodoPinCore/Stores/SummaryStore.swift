import Combine
import Foundation

public final class SummaryStore: ObservableObject {
    @Published public private(set) var summaries: [DailySummary]

    private let fileURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar

    public init(
        fileURL: URL,
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        initialSummaries: [DailySummary] = []
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.calendar = calendar
        self.summaries = initialSummaries.sorted { $0.dayStart < $1.dayStart }
    }

    public convenience init(fileManager: FileManager = .default, calendar: Calendar = .current) throws {
        try self.init(
            fileURL: StorageLocations.summariesURL(fileManager: fileManager),
            fileManager: fileManager,
            calendar: calendar
        )
        try load()
    }

    public func load() throws {
        do {
            summaries = try JSONFile.load([DailySummary].self, from: fileURL, fileManager: fileManager)
                .sorted { $0.dayStart < $1.dayStart }
        } catch CocoaError.fileNoSuchFile {
            summaries = []
        }
    }

    public func save() throws {
        try JSONFile.save(summaries, to: fileURL, fileManager: fileManager)
    }

    public func summary(for day: Date) -> DailySummary? {
        let dayStart = calendar.todoPinDayStart(for: day)
        return summaries.first { calendar.isDate($0.dayStart, inSameDayAs: dayStart) }
    }

    @discardableResult
    public func generateSummary(
        for day: Date,
        todos: [TodoItem],
        generatedAt: Date = Date()
    ) throws -> DailySummary {
        let summary = Self.makeSummary(for: day, todos: todos, generatedAt: generatedAt, calendar: calendar)
        summaries.removeAll { calendar.isDate($0.dayStart, inSameDayAs: summary.dayStart) }
        summaries.append(summary)
        summaries.sort { $0.dayStart < $1.dayStart }
        try save()
        return summary
    }

    public func generateMissingSummaries(upTo now: Date, todos: [TodoItem]) throws {
        let todayStart = calendar.todoPinDayStart(for: now)
        let candidateDays = Set(todos.flatMap { item -> [Date] in
            var days = [calendar.todoPinDayStart(for: item.createdAt)]
            if let completedAt = item.completedAt {
                days.append(calendar.todoPinDayStart(for: completedAt))
            }
            return days
        })

        for dayStart in candidateDays.sorted() where dayStart < todayStart {
            if summary(for: dayStart) == nil {
                try generateSummary(for: dayStart, todos: todos, generatedAt: now)
            }
        }
    }

    public static func makeSummary(
        for day: Date,
        todos: [TodoItem],
        generatedAt: Date,
        calendar: Calendar = .current
    ) -> DailySummary {
        let start = calendar.todoPinDayStart(for: day)
        let end = calendar.todoPinDayEnd(for: day)
        let added = todos.filter { $0.createdAt >= start && $0.createdAt <= end }
        let completed = todos.filter { item in
            guard let completedAt = item.completedAt else {
                return false
            }
            return completedAt >= start && completedAt <= end
        }
        let open = todos.filter { item in
            item.createdAt <= end && item.completedAt == nil
        }

        return DailySummary(
            dayStart: start,
            generatedAt: generatedAt,
            addedCount: added.count,
            completedCount: completed.count,
            carriedOpenCount: open.count,
            completedTitles: completed.map(\.title),
            openTitles: open.map(\.title)
        )
    }
}
