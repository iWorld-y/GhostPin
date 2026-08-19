using System.ComponentModel;
using System.Windows.Interop;
using GhostPin.Windows.Core.Settings;

namespace GhostPin.Windows.App.Platform;

/// <summary>通过公开 Win32 API 注册并分发单个全局快捷键。</summary>
public sealed class GlobalHotKeyService : IDisposable
{
    private const int HotKeyId = 0x4750;
    private readonly IntPtr _hwnd;
    private readonly Action _action;
    private readonly HwndSource _source;
    private bool _isRegistered;
    private bool _isDisposed;

    public GlobalHotKeyService(IntPtr hwnd, Action action)
    {
        if (hwnd == IntPtr.Zero) throw new ArgumentException("快捷键服务需要有效的窗口句柄。", nameof(hwnd));
        _hwnd = hwnd;
        _action = action ?? throw new ArgumentNullException(nameof(action));
        _source = HwndSource.FromHwnd(hwnd) ?? throw new InvalidOperationException("无法取得 HUD 的消息源。");
        _source.AddHook(WindowProcedure);
    }

    public HotKeyShortcut? RegisteredShortcut { get; private set; }

    public void Register(HotKeyShortcut shortcut)
    {
        ObjectDisposedException.ThrowIf(_isDisposed, this);
        ArgumentNullException.ThrowIfNull(shortcut);
        Unregister();

        var modifiers = (uint)shortcut.Modifiers | Win32.ModNoRepeat;
        if (!Win32.RegisterHotKey(_hwnd, HotKeyId, modifiers, (uint)shortcut.VirtualKey))
        {
            throw new Win32Exception(
                System.Runtime.InteropServices.Marshal.GetLastWin32Error(),
                "该快捷键可能已被系统或其他应用占用，请换一个组合。");
        }

        _isRegistered = true;
        RegisteredShortcut = shortcut;
    }

    public void Unregister()
    {
        if (!_isRegistered)
        {
            return;
        }

        Win32.UnregisterHotKey(_hwnd, HotKeyId);
        _isRegistered = false;
        RegisteredShortcut = null;
    }

    public void Dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        Unregister();
        _source.RemoveHook(WindowProcedure);
        _isDisposed = true;
    }

    private IntPtr WindowProcedure(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == Win32.WmHotKey && wParam.ToInt32() == HotKeyId)
        {
            handled = true;
            _action();
        }

        return IntPtr.Zero;
    }
}
