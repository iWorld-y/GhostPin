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
    public static let optionCommandT = HotKeyShortcut(keyCode: 17, modifiers: 2_304, displayName: "Option + Command + T")

    public static let defaultShortcut = optionSpace
    public static let defaultTextShortcut = optionSpace
    public static let presets = [optionSpace, optionN, optionCommandT]

    public static func legacyPreset(rawValue: String) -> HotKeyShortcut? {
        switch rawValue {
        case "optionSpace":
            return .optionSpace
        case "optionN":
            return .optionN
        default:
            return nil
        }
    }
}
