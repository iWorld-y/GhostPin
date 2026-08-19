namespace GhostPin.Windows.Core.Settings;

/// <summary>Windows 全局快捷键使用的公开修饰键。</summary>
[Flags]
public enum HotKeyModifiers : uint
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Windows = 0x0008
}

/// <summary>可持久化的 Windows 虚拟键与修饰键组合。</summary>
public sealed record class HotKeyShortcut
{
    private const HotKeyModifiers ModifierMask =
        HotKeyModifiers.Alt | HotKeyModifiers.Control | HotKeyModifiers.Shift | HotKeyModifiers.Windows;

    private HotKeyShortcut(int virtualKey, HotKeyModifiers modifiers)
    {
        VirtualKey = virtualKey;
        Modifiers = modifiers;
    }

    public int VirtualKey { get; }
    public HotKeyModifiers Modifiers { get; }
    public string DisplayName => BuildDisplayName(VirtualKey, Modifiers);

    public static HotKeyShortcut? Create(int virtualKey, HotKeyModifiers modifiers)
    {
        modifiers &= ModifierMask;
        if (IsModifierKey(virtualKey) || (!IsFunctionKey(virtualKey) && modifiers == HotKeyModifiers.None))
        {
            return null;
        }

        return virtualKey is > 0 and <= 0xFF ? new HotKeyShortcut(virtualKey, modifiers) : null;
    }

    public static bool IsModifierKey(int virtualKey)
    {
        return virtualKey is 0x10 or 0x11 or 0x12 or 0x5B or 0x5C or
            >= 0xA0 and <= 0xA5;
    }

    private static bool IsFunctionKey(int virtualKey)
    {
        return virtualKey is >= 0x70 and <= 0x83;
    }

    private static string BuildDisplayName(int virtualKey, HotKeyModifiers modifiers)
    {
        var names = new List<string>(5);
        if (modifiers.HasFlag(HotKeyModifiers.Control)) names.Add("Ctrl");
        if (modifiers.HasFlag(HotKeyModifiers.Alt)) names.Add("Alt");
        if (modifiers.HasFlag(HotKeyModifiers.Shift)) names.Add("Shift");
        if (modifiers.HasFlag(HotKeyModifiers.Windows)) names.Add("Win");
        names.Add(KeyName(virtualKey));
        return string.Join("+", names);
    }

    private static string KeyName(int virtualKey)
    {
        if (virtualKey is >= 0x30 and <= 0x39 || virtualKey is >= 0x41 and <= 0x5A)
        {
            return ((char)virtualKey).ToString();
        }
        if (IsFunctionKey(virtualKey))
        {
            return $"F{virtualKey - 0x6F}";
        }

        return virtualKey switch
        {
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x1B => "Esc",
            0x20 => "Space",
            0x21 => "PageUp",
            0x22 => "PageDown",
            0x23 => "End",
            0x24 => "Home",
            0x25 => "Left",
            0x26 => "Up",
            0x27 => "Right",
            0x28 => "Down",
            0x2D => "Insert",
            0x2E => "Delete",
            _ => $"键{virtualKey}"
        };
    }
}
