using System.Runtime.InteropServices;
using System.Windows;
using GhostPin.Windows.Core.Settings;

namespace GhostPin.Windows.App.Platform;

public sealed record MonitorDescriptor(string Id, Rect WorkArea, uint Dpi, bool IsPrimary = false)
{
    public double Scale => Math.Max(Dpi, 1) / 96.0;
}

/// <summary>在物理屏幕坐标与每显示器 DPI 逻辑布局之间转换。</summary>
public sealed class WindowPlacementService
{
    public const double MinimumLogicalWidth = 310;
    public const double MinimumLogicalHeight = 300;

    public IReadOnlyList<MonitorDescriptor> GetMonitors(IntPtr referenceWindow = default)
    {
        var screens = System.Windows.Forms.Screen.AllScreens;
        var result = new List<MonitorDescriptor>(screens.Length);
        foreach (var screen in screens)
        {
            var workArea = screen.WorkingArea;
            var monitor = Win32.MonitorFromPoint(
                new Win32.PointNative(workArea.Left + 1, workArea.Top + 1),
                Win32.MonitorDefaultToNearest);
            var dpi = referenceWindow != IntPtr.Zero && string.Equals(screen.DeviceName, GetDeviceName(monitor), StringComparison.OrdinalIgnoreCase)
                ? Win32.GetDpiForWindow(referenceWindow)
                : GetMonitorDpi(monitor);
            result.Add(new MonitorDescriptor(
                screen.DeviceName,
                new Rect(workArea.Left, workArea.Top, workArea.Width, workArea.Height),
                dpi == 0 ? 96u : dpi,
                screen.Primary));
        }

        return result;
    }

    public WindowPlacement Capture(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !Win32.GetWindowRect(hwnd, out var nativeRect))
        {
            return WindowPlacement.Default;
        }

        var monitorHandle = Win32.MonitorFromWindow(hwnd, Win32.MonitorDefaultToPrimary);
        var monitorInfo = Win32.MonitorInfo.Create();
        if (monitorHandle == IntPtr.Zero || !Win32.GetMonitorInfo(monitorHandle, ref monitorInfo))
        {
            return WindowPlacement.Default;
        }

        var dpi = Win32.GetDpiForWindow(hwnd);
        var scale = (dpi == 0 ? 96u : dpi) / 96.0;
        var work = monitorInfo.Work;
        return new WindowPlacement
        {
            MonitorId = monitorInfo.Device.TrimEnd('\0'),
            RelativeX = (nativeRect.Left - work.Left) / scale,
            RelativeY = (nativeRect.Top - work.Top) / scale,
            LogicalWidth = Math.Max(MinimumLogicalWidth, (nativeRect.Right - nativeRect.Left) / scale),
            LogicalHeight = Math.Max(MinimumLogicalHeight, (nativeRect.Bottom - nativeRect.Top) / scale),
            Dpi = dpi == 0 ? 96u : dpi
        };
    }

    public Rect Restore(WindowPlacement placement, IReadOnlyList<MonitorDescriptor> monitors)
    {
        ArgumentNullException.ThrowIfNull(placement);
        ArgumentNullException.ThrowIfNull(monitors);
        var workAreas = monitors
            .Select(monitor => new WindowWorkArea(
                monitor.Id,
                monitor.WorkArea.Left,
                monitor.WorkArea.Top,
                monitor.WorkArea.Width,
                monitor.WorkArea.Height,
                monitor.Dpi,
                monitor.IsPrimary))
            .ToArray();
        var restored = WindowPlacementCalculator.Restore(placement, workAreas);
        return new Rect(restored.Left, restored.Top, restored.Width, restored.Height);
    }

    public static Rect LimitToWorkArea(Rect candidate, Rect workArea, double minimumWidth = MinimumLogicalWidth, double minimumHeight = MinimumLogicalHeight)
    {
        var width = Math.Clamp(candidate.Width, Math.Min(minimumWidth, workArea.Width), workArea.Width);
        var height = Math.Clamp(candidate.Height, Math.Min(minimumHeight, workArea.Height), workArea.Height);
        var x = Math.Clamp(candidate.Left, workArea.Left, workArea.Right - width);
        var y = Math.Clamp(candidate.Top, workArea.Top, workArea.Bottom - height);
        return new Rect(x, y, width, height);
    }

    public static Rect ConvertSuggestedRect(Rect physicalRect, uint oldDpi, uint newDpi)
    {
        if (oldDpi == 0 || newDpi == 0 || oldDpi == newDpi)
        {
            return physicalRect;
        }

        var scale = newDpi / (double)oldDpi;
        return new Rect(physicalRect.Left, physicalRect.Top, physicalRect.Width * scale, physicalRect.Height * scale);
    }

    private static string GetDeviceName(IntPtr monitor)
    {
        if (monitor == IntPtr.Zero)
        {
            return string.Empty;
        }

        var info = Win32.MonitorInfo.Create();
        return Win32.GetMonitorInfo(monitor, ref info) ? info.Device.TrimEnd('\0') : string.Empty;
    }

    private static uint GetMonitorDpi(IntPtr monitor)
    {
        if (monitor == IntPtr.Zero)
        {
            return 96;
        }

        try
        {
            return GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 && dpiX > 0 ? dpiX : 96;
        }
        catch (DllNotFoundException)
        {
            return 96;
        }
        catch (EntryPointNotFoundException)
        {
            return 96;
        }
    }

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hMonitor, uint dpiType, out uint dpiX, out uint dpiY);
}
