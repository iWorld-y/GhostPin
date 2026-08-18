import AppKit
import SwiftUI
import GhostPinCore

@main
struct GhostPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        AppDelegate.appState = state
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            HStack(spacing: 3) {
                if let statusBar = GhostPinAssets.statusBar {
                    Image(nsImage: statusBar)
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .fixedSize()
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                }
                let openCount = appState.todoStore.openItems().count
                if openCount > 0 {
                    Text("\(openCount)")
                }
            }
            .fixedSize()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(appState: appState)
                .frame(width: 420)
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.appState?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.appState?.stop()
    }
}
