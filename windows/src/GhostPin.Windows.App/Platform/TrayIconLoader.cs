using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace GhostPin.Windows.App.Platform;

/// <summary>从 WPF 图像资源创建拥有独立句柄生命周期的通知区域图标。</summary>
public static class TrayIconLoader
{
    private const int IconSize = 32;

    public static Icon Load(Uri resourceUri)
    {
        ArgumentNullException.ThrowIfNull(resourceUri);
        var resource = System.Windows.Application.GetResourceStream(resourceUri)
            ?? throw new InvalidOperationException($"找不到通知区域图标资源：{resourceUri}");

        using var stream = resource.Stream;
        using var source = new Bitmap(stream);
        using var bitmap = RenderTemplate(source, ResolveTemplateColor());
        var handle = bitmap.GetHicon();
        if (handle == IntPtr.Zero)
        {
            throw new InvalidOperationException("无法创建通知区域图标句柄。");
        }

        try
        {
            return (Icon)Icon.FromHandle(handle).Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    private static Bitmap RenderTemplate(Bitmap source, Color color)
    {
        var bitmap = new Bitmap(IconSize, IconSize, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.Transparent);
            graphics.CompositingMode = CompositingMode.SourceCopy;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.DrawImage(source, new Rectangle(0, 0, IconSize, IconSize));
        }

        for (var y = 0; y < IconSize; y++)
        {
            for (var x = 0; x < IconSize; x++)
            {
                var alpha = bitmap.GetPixel(x, y).A;
                bitmap.SetPixel(x, y, Color.FromArgb(alpha, color));
            }
        }
        return bitmap;
    }

    private static Color ResolveTemplateColor()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var usesLightTheme = key?.GetValue("SystemUsesLightTheme") is not int value || value != 0;
            return usesLightTheme ? Color.FromArgb(35, 40, 37) : Color.White;
        }
        catch (Exception error) when (error is UnauthorizedAccessException or System.Security.SecurityException)
        {
            return Color.FromArgb(35, 40, 37);
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);
}
