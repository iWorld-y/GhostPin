using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using GhostPin.Windows.Core.Models;

namespace GhostPin.Windows.App.Platform;

public sealed record WindowStyleDiagnostics(IntPtr Hwnd, long ExtendedStyle, HudMode Mode, bool IsTopmost)
{
    public bool IsToolWindow => (ExtendedStyle & Win32.WsExToolWindow) != 0;
    public bool IsLayered => (ExtendedStyle & Win32.WsExLayered) != 0;
    public bool IsTransparent => (ExtendedStyle & Win32.WsExTransparent) != 0;
    public bool IsNoActivate => (ExtendedStyle & Win32.WsExNoActivate) != 0;
}

/// <summary>集中管理 HUD HWND 样式、Z 序、命中测试和非激活显示。</summary>
public sealed class HudWindowHost : IDisposable
{
    private readonly Window _window;
    private HwndSource? _source;
    private IntPtr _hwnd;
    private HudMode _mode = HudMode.Passthrough;
    private bool _isTopmost = true;
    private bool _attached;

    public HudWindowHost(Window window)
    {
        _window = window ?? throw new ArgumentNullException(nameof(window));
        _window.SourceInitialized += OnSourceInitialized;
        _window.ShowActivated = false;
    }

    public IntPtr Hwnd => _hwnd;
    public HudMode Mode => _mode;
    public bool IsTopmost => _isTopmost;
    public bool IsInitialized => _hwnd != IntPtr.Zero;

    public event Action<Exception>? DiagnosticError;

    public void SetInteractionMode(HudMode mode)
    {
        if (!IsInitialized)
        {
            _mode = mode;
            return;
        }

        var previousMode = _mode;
        _mode = mode;
        try
        {
            ApplyInteractionStyle();
        }
        catch
        {
            _mode = previousMode;
            throw;
        }
    }

    public void SetTopmost(bool isTopmost)
    {
        if (!IsInitialized)
        {
            _isTopmost = isTopmost;
            return;
        }

        var insertAfter = isTopmost ? Win32.HwndTopmost : Win32.HwndNotTopmost;
        Win32.SetWindowPosOrThrow(_hwnd, insertAfter, 0, 0, 0, 0, Win32.SwpNoMove | Win32.SwpNoSize | Win32.SwpNoActivate);
        _isTopmost = isTopmost;
    }

    public void SetOpacity(double opacity)
    {
        _window.Opacity = Math.Clamp(opacity, 0.5, 1.0);
    }

    public void ShowWithoutActivation()
    {
        _window.ShowActivated = false;
        if (!_window.IsVisible)
        {
            _window.Show();
        }

        if (IsInitialized)
        {
            var flags = Win32.SwpNoActivate | Win32.SwpShowWindow;
            Win32.SetWindowPosOrThrow(_hwnd, _isTopmost ? Win32.HwndTopmost : Win32.HwndNotTopmost, 0, 0, 0, 0, flags | Win32.SwpNoMove | Win32.SwpNoSize);
        }
    }

    public void ApplyPhysicalBounds(System.Windows.Rect bounds)
    {
        if (!IsInitialized)
        {
            throw new InvalidOperationException("HUD HWND 尚未初始化。");
        }

        Win32.SetWindowPosOrThrow(
            _hwnd,
            _isTopmost ? Win32.HwndTopmost : Win32.HwndNotTopmost,
            (int)Math.Round(bounds.Left),
            (int)Math.Round(bounds.Top),
            Math.Max(1, (int)Math.Round(bounds.Width)),
            Math.Max(1, (int)Math.Round(bounds.Height)),
            Win32.SwpNoActivate | Win32.SwpNoZOrder);
    }

    public void Hide()
    {
        _window.Hide();
    }

    public WindowStyleDiagnostics ReadDiagnostics()
    {
        return new WindowStyleDiagnostics(_hwnd, IsInitialized ? Win32.GetExtendedStyle(_hwnd) : 0, _mode, _isTopmost);
    }

    public void Dispose()
    {
        _window.SourceInitialized -= OnSourceInitialized;
        if (_source is not null)
        {
            _source.RemoveHook(WindowHook);
            _source = null;
        }
    }

    public static int ResizeHitTest(System.Windows.Rect windowRect, System.Windows.Point screenPoint, double border = 8)
    {
        var left = screenPoint.X - windowRect.Left <= border;
        var right = windowRect.Right - screenPoint.X <= border;
        var top = screenPoint.Y - windowRect.Top <= border;
        var bottom = windowRect.Bottom - screenPoint.Y <= border;
        if (top && left) return Win32.HtTopLeft;
        if (top && right) return Win32.HtTopRight;
        if (bottom && left) return Win32.HtBottomLeft;
        if (bottom && right) return Win32.HtBottomRight;
        if (left) return Win32.HtLeft;
        if (right) return Win32.HtRight;
        if (top) return Win32.HtTop;
        if (bottom) return Win32.HtBottom;
        return Win32.HtClient;
    }

    private void OnSourceInitialized(object? sender, EventArgs args)
    {
        if (_attached)
        {
            return;
        }

        _attached = true;
        try
        {
            _hwnd = new WindowInteropHelper(_window).Handle;
            _source = HwndSource.FromHwnd(_hwnd);
            _source?.AddHook(WindowHook);
            ApplyInteractionStyle();
            SetTopmost(_isTopmost);
        }
        catch (Exception error)
        {
            DiagnosticError?.Invoke(error);
        }
    }

    private void ApplyInteractionStyle()
    {
        var current = Win32.GetExtendedStyle(_hwnd);
        var desired = Win32.CalculateHudExtendedStyle(current, _mode);
        if (desired != current)
        {
            Win32.SetExtendedStyle(_hwnd, desired);
        }

        Win32.SetWindowPosOrThrow(
            _hwnd,
            _isTopmost ? Win32.HwndTopmost : Win32.HwndNotTopmost,
            0,
            0,
            0,
            0,
            Win32.SwpNoMove | Win32.SwpNoSize | Win32.SwpNoActivate | Win32.SwpFrameChanged);
    }

    private IntPtr WindowHook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == Win32.WmDpiChanged && lParam != IntPtr.Zero)
        {
            var suggested = Marshal.PtrToStructure<Win32.RectNative>(lParam);
            try
            {
                Win32.SetWindowPosOrThrow(
                    hwnd,
                    _isTopmost ? Win32.HwndTopmost : Win32.HwndNotTopmost,
                    suggested.Left,
                    suggested.Top,
                    suggested.Right - suggested.Left,
                    suggested.Bottom - suggested.Top,
                    Win32.SwpNoActivate | Win32.SwpNoZOrder);
            }
            catch (Exception error)
            {
                DiagnosticError?.Invoke(error);
            }
            // 让 WPF PerMonitorV2 继续完成自己的 DPI/HwndTarget 更新。
            handled = false;
            return IntPtr.Zero;
        }

        if (message != Win32.WmNcHitTest || _mode != HudMode.Interactive || !Win32.GetWindowRect(hwnd, out var nativeRect))
        {
            return IntPtr.Zero;
        }

        var packed = lParam.ToInt64();
        var x = (short)(packed & 0xffff);
        var y = (short)((packed >> 16) & 0xffff);
        var hit = ResizeHitTest(
            new System.Windows.Rect(nativeRect.Left, nativeRect.Top, nativeRect.Right - nativeRect.Left, nativeRect.Bottom - nativeRect.Top),
            new System.Windows.Point(x, y));
        if (hit != Win32.HtClient)
        {
            handled = true;
            return new IntPtr(hit);
        }

        return IntPtr.Zero;
    }
}
