import Foundation

public struct HotKeyShortcut: Codable, Equatable, Identifiable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayName: String

    public var id: String {
        "\(modifiers)-\(keyCode)-\(displayName)"
    }

    public init(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }

    public static let optionSpace = HotKeyShortcut(keyCode: 49, modifiers: 2_048, displayName: "Option + Space")
    public static let optionN = HotKeyShortcut(keyCode: 45, modifiers: 2_048, displayName: "Option + N")
    public static let f8 = HotKeyShortcut(keyCode: 100, modifiers: 0, displayName: "F8")

    public static let defaultShortcut = optionSpace
    public static let defaultTextShortcut = optionSpace
    public static let defaultVoiceShortcut = f8
    public static let presets = [optionSpace, optionN, f8]

    public static func legacyPreset(rawValue: String) -> HotKeyShortcut? {
        switch rawValue {
        case "optionSpace":
            return .optionSpace
        case "optionN":
            return .optionN
        case "f8":
            return .f8
        default:
            return nil
        }
    }
}
