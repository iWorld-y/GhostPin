import Foundation

/// 四象限分类：高优先级为重要，中、低优先级为一般；
/// 已逾期或本地今天到期为紧急，其余（含无截止日期）为不紧急。
public enum HudQuadrant: String, CaseIterable, Sendable {
    case importantUrgent
    case importantNotUrgent
    case generalUrgent
    case generalNotUrgent

    public static func classify(priority: Priority, dueAt: Date?, nextDayStart: Date) -> HudQuadrant {
        let important = priority == .high
        let urgent = dueAt.map { $0 < nextDayStart } ?? false
        switch (important, urgent) {
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