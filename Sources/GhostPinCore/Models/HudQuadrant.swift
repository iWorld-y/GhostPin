import Foundation

/// 已逾期或本地今天到期的任务在展示时视为紧急。
public enum HudQuadrant: String, CaseIterable, Sendable {
    case importantUrgent
    case importantNotUrgent
    case generalUrgent
    case generalNotUrgent

    public var isImportantRow: Bool {
        self == .importantUrgent || self == .importantNotUrgent
    }

    public var isUrgentColumn: Bool {
        self == .importantUrgent || self == .generalUrgent
    }

    public var sortRank: Int {
        switch self {
        case .importantUrgent: return 1
        case .importantNotUrgent: return 2
        case .generalUrgent: return 3
        case .generalNotUrgent: return 4
        }
    }

    public static func classify(important: Bool, urgent: Bool, dueAt: Date?, nextDayStart: Date) -> HudQuadrant {
        let effectiveUrgent = urgent || (dueAt.map { $0 < nextDayStart } ?? false)
        switch (important, effectiveUrgent) {
        case (true, true):
            return .importantUrgent
        case (true, false):
            return .importantNotUrgent
        case (false, true):
            return .generalUrgent
        case (false, false):
            return .generalNotUrgent
        }
    }
}

/// 单个象限的渲染集合：Doing 排在 Todo 前面，同状态沿用列表排序。
public struct HudQuadrantCell: Equatable, Sendable {
    public let quadrant: HudQuadrant
    public let doing: [TodoItem]
    public let todo: [TodoItem]

    public init(quadrant: HudQuadrant, doing: [TodoItem], todo: [TodoItem]) {
        self.quadrant = quadrant
        self.doing = doing
        self.todo = todo
    }

    public var count: Int {
        doing.count + todo.count
    }
}

/// 四象限投影：显示范围内全部未完成任务，不应用条数上限与 Doing 聚焦。
public struct HudQuadrantProjection: Equatable, Sendable {
    public let cells: [HudQuadrantCell]
    public let doingCount: Int
    public let todoCount: Int

    public init(cells: [HudQuadrantCell], doingCount: Int, todoCount: Int) {
        self.cells = cells
        self.doingCount = doingCount
        self.todoCount = todoCount
    }

    public func cell(_ quadrant: HudQuadrant) -> HudQuadrantCell {
        cells.first { $0.quadrant == quadrant } ?? HudQuadrantCell(quadrant: quadrant, doing: [], todo: [])
    }
}