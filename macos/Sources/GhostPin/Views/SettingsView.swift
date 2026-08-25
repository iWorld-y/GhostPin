import AppKit
import SwiftUI
import GhostPinCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @StateObject private var recorder: HotKeyRecorder

    init(appState: AppState) {
        self.appState = appState
        _recorder = StateObject(wrappedValue: HotKeyRecorder(appState: appState))
    }

    var body: some View {
        TabView {
            hudTab
                .tabItem { Label("HUD", systemImage: "rectangle.on.rectangle") }
            advancedTab
                .tabItem { Label("高级", systemImage: "keyboard") }
        }
    }

    private var hudTab: some View {
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

    private var advancedTab: some View {
        Form {
            Section("交互模式快捷键") {
                Toggle("启用全局快捷键", isOn: hotKeyEnabledBinding)

                HStack {
                    Button {
                        recorder.start()
                    } label: {
                        LabeledContent("当前快捷键") {
                            if let shortcut = appState.preferences.hudModeHotKeyShortcut {
                                Text(shortcut.displayName).monospaced()
                            } else {
                                Text("未设置").foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!hotKeyToggleOn || recorder.isRecording)

                    if appState.preferences.hudModeHotKeyShortcut != nil, !recorder.isRecording {
                        Button {
                            appState.clearHudModeHotKeyShortcut()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("清除快捷键")
                    }
                }

                if recorder.isRecording {
                    Label("请按下快捷键组合，Esc 取消", systemImage: "record.circle")
                }

                hotKeyStatusView
            }
        }
        .formStyle(.grouped)
        .padding()
        .onDisappear {
            recorder.stop()
        }
    }

    @ViewBuilder
    private var hotKeyStatusView: some View {
        if let message = recorder.validationMessage {
            Text(message).foregroundStyle(.red).font(.callout)
        }
        if let notice = appState.hotKeyNotice {
            Text(notice).foregroundStyle(.orange).font(.callout)
        }
        switch appState.hotKeySetupState {
        case .disabled:
            if appState.preferences.hudModeHotKeyShortcut != nil {
                Text("开关已关闭，快捷键停止响应，配置已保留。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        case .pendingConfiguration:
            Text("开关已打开，请录制快捷键；录制成功并注册后才会保存与生效。")
                .foregroundStyle(.orange)
                .font(.callout)
        case .registered:
            Text("GhostPin 已注册该快捷键。第三方软件的冲突无法完全自动检测，若同时响应请在其他软件中调整。")
                .foregroundStyle(.secondary)
                .font(.callout)
        case .failure(let message):
            Text(message).foregroundStyle(.red).font(.callout)
        }
    }

    private var hotKeyToggleOn: Bool {
        switch appState.hotKeySetupState {
        case .pendingConfiguration, .registered:
            return true
        case .disabled:
            return false
        case .failure:
            return appState.preferences.hudModeHotKeyEnabled
        }
    }

    private var hotKeyEnabledBinding: Binding<Bool> {
        Binding(
            get: { hotKeyToggleOn },
            set: { appState.setHudModeHotKeyEnabled($0) }
        )
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

@MainActor
private final class HotKeyRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var validationMessage: String?

    private let appState: AppState
    private var monitor: Any?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        guard !isRecording else {
            return
        }
        appState.beginHotKeyRecording()
        validationMessage = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stop() {
        guard isRecording else {
            return
        }
        finishRecording()
        appState.cancelHotKeyRecording()
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            stop()
            return
        }
        guard !Self.modifierOnlyKeyCodes.contains(event.keyCode) else {
            return
        }
        let modifiers = HotKeyShortcut.carbonModifiers(from: event.modifierFlags)
        guard let candidate = HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            validationMessage = "不符合规则：请包含 Command、Option、Control 或 Shift 修饰键，或使用 F1–F20 功能键。"
            return
        }
        finishRecording()
        appState.submitHotKeyCandidate(candidate)
    }

    private func finishRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        validationMessage = nil
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = Set((54...63).map(UInt16.init))
}
