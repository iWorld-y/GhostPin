import Foundation
import TodoPinCore

enum HudMode: String, Codable, CaseIterable {
    case passthrough
    case interactive
}

struct HudWindowFrame: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

final class AppPreferences: ObservableObject {
    @Published var textHotKeyShortcut: HotKeyShortcut {
        didSet { saveTextHotKeyShortcut() }
    }

    @Published var voiceHotKeyShortcut: HotKeyShortcut {
        didSet { saveVoiceHotKeyShortcut() }
    }

    @Published var reminderSettings: ReminderSettings {
        didSet { saveReminderSettings() }
    }

    @Published var speechLanguage: String {
        didSet { defaults.set(speechLanguage, forKey: Keys.speechLanguage) }
    }

    @Published var keepBoardOnTop: Bool {
        didSet { defaults.set(keepBoardOnTop, forKey: Keys.keepBoardOnTop) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var hudMode: HudMode {
        didSet { saveHudMode() }
    }

    @Published var hudOpacity: Double {
        didSet { defaults.set(hudOpacity, forKey: Keys.hudOpacity) }
    }

    @Published var hudScope: HudScope {
        didSet { saveHudScope() }
    }

    @Published var hudMaxItems: Int {
        didSet { defaults.set(hudMaxItems, forKey: Keys.hudMaxItems) }
    }

    @Published var hudAllSpaces: Bool {
        didSet { defaults.set(hudAllSpaces, forKey: Keys.hudAllSpaces) }
    }

    @Published var hudFrame: HudWindowFrame? {
        didSet { saveHudFrame() }
    }

    @Published var hudModeHotKeyShortcut: HotKeyShortcut {
        didSet { saveHudModeHotKeyShortcut() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loadedTextHotKeyShortcut: HotKeyShortcut
        if let data = defaults.data(forKey: Keys.textHotKeyShortcut),
           let decoded = try? JSONDecoder.todoPin.decode(HotKeyShortcut.self, from: data) {
            loadedTextHotKeyShortcut = decoded
        } else if let data = defaults.data(forKey: Keys.hotKeyShortcut),
                  let decoded = try? JSONDecoder.todoPin.decode(HotKeyShortcut.self, from: data) {
            loadedTextHotKeyShortcut = decoded
        } else if let legacyRawValue = defaults.string(forKey: Keys.hotKeyPreset),
                  let legacyShortcut = HotKeyShortcut.legacyPreset(rawValue: legacyRawValue) {
            loadedTextHotKeyShortcut = legacyShortcut
        } else {
            loadedTextHotKeyShortcut = .defaultTextShortcut
        }

        let loadedVoiceHotKeyShortcut: HotKeyShortcut
        if let data = defaults.data(forKey: Keys.voiceHotKeyShortcut),
           let decoded = try? JSONDecoder.todoPin.decode(HotKeyShortcut.self, from: data) {
            loadedVoiceHotKeyShortcut = decoded
        } else {
            loadedVoiceHotKeyShortcut = .defaultVoiceShortcut
        }

        self.textHotKeyShortcut = loadedTextHotKeyShortcut
        self.voiceHotKeyShortcut = loadedVoiceHotKeyShortcut == loadedTextHotKeyShortcut
            ? (loadedTextHotKeyShortcut == .defaultVoiceShortcut ? .optionN : .defaultVoiceShortcut)
            : loadedVoiceHotKeyShortcut

        self.speechLanguage = defaults.string(forKey: Keys.speechLanguage) ?? "zh"
        self.keepBoardOnTop = defaults.object(forKey: Keys.keepBoardOnTop) == nil ? true : defaults.bool(forKey: Keys.keepBoardOnTop)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        self.hudMode = defaults.string(forKey: Keys.hudMode).flatMap(HudMode.init(rawValue:)) ?? .passthrough
        let loadedOpacity = defaults.object(forKey: Keys.hudOpacity) as? Double ?? 1.0
        self.hudOpacity = min(max(loadedOpacity, 0.5), 1.0)
        self.hudScope = defaults.string(forKey: Keys.hudScope).flatMap(HudScope.init(rawValue:)) ?? .all
        self.hudMaxItems = defaults.object(forKey: Keys.hudMaxItems) as? Int ?? 8
        self.hudAllSpaces = defaults.object(forKey: Keys.hudAllSpaces) == nil ? true : defaults.bool(forKey: Keys.hudAllSpaces)
        if let data = defaults.data(forKey: Keys.hudFrame),
           let decoded = try? JSONDecoder.todoPin.decode(HudWindowFrame.self, from: data) {
            self.hudFrame = decoded
        } else {
            self.hudFrame = nil
        }

        let hudModeFallback: HotKeyShortcut
        if HotKeyShortcut.optionCommandT != loadedTextHotKeyShortcut,
           HotKeyShortcut.optionCommandT != loadedVoiceHotKeyShortcut {
            hudModeFallback = .optionCommandT
        } else {
            hudModeFallback = HotKeyShortcut.presets.first {
                $0 != loadedTextHotKeyShortcut && $0 != loadedVoiceHotKeyShortcut
            } ?? .optionCommandT
        }

        if let data = defaults.data(forKey: Keys.hudModeHotKeyShortcut),
           let decoded = try? JSONDecoder.todoPin.decode(HotKeyShortcut.self, from: data),
           decoded != loadedTextHotKeyShortcut,
           decoded != loadedVoiceHotKeyShortcut {
            self.hudModeHotKeyShortcut = decoded
        } else {
            self.hudModeHotKeyShortcut = hudModeFallback
        }

        if let data = defaults.data(forKey: Keys.reminderSettings),
           let decoded = try? JSONDecoder.todoPin.decode(ReminderSettings.self, from: data) {
            self.reminderSettings = decoded
        } else {
            self.reminderSettings = ReminderSettings()
        }
    }

    private func saveTextHotKeyShortcut() {
        guard let data = try? JSONEncoder.todoPin.encode(textHotKeyShortcut) else {
            return
        }
        defaults.set(data, forKey: Keys.textHotKeyShortcut)
    }

    private func saveVoiceHotKeyShortcut() {
        guard let data = try? JSONEncoder.todoPin.encode(voiceHotKeyShortcut) else {
            return
        }
        defaults.set(data, forKey: Keys.voiceHotKeyShortcut)
    }

    private func saveReminderSettings() {
        guard let data = try? JSONEncoder.todoPin.encode(reminderSettings) else {
            return
        }
        defaults.set(data, forKey: Keys.reminderSettings)
    }

    private func saveHudMode() {
        defaults.set(hudMode.rawValue, forKey: Keys.hudMode)
    }

    private func saveHudScope() {
        defaults.set(hudScope.rawValue, forKey: Keys.hudScope)
    }

    private func saveHudModeHotKeyShortcut() {
        guard let data = try? JSONEncoder.todoPin.encode(hudModeHotKeyShortcut) else {
            return
        }
        defaults.set(data, forKey: Keys.hudModeHotKeyShortcut)
    }

    private func saveHudFrame() {
        guard let hudFrame,
              let data = try? JSONEncoder.todoPin.encode(hudFrame) else {
            defaults.removeObject(forKey: Keys.hudFrame)
            return
        }
        defaults.set(data, forKey: Keys.hudFrame)
    }

    private enum Keys {
        static let textHotKeyShortcut = "textHotKeyShortcut"
        static let voiceHotKeyShortcut = "voiceHotKeyShortcut"
        static let hotKeyShortcut = "hotKeyShortcut"
        static let hotKeyPreset = "hotKeyPreset"
        static let reminderSettings = "reminderSettings"
        static let speechLanguage = "speechLanguage"
        static let keepBoardOnTop = "keepBoardOnTop"
        static let launchAtLogin = "launchAtLogin"
        static let hudMode = "hudMode"
        static let hudOpacity = "hudOpacity"
        static let hudScope = "hudScope"
        static let hudMaxItems = "hudMaxItems"
        static let hudAllSpaces = "hudAllSpaces"
        static let hudFrame = "hudFrame"
        static let hudModeHotKeyShortcut = "hudModeHotKeyShortcut"
    }
}
