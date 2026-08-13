import AppKit
import Carbon
import SwiftUI
import TodoPinCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var recordingShortcutTarget: ShortcutTarget?
    @State private var shortcutMonitor: Any?
    @State private var shortcutMessage: String?

    var body: some View {
        Form {
            Section("录入") {
                shortcutRow(
                    title: "文本录入快捷键",
                    shortcut: appState.preferences.textHotKeyShortcut,
                    target: .text
                )

                if let shortcutMessage {
                    Text(shortcutMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("文本快捷键打开输入窗，自动解析中文提醒时间。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("提醒") {
                Text("未完成待办会在创建满 1 小时后提醒，此后每小时提醒一次，直到标记完成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("HUD") {
                shortcutRow(
                    title: "模式切换快捷键",
                    shortcut: appState.preferences.hudModeHotKeyShortcut,
                    target: .hudMode
                )

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
        .onChange(of: recordingShortcutTarget) { _, target in
            updateShortcutMonitor(target: target)
        }
        .onDisappear {
            removeShortcutMonitor()
        }
    }

    private func shortcutRow(title: String, shortcut: HotKeyShortcut, target: ShortcutTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut.displayName)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(recordingShortcutTarget == target ? "按下新的快捷键" : "录制快捷键") {
                    recordingShortcutTarget = recordingShortcutTarget == target ? nil : target
                }
                .buttonStyle(.bordered)
                .tint(recordingShortcutTarget == target ? Color.accentColor : nil)

                Menu("预设") {
                    ForEach(HotKeyShortcut.presets) { preset in
                        Button(preset.displayName) {
                            applyShortcut(preset, to: target)
                        }
                    }
                }
            }
            .controlSize(.small)
        }
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

    private func updateShortcutMonitor(target: ShortcutTarget?) {
        removeShortcutMonitor()
        guard let target else {
            return
        }

        shortcutMessage = nil
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                recordingShortcutTarget = nil
                return nil
            }

            guard let shortcut = makeShortcut(from: event) else {
                shortcutMessage = "请使用组合键，或按 F1-F20。"
                recordingShortcutTarget = nil
                return nil
            }

            applyShortcut(shortcut, to: target)
            recordingShortcutTarget = nil
            return nil
        }
    }

    private func removeShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }

    private func applyShortcut(_ shortcut: HotKeyShortcut, to target: ShortcutTarget) {
        switch target {
        case .text:
            appState.updateTextHotKey(shortcut)
        case .hudMode:
            guard shortcut != appState.preferences.textHotKeyShortcut else {
                shortcutMessage = "HUD 模式切换不能与文本录入使用同一个快捷键。"
                return
            }
            appState.updateHUDModeHotKey(shortcut)
        }
        shortcutMessage = nil
    }

    private func makeShortcut(from event: NSEvent) -> HotKeyShortcut? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 || Self.functionKeyCodes.contains(event.keyCode) else {
            return nil
        }

        let keyName = Self.keyName(for: event)
        let displayName = Self.displayName(
            keyName: keyName,
            flags: event.modifierFlags
        )
        return HotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            displayName: displayName
        )
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    private static func displayName(keyName: String, flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.command) {
            parts.append("Command")
        }
        if flags.contains(.option) {
            parts.append("Option")
        }
        if flags.contains(.control) {
            parts.append("Control")
        }
        if flags.contains(.shift) {
            parts.append("Shift")
        }
        parts.append(keyName)
        return parts.joined(separator: " + ")
    }

    private static func keyName(for event: NSEvent) -> String {
        if let mappedName = keyNames[event.keyCode] {
            return mappedName
        }

        if let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines),
           !characters.isEmpty {
            return characters.uppercased()
        }

        return "Key \(event.keyCode)"
    }

    private static let functionKeyCodes: Set<UInt16> = [
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
        UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
        UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
        UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15), UInt16(kVK_F16),
        UInt16(kVK_F17), UInt16(kVK_F18), UInt16(kVK_F19), UInt16(kVK_F20)
    ]

    private static let keyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_Escape): "Escape",
        UInt16(kVK_LeftArrow): "Left Arrow",
        UInt16(kVK_RightArrow): "Right Arrow",
        UInt16(kVK_UpArrow): "Up Arrow",
        UInt16(kVK_DownArrow): "Down Arrow",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19",
        UInt16(kVK_F20): "F20"
    ]

    private enum ShortcutTarget: Equatable {
        case text
        case hudMode
    }
}
