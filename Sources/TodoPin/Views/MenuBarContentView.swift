import AppKit
import SwiftUI
import TodoPinCore

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button {
            appState.toggleBoard()
        } label: {
            Label(appState.isBoardVisible ? "隐藏桌面便签" : "显示桌面便签", systemImage: "note.text")
        }

        Toggle("交互模式", isOn: hudModeBinding)

        Divider()

        SettingsLink {
            Label("设置…", systemImage: "gearshape")
        }

        Divider()

        Button("退出 TodoPin") {
            NSApp.terminate(nil)
        }
    }

    private var hudModeBinding: Binding<Bool> {
        Binding(
            get: { appState.preferences.hudMode == .interactive },
            set: { isOn in
                if isOn != (appState.preferences.hudMode == .interactive) {
                    appState.toggleHUDMode()
                }
            }
        )
    }
}
