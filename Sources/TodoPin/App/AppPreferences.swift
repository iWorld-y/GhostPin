import Foundation
import TodoPinCore

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
        self.keepBoardOnTop = defaults.bool(forKey: Keys.keepBoardOnTop)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

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

    private enum Keys {
        static let textHotKeyShortcut = "textHotKeyShortcut"
        static let voiceHotKeyShortcut = "voiceHotKeyShortcut"
        static let hotKeyShortcut = "hotKeyShortcut"
        static let hotKeyPreset = "hotKeyPreset"
        static let reminderSettings = "reminderSettings"
        static let speechLanguage = "speechLanguage"
        static let keepBoardOnTop = "keepBoardOnTop"
        static let launchAtLogin = "launchAtLogin"
    }
}
