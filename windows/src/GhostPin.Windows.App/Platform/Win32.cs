using System.ComponentModel;
using System.Runtime.InteropServices;
using GhostPin.Windows.Core.Models;

namespace GhostPin.Windows.App.Platform;

/// <summary>GhostPin HUD 使用的最小 Win32 互操作面。</summary>
public static class Win32
{
    public const int GwlExStyle = -20;
    public const long WsExToolWindow = 0x00000080L;
    public const long WsExLayered = 0x00080000L;
    public const long WsExTransparent = 0x00000020L;
    public const long WsExNoActivate = 0x08000000L;
    public const long WsExAppWindow = 0x00040000L;

    public const uint SwpNoSize = 0x0001;
    public const uint SwpNoMove = 0x0002;
    public const uint SwpNoActivate = 0x0010;
    public const uint SwpNoZOrder = 0x0004;
    public const uint SwpFrameChanged = 0x0020;
    public const uint SwpShowWindow = 0x0040;
    public const uint WmNcHitTest = 0x0084;
    public const uint WmDpiChanged = 0x02E0;
    public const uint MonitorDefaultToPrimary = 0x00000001;
    public const uint MonitorDefaultToNearest = 0x00000002;
    public const uint DpiAwarenessContextPerMonitorAwareV2 = unchecked((uint)-4);

    public const int HtNowhere = 0;
    public const int HtClient = 1;
    public const int HtLeft = 10;
    public const int HtRight = 11;
    public const int HtTop = 12;
    public const int HtTopLeft = 13;
    public const int HtTopRight = 14;
    public const int HtBottom = 15;
    public const int HtBottomLeft = 16;
    public const int HtBottomRight = 17;

    public static readonly IntPtr HwndTopmost = new IntPtr(-1);
    public static readonly IntPtr HwndNotTopmost = new IntPtr(-2);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    private static extern int SetWindowLong32(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RectNative rect);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr MonitorFromPoint(PointNative point, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MonitorInfo monitorInfo);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    public static long GetExtendedStyle(IntPtr hwnd)
    {
        SetLastErrorCode(0);
        var value = IntPtr.Size == 8 ? GetWindowLongPtr64(hwnd, GwlExStyle).ToInt64() : GetWindowLong32(hwnd, GwlExStyle);
        ThrowIfLastError(value == 0);
        return value;
    }

    public static long SetExtendedStyle(IntPtr hwnd, long style)
    {
        SetLastErrorCode(0);
        var previous = IntPtr.Size == 8
            ? SetWindowLongPtr64(hwnd, GwlExStyle, new IntPtr(style)).ToInt64()
            : SetWindowLong32(hwnd, GwlExStyle, unchecked((int)style));
        ThrowIfLastError(previous == 0);
        return previous;
    }

    public static void SetWindowPosOrThrow(
        IntPtr hwnd,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags)
    {
        if (!SetWindowPos(hwnd, insertAfter, x, y, width, height, flags))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SetWindowPos 失败。");
        }
    }

    private static void SetLastErrorCode(uint error)
    {
        SetLastError(error);
    }

    private static void ThrowIfLastError(bool zeroResult)
    {
        var error = Marshal.GetLastWin32Error();
        if (zeroResult && error != 0)
        {
            throw new Win32Exception(error, "窗口扩展样式调用失败。");
        }
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern void SetLastError(uint dwErrCode);

    public static long CalculateHudExtendedStyle(long currentStyle, HudMode mode)
    {
        var style = (currentStyle | WsExToolWindow | WsExLayered) & ~WsExAppWindow;
        style &= ~(WsExTransparent | WsExNoActivate);
        if (mode == HudMode.Passthrough)
        {
            style |= WsExTransparent | WsExNoActivate;
        }

        return style;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RectNative
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PointNative
    {
        public int X;
        public int Y;

        public PointNative(int x, int y)
        {
            X = x;
            Y = y;
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MonitorInfo
    {
        public int CbSize;
        public RectNative Monitor;
        public RectNative Work;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string Device;

        public static MonitorInfo Create()
        {
            return new MonitorInfo { CbSize = Marshal.SizeOf<MonitorInfo>(), Device = string.Empty };
        }
    }
}
