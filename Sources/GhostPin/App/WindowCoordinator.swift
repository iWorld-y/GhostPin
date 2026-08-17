import AppKit
import SwiftUI

final class WindowCoordinator: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var boardWindow: NSWindow?

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
            let window = HUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
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
            window.minSize = NSSize(width: 300, height: 280)
            if let savedFrame = appState.preferences.hudFrame {
                window.setFrame(savedFrame.nsRect, display: false)
                if !Self.frameIntersectsAnyScreen(savedFrame.nsRect) {
                    window.center()
                }
            } else {
                window.center()
            }
            boardWindow = window
        }

        boardWindow?.contentView = NSHostingView(
            rootView: DesktopNotesBoardView(
                appState: appState,
                onClose: { [weak self] in
                    self?.hideBoard()
                }
            )
        )
        updateHUD()
        boardWindow?.orderFrontRegardless()
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
        let interactive = appState.preferences.hudMode == .interactive
        boardWindow.ignoresMouseEvents = !interactive
        boardWindow.alphaValue = CGFloat(appState.preferences.hudOpacity)
        boardWindow.collectionBehavior = appState.preferences.hudAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : []
        boardWindow.level = appState.preferences.keepBoardOnTop == true ? .floating : .normal
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
        saveBoardFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveBoardFrame()
    }

    private func saveBoardFrame() {
        guard let boardWindow, let appState else {
            return
        }
        let frame = boardWindow.frame
        appState.preferences.hudFrame = HudWindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
    }

    private static func frameIntersectsAnyScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.frame.intersects(frame) }
    }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
