import Foundation
import GhostPinCore

enum HudMode: String, Codable, CaseIterable {
    case passthrough
    case interactive
}

/// 交互模式下用户主动选择的视图；穿透模式始终收为列表。
enum HudView: String, Codable, CaseIterable {
    case list
    case quadrants
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

    /// 交互模式最后一次主动选择的视图，缺省为列表；自动收为列表不改写此偏好。
    @Published var hudInteractiveView: HudView {
        didSet { defaults.set(hudInteractiveView.rawValue, forKey: Keys.hudInteractiveView) }
    }

    /// 当前生效视图：菜单栏、快捷键与启动恢复共用同一取值路径。
    var effectiveHudView: HudView {
        hudMode == .interactive ? hudInteractiveView : .list
    }

    @Published var hudPassthroughOpacity: Double {
        didSet { defaults.set(hudPassthroughOpacity, forKey: Keys.hudPassthroughOpacity) }
    }

    @Published var hudInteractiveOpacity: Double {
        didSet { defaults.set(hudInteractiveOpacity, forKey: Keys.hudInteractiveOpacity) }
    }

    @Published var hudScope: HudScope {
        didSet { saveHudScope() }
    }

    @Published var hudMaxItems: Int {
        didSet { defaults.set(hudMaxItems, forKey: Keys.hudMaxItems) }
    }

    /// 有 Doing 任务时只展示 Doing 分区，默认开启。
    @Published var hudFocusDoing: Bool {
        didSet { defaults.set(hudFocusDoing, forKey: Keys.hudFocusDoing) }
    }

    @Published var hudAllSpaces: Bool {
        didSet { defaults.set(hudAllSpaces, forKey: Keys.hudAllSpaces) }
    }

    @Published var hudFrame: HudWindowFrame? {
        didSet { saveHudFrame() }
    }

    /// 四象限布局的窗口尺寸，与列表的 hudFrame 分开保存。
    @Published var hudQuadrantsFrame: HudWindowFrame? {
        didSet { saveHudQuadrantsFrame() }
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
        self.hudInteractiveView = defaults.string(forKey: Keys.hudInteractiveView).flatMap(HudView.init(rawValue:)) ?? .list
        let legacyOpacity = defaults.object(forKey: Keys.hudOpacity) as? Double
        let passthroughOpacity = defaults.object(forKey: Keys.hudPassthroughOpacity) as? Double
            ?? (legacyOpacity.map { $0 * 0.86 } ?? 1.0)
        let interactiveOpacity = defaults.object(forKey: Keys.hudInteractiveOpacity) as? Double
            ?? legacyOpacity
            ?? 1.0
        self.hudPassthroughOpacity = min(max(passthroughOpacity, 0.1), 1.0)
        self.hudInteractiveOpacity = min(max(interactiveOpacity, 0.1), 1.0)
        self.hudScope = defaults.string(forKey: Keys.hudScope).flatMap(HudScope.init(rawValue:)) ?? .all
        self.hudMaxItems = defaults.object(forKey: Keys.hudMaxItems) as? Int ?? 8
        // 键缺失（首次启动或旧版本升级）时按开启处理，只有用户显式关闭才为 false。
        self.hudFocusDoing = defaults.object(forKey: Keys.hudFocusDoing) == nil ? true : defaults.bool(forKey: Keys.hudFocusDoing)
        self.hudAllSpaces = defaults.object(forKey: Keys.hudAllSpaces) == nil ? true : defaults.bool(forKey: Keys.hudAllSpaces)
        if let data = defaults.data(forKey: Keys.hudFrame),
           let decoded = try? JSONDecoder.ghostPin.decode(HudWindowFrame.self, from: data) {
            self.hudFrame = decoded
        } else {
            self.hudFrame = nil
        }
        if let data = defaults.data(forKey: Keys.hudQuadrantsFrame),
           let decoded = try? JSONDecoder.ghostPin.decode(HudWindowFrame.self, from: data) {
            self.hudQuadrantsFrame = decoded
        } else {
            self.hudQuadrantsFrame = nil
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

    private func saveHudQuadrantsFrame() {
        guard let hudQuadrantsFrame,
              let data = try? JSONEncoder.ghostPin.encode(hudQuadrantsFrame) else {
            defaults.removeObject(forKey: Keys.hudQuadrantsFrame)
            return
        }
        defaults.set(data, forKey: Keys.hudQuadrantsFrame)
    }

    /// Debug 隔离验证：设置 GHOSTPIN_TEST_SUPPORT_ROOT 时偏好写入该目录，不碰真实 UserDefaults。
    static func liveDefaults() -> UserDefaults {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["GHOSTPIN_TEST_SUPPORT_ROOT"], !path.isEmpty {
            let plistPath = URL(fileURLWithPath: path, isDirectory: true)
                .appendingPathComponent("preferences")
                .path
            if let isolated = UserDefaults(suiteName: plistPath) {
                return isolated
            }
        }
        #endif
        return .standard
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
        static let hudInteractiveView = "hudInteractiveView"
        static let hudOpacity = "hudOpacity"
        static let hudPassthroughOpacity = "hudPassthroughOpacity"
        static let hudInteractiveOpacity = "hudInteractiveOpacity"
        static let hudScope = "hudScope"
        static let hudMaxItems = "hudMaxItems"
        static let hudFocusDoing = "hudFocusDoing"
        static let hudAllSpaces = "hudAllSpaces"
        static let hudFrame = "hudFrame"
        static let hudQuadrantsFrame = "hudQuadrantsFrame"
        static let hudModeHotKeyEnabled = "hudModeHotKeyEnabled"
        static let hudModeHotKeyShortcut = "hudModeHotKeyShortcut"
    }
}
