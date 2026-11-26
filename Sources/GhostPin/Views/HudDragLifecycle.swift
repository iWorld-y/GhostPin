import CoreGraphics
import Foundation
import GhostPinCore

/// 拖动判定所需的即时环境：模式、视图、范围与取消代次。
struct HudDragContext: Equatable {
    let isInteractive: Bool
    let view: HudView
    let scope: HudScope
    let cancelToken: Int
}

/// 一次物理手势的拖动会话，记录开始时的分类与环境快照。
struct TaskDragSession {
    let item: TodoItem
    let startQuadrant: HudQuadrant
    let startStatus: TodoStatus
    let startContext: HudDragContext
    var location: CGPoint

    /// 移动与投放共用：环境仍与开始时一致才有效。
    func isValid(in context: HudDragContext) -> Bool {
        context.isInteractive
            && context.view == startContext.view
            && context.scope == startContext.scope
            && context.cancelToken == startContext.cancelToken
    }
}

/// 手柄上报的物理手势事件。
enum HudDragGestureEvent {
    case began
    case moved(CGPoint)
    case ended(CGPoint)
    /// GestureState 复位：手势正常结束或被系统取消，不依赖 onEnded。
    case gestureReset
    /// 源手柄随视图移除（外部更新、滚动或模式切换）。
    case sourceDisappeared
}

/// HUD 拖动的物理手势生命周期。视图回调与隔离自测共用同一判定。
struct HudDragLifecycle {
    private(set) var session: TaskDragSession?
    /// 已取消但尚未结束的手势来源；同一手势的后续 change/up 一律忽略。
    private(set) var cancelledItemID: TodoItem.ID?

    /// 新手势开始：解除上一次取消的封锁。
    mutating func begin() {
        cancelledItemID = nil
    }

    /// 手势移动：会话失效立即取消；被封锁的手势不得重建会话。
    mutating func move(_ item: TodoItem, quadrant: HudQuadrant, to location: CGPoint, context: HudDragContext) {
        guard cancelledItemID != item.id else { return }
        if let session {
            guard session.isValid(in: context) else {
                cancel()
                return
            }
            if session.item.id == item.id {
                self.session?.location = location
            }
            return
        }
        guard context.isInteractive else { return }
        session = TaskDragSession(
            item: item,
            startQuadrant: quadrant,
            startStatus: item.status,
            startContext: context,
            location: location
        )
    }

    /// 松手：结束物理手势，返回可投放的会话；已取消或环境失效时返回 nil。
    mutating func end(_ item: TodoItem, at location: CGPoint, context: HudDragContext) -> TaskDragSession? {
        if cancelledItemID == item.id {
            cancelledItemID = nil
        }
        guard let session, session.item.id == item.id else { return nil }
        self.session = nil
        guard session.isValid(in: context) else { return nil }
        var ended = session
        ended.location = location
        return ended
    }

    /// 模式、视图、范围或取消代次变化：作废会话并封锁同一手势。
    mutating func cancel() {
        if let session {
            cancelledItemID = session.item.id
        }
        session = nil
    }

    /// 源手柄消失：清理预览与落点，封锁可能残留的旧回调。
    mutating func cancelSource(_ itemID: TodoItem.ID) {
        guard session?.item.id == itemID else { return }
        cancel()
    }

    /// 手势结束或系统取消：解除封锁，清理未经松手投放的残留会话。
    mutating func gestureFinished(_ itemID: TodoItem.ID) {
        if cancelledItemID == itemID {
            cancelledItemID = nil
        }
        if session?.item.id == itemID {
            session = nil
        }
    }
}
