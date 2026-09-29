import Foundation

/// HUD 任务投影结果：按状态分区后的实际渲染集合与各自的完整计数。
///
/// `doing` / `todo` 是 HUD 真正渲染的卡片；`doingCount` / `todoCount`
/// 是应用显示范围与条数上限之前的计数，供头部展示，因此隐藏分区时
/// 计数依然可用。
public struct HudProjection: Equatable, Sendable {
    public let doing: [TodoItem]
    public let todo: [TodoItem]
    public let doingCount: Int
    public let todoCount: Int

    public init(doing: [TodoItem], todo: [TodoItem], doingCount: Int, todoCount: Int) {
        self.doing = doing
        self.todo = todo
        self.doingCount = doingCount
        self.todoCount = todoCount
    }
}
