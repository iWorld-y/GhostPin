import AppKit
import SwiftUI

final class WindowCoordinator: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var quickAddWindow: NSWindow?
    private var voiceCaptureWindow: NSWindow?
    private var boardWindow: NSWindow?

    init(appState: AppState) {
        self.appState = appState
    }

    func showQuickAdd() {
        guard let appState else {
            return
        }

        if quickAddWindow == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "TodoPin"
            window.isReleasedWhenClosed = false
            window.delegate = self
            configureFloatingPanel(window, hidesStandardButtons: true)
            window.center()
            quickAddWindow = window
        }

        quickAddWindow?.contentView = NSHostingView(
            rootView: QuickAddPanelView(
                appState: appState,
                onClose: { [weak self] in
                    self?.quickAddWindow?.close()
                }
            )
        )
        updateBoardLevel()

        NSApp.activate(ignoringOtherApps: true)
        quickAddWindow?.makeKeyAndOrderFront(nil)
    }

    func showVoiceCapture() {
        guard let appState else {
            return
        }

        if voiceCaptureWindow?.isVisible == true {
            voiceCaptureWindow?.orderFrontRegardless()
            return
        }

        if voiceCaptureWindow == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 250, height: 210),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "TodoPin 语音录入"
            window.isReleasedWhenClosed = false
            window.delegate = self
            configureFloatingPanel(window, hidesStandardButtons: true)
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.center()
            voiceCaptureWindow = window
        }

        voiceCaptureWindow?.contentView = NSHostingView(
            rootView: VoiceCaptureOverlayView(
                appState: appState,
                onClose: { [weak self] in
                    self?.voiceCaptureWindow?.close()
                }
            )
        )
        updateBoardLevel()
        voiceCaptureWindow?.orderFrontRegardless()
    }

    func showBoard() {
        guard let appState else {
            return
        }

        if boardWindow == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "TodoPin 桌面便签"
            window.isReleasedWhenClosed = false
            window.delegate = self
            configureFloatingPanel(window, hidesStandardButtons: true)
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 300, height: 280)
            window.center()
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
        updateBoardLevel()
        boardWindow?.orderFrontRegardless()
    }

    func hideBoard() {
        boardWindow?.orderOut(nil)
    }

    func showSummary() {
        appState?.generateTodaySummary()
    }

    func updateBoardLevel() {
        quickAddWindow?.level = appState?.preferences.keepBoardOnTop == true ? .floating : .normal
        voiceCaptureWindow?.level = .floating
        boardWindow?.level = appState?.preferences.keepBoardOnTop == true ? .floating : .normal
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as AnyObject? === quickAddWindow {
            quickAddWindow?.contentView = nil
        } else if notification.object as AnyObject? === voiceCaptureWindow {
            voiceCaptureWindow?.contentView = nil
        } else if notification.object as AnyObject? === boardWindow {
            boardWindow?.contentView = nil
        }
    }

    private func configureFloatingPanel(_ window: NSPanel, hidesStandardButtons: Bool) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        guard hidesStandardButtons else {
            return
        }

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
