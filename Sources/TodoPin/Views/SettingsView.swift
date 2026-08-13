import AppKit
import SwiftUI
import TodoPinCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("HUD") {
                HStack {
                    Text("透明度")
                    Slider(value: hudOpacityBinding, in: 0.5...1.0)
                }

                Picker("显示范围", selection: hudScopeBinding) {
                    Text("全部未完成").tag(HudScope.all)
                    Text("今天新增").tag(HudScope.today)
                }

                Stepper(value: hudMaxItemsBinding, in: 1...20) {
                    Text("最多显示 \(appState.preferences.hudMaxItems) 条")
                }

                Toggle("跨 Space 显示", isOn: hudAllSpacesBinding)
                Toggle("HUD 置顶", isOn: keepBoardOnTopBinding)
            }

            Section("通用") {
                Toggle("登录时启动", isOn: launchAtLoginBinding)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var keepBoardOnTopBinding: Binding<Bool> {
        Binding(
            get: { appState.preferences.keepBoardOnTop },
            set: {
                appState.preferences.keepBoardOnTop = $0
                appState.updateBoardLevel()
            }
        )
    }

    private var hudOpacityBinding: Binding<Double> {
        Binding(
            get: { appState.preferences.hudOpacity },
            set: {
                appState.preferences.hudOpacity = $0
                appState.updateHUD()
            }
        )
    }

    private var hudScopeBinding: Binding<HudScope> {
        Binding(
            get: { appState.preferences.hudScope },
            set: { appState.preferences.hudScope = $0 }
        )
    }

    private var hudMaxItemsBinding: Binding<Int> {
        Binding(
            get: { appState.preferences.hudMaxItems },
            set: { appState.preferences.hudMaxItems = $0 }
        )
    }

    private var hudAllSpacesBinding: Binding<Bool> {
        Binding(
            get: { appState.preferences.hudAllSpaces },
            set: {
                appState.preferences.hudAllSpaces = $0
                appState.updateHUD()
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.preferences.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
        )
    }
}
