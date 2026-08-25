import AppKit
import Carbon.HIToolbox

struct HotKeyShortcut: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let modifierMask: UInt32 = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    static func isValid(keyCode: UInt32, modifiers: UInt32) -> Bool {
        if isModifierKey(keyCode) {
            return false
        }
        if functionKeyCodes.contains(keyCode) {
            return true
        }
        return modifiers & modifierMask != 0
    }

    init?(keyCode: UInt32, modifiers: UInt32) {
        guard Self.isValid(keyCode: keyCode, modifiers: modifiers) else {
            return nil
        }
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
        self.displayName = Self.buildDisplayName(keyCode: keyCode, modifiers: self.modifiers)
    }

    static func == (lhs: HotKeyShortcut, rhs: HotKeyShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }

    static func isModifierKey(_ keyCode: UInt32) -> Bool {
        keyCode >= 54 && keyCode <= 63
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
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

    private static func buildDisplayName(keyCode: UInt32, modifiers: UInt32) -> String {
        var name = ""
        if modifiers & UInt32(controlKey) != 0 {
            name += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            name += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            name += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            name += "⌘"
        }
        name += keyName(forKeyCode: keyCode, modifiers: modifiers)
        return name
    }

    private static func keyName(forKeyCode keyCode: UInt32, modifiers: UInt32) -> String {
        if let name = fixedKeyNames[UInt16(keyCode)] {
            return name
        }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "键\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else {
            return "键\(keyCode)"
        }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            UInt32((modifiers & UInt32(shiftKey)) >> 8),
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else {
            return "键\(keyCode)"
        }
        let text = String(utf16CodeUnits: characters, count: length)
        let hasShift = modifiers & UInt32(shiftKey) != 0
        if !hasShift, text.count == 1, text.rangeOfCharacter(from: .letters) != nil {
            return text.uppercased()
        }
        return text
    }

    private static let functionKeyCodes: Set<UInt32> = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5),
        UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10),
        UInt32(kVK_F11), UInt32(kVK_F12), UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15),
        UInt32(kVK_F16), UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20)
    ]

    private static let fixedKeyNames: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
