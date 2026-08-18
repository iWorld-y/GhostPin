import AppKit
import Carbon.HIToolbox

enum HotKeySetupState: Equatable {
    case disabled
    case pendingConfiguration
    case registered
    case failure(String)
}

enum HotKeyRegistrationError: LocalizedError, Equatable {
    case systemConflict(feature: String)
    case occupied
    case failed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .systemConflict(let feature):
            return "与系统快捷键「\(feature)」冲突，请换一个组合。"
        case .occupied:
            return "该快捷键可能已被其他应用占用，请换一个组合。"
        case .failed(let status):
            return "快捷键注册失败（错误码 \(status)），请换一个组合。"
        }
    }
}

final class HotKeyService {
    private let action: @MainActor @Sendable () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registeredShortcut: HotKeyShortcut?

    var isRegistered: Bool {
        hotKeyRef != nil
    }

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    func preflight(_ shortcut: HotKeyShortcut) throws {
        if let feature = Self.systemSymbolicFeature(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {
            throw HotKeyRegistrationError.systemConflict(feature: feature)
        }
    }

    func register(_ shortcut: HotKeyShortcut) throws {
        unregister()
        try preflight(shortcut)
        try installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            UInt32(shortcut.modifiers),
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            throw status == eventHotKeyExistsErr ? HotKeyRegistrationError.occupied : .failed(status)
        }
        hotKeyRef = ref
        registeredShortcut = shortcut
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredShortcut = nil
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else {
            return
        }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                guard service.isMatchingHotKeyEvent(event) else {
                    return OSStatus(eventNotHandledErr)
                }
                service.fireAction()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            throw HotKeyRegistrationError.failed(status)
        }
    }

    private func isMatchingHotKeyEvent(_ event: EventRef?) -> Bool {
        guard let event else {
            return false
        }
        var hotKeyID = EventHotKeyID()
        var actualType: EventParamType = 0
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            &actualType,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return false
        }
        return hotKeyID.signature == Self.signature && hotKeyID.id == Self.hotKeyID
    }

    private func fireAction() {
        Task { @MainActor [action] in
            action()
        }
    }

    private static func systemSymbolicFeature(keyCode: UInt32, modifiers: UInt32) -> String? {
        guard let defaults = UserDefaults(suiteName: symbolicHotKeyDomain) else {
            return nil
        }
        guard let entries = defaults.dictionary(forKey: "AppleSymbolicHotKeys") else {
            return nil
        }
        for (type, value) in entries {
            guard let info = value as? [String: Any],
                  let valueInfo = info["value"] as? [String: Any],
                  let parameters = valueInfo["parameters"] as? [Any],
                  parameters.count >= 2,
                  let entryKeyCode = parameters[0] as? Int,
                  let entryModifiers = parameters[1] as? Int else {
                continue
            }
            if let enabled = info["enabled"] as? Bool, !enabled {
                continue
            }
            let carbonModifiers = HotKeyShortcut.carbonModifiers(
                from: NSEvent.ModifierFlags(rawValue: UInt(entryModifiers))
            )
            if entryKeyCode == Int(keyCode), carbonModifiers == modifiers {
                return Self.featureName(for: type)
            }
        }
        return nil
    }

    private static func featureName(for type: String) -> String {
        switch type {
        case "7":
            return "调度中心"
        case "8":
            return "应用窗口"
        case "9":
            return "显示桌面"
        case "10":
            return "Dashboard"
        case "11":
            return "通知中心"
        case "12":
            return "启动台"
        case "13", "64":
            return "聚焦搜索"
        case "28", "29", "30", "31":
            return "屏幕截图"
        case "32":
            return "辅助功能快捷键"
        case "33":
            return "旁白（VoiceOver）"
        case "34":
            return "辅助功能快捷键面板"
        case "36", "37", "60", "61":
            return "输入法切换"
        case "52":
            return "隐藏/显示程序坞"
        case "65":
            return "访达搜索窗口"
        case "79", "80", "81", "82", "83", "84", "85", "86", "87", "88":
            return "键盘焦点导航"
        default:
            return "系统快捷键"
        }
    }

    private static let signature: OSType = 0x4750484B
    private static let hotKeyID: UInt32 = 1
    private static let symbolicHotKeyDomain = "com.apple.symbolichotkeys"
}
