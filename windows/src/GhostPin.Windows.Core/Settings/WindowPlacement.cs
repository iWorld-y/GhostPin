namespace GhostPin.Windows.Core.Settings;

/// <summary>以显示器工作区和 DPI 为基准保存的逻辑窗口布局。</summary>
public sealed record class WindowPlacement
{
    public string? MonitorId { get; set; }
    public double RelativeX { get; set; }
    public double RelativeY { get; set; }
    public double LogicalWidth { get; set; } = 360;
    public double LogicalHeight { get; set; } = 520;
    public uint Dpi { get; set; } = 96;

    public static WindowPlacement Default => new();
}
