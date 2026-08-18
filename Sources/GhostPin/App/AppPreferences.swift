import Foundation
import GhostPinCore

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

    @Published var hudModeHotKeyEnabled: Bool {
        didSet { defaults.set(hudModeHotKeyEnabled, forKey: Keys.hudModeHotKeyEnabled) }
    }

    @Published var hudModeHotKeyShortcut: HotKeyShortcut? {
        didSet { saveHudModeHotKeyShortcut() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.keepBoardOnTop = defaults.object(forKey: Keys.keepBoardOnTop) == nil ? true : defaults.bool(forKey: Keys.keepBoardOnTop)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        self.hudMode = defaults.string(forKey: Keys.hudMode).flatMap(HudMode.init(rawValue:)) ?? .passthrough
        let loadedOpacity = defaults.object(forKey: Keys.hudOpacity) as? Double ?? 1.0
        self.hudOpacity = min(max(loadedOpacity, 0.5), 1.0)
        self.hudScope = defaults.string(forKey: Keys.hudScope).flatMap(HudScope.init(rawValue:)) ?? .all
        self.hudMaxItems = defaults.object(forKey: Keys.hudMaxItems) as? Int ?? 8
        self.hudAllSpaces = defaults.object(forKey: Keys.hudAllSpaces) == nil ? true : defaults.bool(forKey: Keys.hudAllSpaces)
        if let data = defaults.data(forKey: Keys.hudFrame),
           let decoded = try? JSONDecoder.ghostPin.decode(HudWindowFrame.self, from: data) {
            self.hudFrame = decoded
        } else {
            self.hudFrame = nil
        }
        self.hudModeHotKeyEnabled = defaults.bool(forKey: Keys.hudModeHotKeyEnabled)
        if let data = defaults.data(forKey: Keys.hudModeHotKeyShortcut),
           let decoded = try? JSONDecoder.ghostPin.decode(HotKeyShortcut.self, from: data) {
            self.hudModeHotKeyShortcut = decoded
        } else {
            self.hudModeHotKeyShortcut = nil
        }
    }

    private func saveHudMode() {
        defaults.set(hudMode.rawValue, forKey: Keys.hudMode)
    }

    private func saveHudScope() {
        defaults.set(hudScope.rawValue, forKey: Keys.hudScope)
    }

    private func saveHudFrame() {
        guard let hudFrame,
              let data = try? JSONEncoder.ghostPin.encode(hudFrame) else {
            defaults.removeObject(forKey: Keys.hudFrame)
            return
        }
        defaults.set(data, forKey: Keys.hudFrame)
    }

    private func saveHudModeHotKeyShortcut() {
        guard let hudModeHotKeyShortcut,
              let data = try? JSONEncoder.ghostPin.encode(hudModeHotKeyShortcut) else {
            defaults.removeObject(forKey: Keys.hudModeHotKeyShortcut)
            return
        }
        defaults.set(data, forKey: Keys.hudModeHotKeyShortcut)
    }

    private enum Keys {
        static let keepBoardOnTop = "keepBoardOnTop"
        static let launchAtLogin = "launchAtLogin"
        static let hudMode = "hudMode"
        static let hudOpacity = "hudOpacity"
        static let hudScope = "hudScope"
        static let hudMaxItems = "hudMaxItems"
        static let hudAllSpaces = "hudAllSpaces"
        static let hudFrame = "hudFrame"
        static let hudModeHotKeyEnabled = "hudModeHotKeyEnabled"
        static let hudModeHotKeyShortcut = "hudModeHotKeyShortcut"
    }
}
