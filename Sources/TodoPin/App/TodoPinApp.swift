import AppKit
import SwiftUI
import TodoPinCore

@main
struct TodoPinApp: App {
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
            let openCount = appState.todoStore.openItems().count
            HStack(spacing: 5) {
                TodoPinLogoMark(size: 16)
                Text(openCount == 0 ? "TodoPin" : "\(openCount)")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
                .frame(width: 420)
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
