import Foundation

public struct DailySummary: Identifiable, Codable, Equatable, Sendable {
    public var id: Date { dayStart }
    public let dayStart: Date
    public let generatedAt: Date
    public let addedCount: Int
    public let completedCount: Int
    public let carriedOpenCount: Int
    public let completedTitles: [String]
    public let openTitles: [String]

    public init(
        dayStart: Date,
        generatedAt: Date,
        addedCount: Int,
        completedCount: Int,
        carriedOpenCount: Int,
        completedTitles: [String],
        openTitles: [String]
    ) {
        self.dayStart = dayStart
        self.generatedAt = generatedAt
        self.addedCount = addedCount
        self.completedCount = completedCount
        self.carriedOpenCount = carriedOpenCount
        self.completedTitles = completedTitles
        self.openTitles = openTitles
    }
}
