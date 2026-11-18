import AppKit
import OSLog
import SwiftUI

private let hudLogger = Logger(subsystem: "com.oyuxi.TodoPin", category: "HUD")

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var boardWindow: NSWindow?
    private var isPointerInsideHUD = false
    private var needsInitialHUDHeight = false
    private var currentLayout: HudView = .list
    private var isSwitchingLayout = false

    var isBoardVisible: Bool {
        boardWindow?.isVisible == true
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func showBoard() {
        guard let appState else {
            return
        }

        if boardWindow == nil {
            let view = appState.preferences.effectiveHudView
            currentLayout = view
            let savedFrame = framePreference(for: view)
            let defaultSize = view == .quadrants
                ? DesktopNotesBoardView.quadrantsDefaultSize
                : NSSize(width: DesktopNotesBoardView.defaultWidth, height: 460)
            let window = HUDPanel(
                contentRect: NSRect(origin: .zero, size: defaultSize),
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.minSize = minimumSize(for: view)
            if let savedFrame {
                window.setFrame(savedFrame.nsRect, display: false)
                if !Self.frameIntersectsAnyScreen(savedFrame.nsRect) {
                    window.center()
                }
            } else {
                window.center()
            }
            boardWindow = window
            needsInitialHUDHeight = view == .list && savedFrame == nil
            hudLogger.info("showBoard view=\(view.rawValue, privacy: .public) frame=\(NSStringFromRect(window.frame), privacy: .public)")
        }

        boardWindow?.contentView = NSHostingView(
            rootView: DesktopNotesBoardView(
                appState: appState,
                onClose: { [weak self] in
                    self?.hideBoard()
                },
                onPreferredHeightChange: { [weak self] height in
                    self?.applyInitialHUDHeight(height)
                }
            )
        )
        updateHUD()
        boardWindow?.orderFrontRegardless()
    }

    /// 首次展示且未保存尺寸时采用内容高度，之后由用户调整并持久化窗口尺寸。
    private func applyInitialHUDHeight(_ height: CGFloat) {
        guard needsInitialHUDHeight, currentLayout == .list, let boardWindow else {
            return
        }
        needsInitialHUDHeight = false
        let height = max(height, DesktopNotesBoardView.minimumSize.height)
        var frame = boardWindow.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        boardWindow.setFrame(frame, display: true)
    }

    func hideBoard() {
        boardWindow?.orderOut(nil)
    }

    func toggleBoard() {
        if isBoardVisible {
            hideBoard()
        } else {
            showBoard()
        }
    }

    func updateHUD() {
        guard let appState, let boardWindow else {
            return
        }
        applyHudLayout()
        let interactive = appState.preferences.hudMode == .interactive
        boardWindow.ignoresMouseEvents = !interactive
        isPointerInsideHUD = boardWindow.frame.contains(NSEvent.mouseLocation)
        boardWindow.alphaValue = targetHUDAlpha()
        boardWindow.collectionBehavior = appState.preferences.hudAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : []
        boardWindow.level = appState.preferences.keepBoardOnTop == true ? .floating : .normal
    }

    /// 记录指针是否位于 HUD 内。是否隐身始终由「模式 + 该事实」推导，不保留跨模式的中间状态。
    func setPointerInsideHUD(_ inside: Bool) {
        guard inside != isPointerInsideHUD else {
            return
        }
        isPointerInsideHUD = inside
        applyHUDAlpha()
    }

    /// 按生效视图切换窗口尺寸：列表与四象限分别恢复已保存尺寸，
    /// 首次展开固定左上角并限制在当前屏幕可用区域。
    private func applyHudLayout() {
        guard let appState, let boardWindow else {
            return
        }
        let target = appState.preferences.effectiveHudView
        guard target != currentLayout else {
            return
        }
        saveBoardFrame()
        currentLayout = target
        needsInitialHUDHeight = false
        boardWindow.minSize = minimumSize(for: target)

        let oldFrame = boardWindow.frame
        var frame: NSRect
        if let saved = framePreference(for: target), Self.frameIntersectsAnyScreen(saved.nsRect) {
            frame = saved.nsRect
        } else {
            let size = target == .quadrants
                ? DesktopNotesBoardView.quadrantsDefaultSize
                : NSSize(width: DesktopNotesBoardView.defaultWidth, height: 460)
            frame = NSRect(x: oldFrame.minX, y: oldFrame.maxY - size.height, width: size.width, height: size.height)
            needsInitialHUDHeight = target == .list
        }
        frame = Self.clampedFrame(frame)
        isSwitchingLayout = true
        boardWindow.setFrame(frame, display: true)
        isSwitchingLayout = false
        saveBoardFrame()
        hudLogger.info("layout view=\(target.rawValue, privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public)")
    }

    private func framePreference(for view: HudView) -> HudWindowFrame? {
        guard let appState else {
            return nil
        }
        return view == .quadrants ? appState.preferences.hudQuadrantsFrame : appState.preferences.hudFrame
    }

    private func minimumSize(for view: HudView) -> NSSize {
        view == .quadrants ? DesktopNotesBoardView.quadrantsMinimumSize : DesktopNotesBoardView.minimumSize
    }

    private static func clampedFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            return frame
        }
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

    /// 目标不透明度：穿透模式下指针位于 HUD 内即完全不可见，其余情况用偏好值。
    private func targetHUDAlpha() -> CGFloat {
        guard let appState else {
            return 1
        }
        let ghosted = appState.preferences.hudMode == .passthrough && isPointerInsideHUD
        guard !ghosted else {
            return 0
        }
        let opacity = appState.preferences.hudMode == .passthrough
            ? appState.preferences.hudPassthroughOpacity
            : appState.preferences.hudInteractiveOpacity
        return CGFloat(opacity)
    }

    private func applyHUDAlpha() {
        guard let boardWindow else {
            return
        }
        let target = targetHUDAlpha()
        guard boardWindow.alphaValue != target else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            boardWindow.animator().alphaValue = target
        }
    }

    func applyHUDInteraction() {
        guard let appState, let boardWindow else {
            return
        }
        if appState.preferences.hudMode == .interactive {
            NSApp.activate(ignoringOtherApps: true)
            boardWindow.makeKeyAndOrderFront(nil)
        } else {
            boardWindow.resignKey()
            NSApp.deactivate()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as AnyObject? === boardWindow {
            boardWindow?.contentView = nil
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isSwitchingLayout else { return }
        saveBoardFrame()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isSwitchingLayout else { return }
        saveBoardFrame()
    }

    /// 缩放与移动回调按当前视图保存尺寸，避免把四象限尺寸写入列表偏好。
    private func saveBoardFrame() {
        guard let boardWindow, let appState else {
            return
        }
        let frame = boardWindow.frame
        let saved = HudWindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
        if currentLayout == .quadrants {
            appState.preferences.hudQuadrantsFrame = saved
        } else {
            appState.preferences.hudFrame = saved
        }
    }

    private static func frameIntersectsAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(frame) }
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
