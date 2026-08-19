using System.Text.Json;
using GhostPin.Windows.Core.Models;

namespace GhostPin.Windows.Core.Settings;

/// <summary>逐字段校验 HUD 设置，损坏项回退安全默认值。</summary>
public static class HudSettingsCodec
{
    public static HudSettings Deserialize(string json)
    {
        using var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException("HUD 设置必须是 JSON 对象。");
        }

        var defaults = HudSettings.Default;
        var root = document.RootElement;
        var settings = new HudSettings
        {
            IsVisible = ReadBoolean(root, "isVisible", defaults.IsVisible),
            Mode = ReadMode(root, defaults.Mode),
            Opacity = ReadOpacity(root, defaults.Opacity),
            IsTopmost = ReadBoolean(root, "isTopmost", defaults.IsTopmost),
            Scope = ReadScope(root, defaults.Scope),
            MaxItems = ReadMaxItems(root, defaults.MaxItems),
            Placement = ReadPlacement(root, defaults.Placement)
        };
        return settings.Normalize();
    }

    public static string Serialize(HudSettings settings)
    {
        settings = (settings ?? HudSettings.Default).Normalize();
        var options = new JsonWriterOptions { Indented = true };
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, options))
        {
            writer.WriteStartObject();
            writer.WriteBoolean("isVisible", settings.IsVisible);
            writer.WriteString("mode", ToWire(settings.Mode));
            writer.WriteNumber("opacity", settings.Opacity);
            writer.WriteBoolean("isTopmost", settings.IsTopmost);
            writer.WriteString("scope", ToWire(settings.Scope));
            writer.WriteNumber("maxItems", settings.MaxItems);
            writer.WritePropertyName("placement");
            WritePlacement(writer, settings.Placement);
            writer.WriteEndObject();
        }
        return System.Text.Encoding.UTF8.GetString(stream.ToArray());
    }

    private static bool ReadBoolean(JsonElement root, string name, bool fallback)
    {
        if (!root.TryGetProperty(name, out var value))
        {
            return fallback;
        }

        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => fallback
        };
    }

    private static double ReadOpacity(JsonElement root, double fallback)
    {
        if (root.TryGetProperty("opacity", out var value) && value.ValueKind == JsonValueKind.Number &&
            value.TryGetDouble(out var opacity) && double.IsFinite(opacity) && opacity is >= 0.5 and <= 1.0)
        {
            return opacity;
        }

        return fallback;
    }

    private static int ReadMaxItems(JsonElement root, int fallback)
    {
        if (root.TryGetProperty("maxItems", out var value) && value.ValueKind == JsonValueKind.Number &&
            value.TryGetInt32(out var maxItems) && maxItems is >= 1 and <= 100)
        {
            return maxItems;
        }

        return fallback;
    }

    private static HudMode ReadMode(JsonElement root, HudMode fallback)
    {
        if (!root.TryGetProperty("mode", out var value) || value.ValueKind != JsonValueKind.String)
        {
            return fallback;
        }

        return value.GetString()?.ToLowerInvariant() switch
        {
            "passthrough" => HudMode.Passthrough,
            "interactive" => HudMode.Interactive,
            _ => fallback
        };
    }

    private static HudScope ReadScope(JsonElement root, HudScope fallback)
    {
        if (!root.TryGetProperty("scope", out var value) || value.ValueKind != JsonValueKind.String)
        {
            return fallback;
        }

        return value.GetString()?.ToLowerInvariant() switch
        {
            "all" => HudScope.All,
            "today" => HudScope.Today,
            _ => fallback
        };
    }

    private static WindowPlacement ReadPlacement(JsonElement root, WindowPlacement fallback)
    {
        if (!root.TryGetProperty("placement", out var value) || value.ValueKind != JsonValueKind.Object)
        {
            return WindowPlacement.Default;
        }

        return new WindowPlacement
        {
            MonitorId = ReadNullableString(value, "monitorId", fallback.MonitorId),
            RelativeX = ReadFiniteDouble(value, "relativeX", fallback.RelativeX),
            RelativeY = ReadFiniteDouble(value, "relativeY", fallback.RelativeY),
            LogicalWidth = ReadBoundedDouble(value, "logicalWidth", 310, 1920, fallback.LogicalWidth),
            LogicalHeight = ReadBoundedDouble(value, "logicalHeight", 300, 1600, fallback.LogicalHeight),
            Dpi = ReadDpi(value, fallback.Dpi)
        };
    }

    private static void WritePlacement(Utf8JsonWriter writer, WindowPlacement placement)
    {
        writer.WriteStartObject();
        if (placement.MonitorId is null) writer.WriteNull("monitorId"); else writer.WriteString("monitorId", placement.MonitorId);
        writer.WriteNumber("relativeX", placement.RelativeX);
        writer.WriteNumber("relativeY", placement.RelativeY);
        writer.WriteNumber("logicalWidth", placement.LogicalWidth);
        writer.WriteNumber("logicalHeight", placement.LogicalHeight);
        writer.WriteNumber("dpi", placement.Dpi);
        writer.WriteEndObject();
    }

    private static string? ReadNullableString(JsonElement root, string name, string? fallback)
    {
        return root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : fallback;
    }

    private static double ReadFiniteDouble(JsonElement root, string name, double fallback)
    {
        return root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number) && double.IsFinite(number)
            ? number
            : fallback;
    }

    private static double ReadBoundedDouble(JsonElement root, string name, double minimum, double maximum, double fallback)
    {
        var value = ReadFiniteDouble(root, name, fallback);
        return value >= minimum && value <= maximum ? value : fallback;
    }

    private static uint ReadDpi(JsonElement root, uint fallback)
    {
        if (root.TryGetProperty("dpi", out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetUInt32(out var dpi) && dpi is >= 48 and <= 768)
        {
            return dpi;
        }

        return fallback;
    }

    private static string ToWire(HudMode mode) => mode switch
    {
        HudMode.Passthrough => "passthrough",
        HudMode.Interactive => "interactive",
        _ => "passthrough"
    };

    private static string ToWire(HudScope scope) => scope switch
    {
        HudScope.All => "all",
        HudScope.Today => "today",
        _ => "all"
    };
}
