import AppKit
import OSLog
import SwiftUI
import GhostPinCore

#if DEBUG
private let hudLogger = Logger(subsystem: "com.oyuxi.TodoPin", category: "HUD")
#endif

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
            window.minSize = minimumSize(for: view, interactive: appState.preferences.hudMode == .interactive)
            if let savedFrame {
                window.setFrame(
                    HudFrameGeometry.restoredFrame(savedFrame.nsRect, screens: Self.hudScreens(), main: Self.mainHudScreen()),
                    display: false
                )
            } else {
                window.center()
            }
            boardWindow = window
            needsInitialHUDHeight = view == .list && savedFrame == nil
            #if DEBUG
            hudLogger.info("showBoard view=\(view.rawValue, privacy: .public) frame=\(NSStringFromRect(window.frame), privacy: .public)")
            #endif
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
        guard needsInitialHUDHeight, currentLayout == .list, let appState, let boardWindow else {
            return
        }
        needsInitialHUDHeight = false
        let minHeight = minimumSize(for: .list, interactive: appState.preferences.hudMode == .interactive).height
        let height = max(height, minHeight)
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
        applyHudModeMetrics()
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

    /// 按生效视图切换窗口尺寸：保留当前左上角，目标布局仅取已保存尺寸（缺省用默认值），
    /// 在当前屏可用区内夹取，避免跳回旧位置或旧显示器。
    private func applyHudLayout() {
        guard let appState, let boardWindow else {
            return
        }
        let target = appState.preferences.effectiveHudView
        guard target != currentLayout else {
            return
        }
        saveBoardFrame()
        let oldFrame = boardWindow.frame
        currentLayout = target
        needsInitialHUDHeight = false

        let saved = framePreference(for: target)
        let size = saved.map { NSSize(width: $0.width, height: $0.height) } ?? defaultSize(for: target)
        let frame = HudFrameGeometry.switchedFrame(
            current: oldFrame,
            targetSize: size,
            screens: Self.hudScreens(),
            main: Self.mainHudScreen()
        )
        needsInitialHUDHeight = target == .list && saved == nil

        // minSize 变化可能触发 resize，与 setFrame 一起纳入切换保护。
        isSwitchingLayout = true
        boardWindow.minSize = minimumSize(for: target, interactive: appState.preferences.hudMode == .interactive)
        boardWindow.setFrame(frame, display: true)
        isSwitchingLayout = false
        saveBoardFrame()
        #if DEBUG
        hudLogger.info("layout view=\(target.rawValue, privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public)")
        #endif
    }

    /// 同一布局内模式变化（如穿透列表→交互列表）：保证交互工具栏与空状态有足够高度，
    /// 不足时保留左上角增高；该增高不写回偏好，穿透仍恢复紧凑列表尺寸。
    private func applyHudModeMetrics() {
        guard let appState, let boardWindow else {
            return
        }
        let interactive = appState.preferences.hudMode == .interactive
        let required = minimumSize(for: currentLayout, interactive: interactive)
        guard boardWindow.minSize != required else {
            return
        }
        isSwitchingLayout = true
        boardWindow.minSize = required
        var frame = boardWindow.frame
        if frame.height < required.height || frame.width < required.width {
            let newHeight = max(frame.height, required.height)
            frame.origin.y += frame.height - newHeight
            frame.size.height = newHeight
            frame.size.width = max(frame.width, required.width)
            boardWindow.setFrame(frame, display: true)
        }
        isSwitchingLayout = false
    }

    private func framePreference(for view: HudView) -> HudWindowFrame? {
        guard let appState else {
            return nil
        }
        return view == .quadrants ? appState.preferences.hudQuadrantsFrame : appState.preferences.hudFrame
    }

    private func defaultSize(for view: HudView) -> NSSize {
        view == .quadrants
            ? DesktopNotesBoardView.quadrantsDefaultSize
            : NSSize(width: DesktopNotesBoardView.defaultWidth, height: 460)
    }

    private func minimumSize(for view: HudView, interactive: Bool) -> NSSize {
        if view == .quadrants {
            return DesktopNotesBoardView.quadrantsMinimumSize
        }
        return interactive ? DesktopNotesBoardView.interactiveMinimumSize : DesktopNotesBoardView.minimumSize
    }

    private static func hudScreens() -> [HudScreen] {
        NSScreen.screens.map { HudScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }

    private static func mainHudScreen() -> HudScreen? {
        NSScreen.main.map { HudScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
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
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
