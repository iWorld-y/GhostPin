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
    /// 列表基准高度（用户/内容选定，不含交互临时增高）；仅用户真实调高或内容适配时更新。
    private var listBaseHeight: CGFloat?

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
            listBaseHeight = appState.preferences.hudFrame?.height
            let interactive = appState.preferences.hudMode == .interactive
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
            window.minSize = minimumSize(for: view, interactive: interactive)
            if let savedFrame {
                var rect = savedFrame.nsRect
                if view == .list {
                    // 交互列表遇到旧的紧凑尺寸时，先按交互最小值算出目标高度再夹取。
                    rect.size.height = HudFrameGeometry.listHeight(
                        baseHeight: rect.height,
                        interactive: interactive,
                        interactiveMinimum: DesktopNotesBoardView.interactiveMinimumSize.height,
                        passthroughMinimum: DesktopNotesBoardView.minimumSize.height
                    )
                }
                window.setFrame(
                    HudFrameGeometry.restoredFrame(rect, screens: Self.hudScreens(), main: Self.mainHudScreen()),
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
        listBaseHeight = height
        var frame = boardWindow.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        isSwitchingLayout = true
        boardWindow.setFrame(frame, display: true)
        isSwitchingLayout = false
        saveBoardFrame()
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
        var size = saved.map { NSSize(width: $0.width, height: $0.height) } ?? defaultSize(for: target)
        if target == .list {
            size.height = HudFrameGeometry.listHeight(
                baseHeight: size.height,
                interactive: appState.preferences.hudMode == .interactive,
                interactiveMinimum: DesktopNotesBoardView.interactiveMinimumSize.height,
                passthroughMinimum: DesktopNotesBoardView.minimumSize.height
            )
        }
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

    /// 同一布局内模式变化（穿透列表↔交互列表）：目标高度取持久化列表基准高度与模式最小值的较大者，
    /// 交互保证工具栏/空状态高度，穿透还原紧凑高度；用户主动调高的尺寸保留。
    /// 调整保留左上角并夹取进当前屏可用区，不写回偏好。
    private func applyHudModeMetrics() {
        guard let appState, let boardWindow, currentLayout == .list else {
            return
        }
        let interactive = appState.preferences.hudMode == .interactive
        let required = minimumSize(for: .list, interactive: interactive)
        let baseHeight = listBaseHeight ?? boardWindow.frame.height
        let target = HudFrameGeometry.listModeFrame(
            current: boardWindow.frame,
            baseHeight: baseHeight,
            interactive: interactive,
            interactiveMinimum: DesktopNotesBoardView.interactiveMinimumSize.height,
            passthroughMinimum: DesktopNotesBoardView.minimumSize.height,
            screens: Self.hudScreens(),
            main: Self.mainHudScreen()
        )
        guard boardWindow.minSize != required || boardWindow.frame != target else {
            return
        }
        isSwitchingLayout = true
        boardWindow.minSize = required
        if boardWindow.frame != target {
            boardWindow.setFrame(target, display: true)
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
        guard !isSwitchingLayout, let appState, let boardWindow else { return }
        if currentLayout == .list {
            // 仅当高度偏离当前显示高度时才视为用户真实调高；仅调宽/程序化显示保留基准。
            listBaseHeight = HudFrameGeometry.updatedListBaseHeight(
                actualHeight: boardWindow.frame.height,
                currentBaseHeight: listBaseHeight ?? boardWindow.frame.height,
                interactive: appState.preferences.hudMode == .interactive,
                interactiveMinimum: DesktopNotesBoardView.interactiveMinimumSize.height,
                passthroughMinimum: DesktopNotesBoardView.minimumSize.height
            )
        }
        saveBoardFrame()
    }

    /// 缩放与移动回调按当前视图保存：四象限存完整 frame；列表位置/宽度取实际值，
    /// 高度始终存基准高度，避免把交互临时增高、仅移动/仅调宽写回基准。
    private func saveBoardFrame() {
        guard let boardWindow, let appState else {
            return
        }
        let frame = boardWindow.frame
        if currentLayout == .quadrants {
            appState.preferences.hudQuadrantsFrame = HudWindowFrame(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            )
        } else {
            let persisted = HudFrameGeometry.persistedListFrame(actual: frame, baseHeight: listBaseHeight ?? frame.height)
            appState.preferences.hudFrame = HudWindowFrame(
                x: persisted.minX,
                y: persisted.minY,
                width: persisted.width,
                height: persisted.height
            )
        }
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
