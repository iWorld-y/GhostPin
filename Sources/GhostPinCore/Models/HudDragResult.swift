import Foundation

/// HUD 拖动受限写入结果：拒绝时不提交任务文档，保存失败以错误抛出。
public enum HudDragResult: Equatable, Sendable {
    case moved(TodoItem)
    case unchanged
    case taskChanged
    case dueDateRestricted(TodoItem)
}