using GhostPin.Windows.Core.Models;

namespace GhostPin.Windows.Core.Settings;

/// <summary>与任务文件分离的 Windows HUD 偏好。</summary>
public sealed record class HudSettings
{
    public bool IsVisible { get; set; } = true;
    public HudMode Mode { get; set; } = HudMode.Passthrough;
    public double Opacity { get; set; } = 0.92;
    public bool IsTopmost { get; set; } = true;
    public HudScope Scope { get; set; } = HudScope.All;
    public int MaxItems { get; set; } = 8;
    public WindowPlacement Placement { get; set; } = WindowPlacement.Default;

    public static HudSettings Default => new();

    public HudSettings Normalize()
    {
        return this with
        {
            Opacity = double.IsFinite(Opacity) ? Math.Clamp(Opacity, 0.5, 1.0) : 0.92,
            MaxItems = Math.Clamp(MaxItems, 1, 100),
            Placement = NormalizePlacement(Placement)
        };
    }

    private static WindowPlacement NormalizePlacement(WindowPlacement? placement)
    {
        placement ??= WindowPlacement.Default;
        return new WindowPlacement
        {
            MonitorId = string.IsNullOrWhiteSpace(placement.MonitorId) ? null : placement.MonitorId,
            RelativeX = double.IsFinite(placement.RelativeX) ? placement.RelativeX : 0,
            RelativeY = double.IsFinite(placement.RelativeY) ? placement.RelativeY : 0,
            LogicalWidth = double.IsFinite(placement.LogicalWidth) ? Math.Clamp(placement.LogicalWidth, 310, 1920) : 360,
            LogicalHeight = double.IsFinite(placement.LogicalHeight) ? Math.Clamp(placement.LogicalHeight, 300, 1600) : 520,
            Dpi = placement.Dpi is >= 48 and <= 768 ? placement.Dpi : 96
        };
    }
}
