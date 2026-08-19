namespace GhostPin.Windows.Core.Settings;

public readonly record struct WindowRect(double Left, double Top, double Width, double Height)
{
    public double Right => Left + Width;
    public double Bottom => Top + Height;
}

public readonly record struct WindowWorkArea(
    string Id,
    double Left,
    double Top,
    double Width,
    double Height,
    uint Dpi,
    bool IsPrimary = false)
{
    public double Scale => Math.Max(Dpi, 1) / 96.0;
    public double Right => Left + Width;
    public double Bottom => Top + Height;
}

/// <summary>不依赖 WPF 的窗口布局换算，供平台层和自动化测试共同使用。</summary>
public static class WindowPlacementCalculator
{
    public static WindowRect Restore(WindowPlacement placement, IReadOnlyList<WindowWorkArea> workAreas)
    {
        ArgumentNullException.ThrowIfNull(placement);
        ArgumentNullException.ThrowIfNull(workAreas);
        if (workAreas.Count == 0)
        {
            return new WindowRect(0, 0, 310, 300);
        }

        var target = workAreas.FirstOrDefault(area => string.Equals(area.Id, placement.MonitorId, StringComparison.OrdinalIgnoreCase));
        if (string.IsNullOrEmpty(target.Id))
        {
            target = workAreas.FirstOrDefault(area => area.IsPrimary);
        }
        if (string.IsNullOrEmpty(target.Id))
        {
            target = workAreas[0];
        }
        var scale = target.Scale;
        var width = Math.Clamp(placement.LogicalWidth * scale, Math.Min(310 * scale, target.Width), target.Width);
        var height = Math.Clamp(placement.LogicalHeight * scale, Math.Min(300 * scale, target.Height), target.Height);
        var candidate = new WindowRect(
            target.Left + placement.RelativeX * scale,
            target.Top + placement.RelativeY * scale,
            width,
            height);
        return Clamp(candidate, target, Math.Min(310 * scale, target.Width), Math.Min(300 * scale, target.Height));
    }

    public static WindowPlacement Capture(WindowRect window, WindowWorkArea workArea)
    {
        var scale = workArea.Scale;
        return new WindowPlacement
        {
            MonitorId = workArea.Id,
            RelativeX = (window.Left - workArea.Left) / scale,
            RelativeY = (window.Top - workArea.Top) / scale,
            LogicalWidth = Math.Max(310, window.Width / scale),
            LogicalHeight = Math.Max(300, window.Height / scale),
            Dpi = workArea.Dpi == 0 ? 96u : workArea.Dpi
        };
    }

    public static WindowRect Clamp(WindowRect candidate, WindowWorkArea workArea, double minimumWidth = 310, double minimumHeight = 300)
    {
        var width = Math.Clamp(candidate.Width, Math.Min(minimumWidth, workArea.Width), workArea.Width);
        var height = Math.Clamp(candidate.Height, Math.Min(minimumHeight, workArea.Height), workArea.Height);
        var left = Math.Clamp(candidate.Left, workArea.Left, workArea.Right - width);
        var top = Math.Clamp(candidate.Top, workArea.Top, workArea.Bottom - height);
        return new WindowRect(left, top, width, height);
    }
}
