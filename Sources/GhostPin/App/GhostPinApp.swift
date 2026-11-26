import AppKit
import SwiftUI
import GhostPinCore

@main
struct GhostPinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        #if DEBUG
        // 自测必须在创建 AppState 前具备有效隔离根，否则会构造真实偏好并覆盖真实窗口设置。
        if ProcessInfo.processInfo.environment["GHOSTPIN_WINDOW_SELFTEST"] != nil,
           !AppPreferences.isIsolatedVerification {
            FileHandle.standardError.write(Data("GHOSTPIN_WINDOW_SELFTEST 需要 GHOSTPIN_TEST_SUPPORT_ROOT 隔离根\n".utf8))
            exit(2)
        }
        if ProcessInfo.processInfo.environment["GHOSTPIN_DRAG_SELFTEST"] != nil,
           !AppPreferences.isIsolatedVerification {
            FileHandle.standardError.write(Data("GHOSTPIN_DRAG_SELFTEST 需要 GHOSTPIN_TEST_SUPPORT_ROOT 隔离根\n".utf8))
            exit(2)
        }
        #endif
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if ProcessInfo.processInfo.environment["GHOSTPIN_WINDOW_SELFTEST"] != nil {
            let ok = Self.appState?.windowCoordinator.runGeometrySelfTest() ?? false
            exit(ok ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["GHOSTPIN_DRAG_SELFTEST"] != nil {
            let ok = Self.appState?.runDragSelfTest() ?? false
            exit(ok ? 0 : 1)
        }
        #endif
        Self.appState?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.appState?.stop()
    }
}
