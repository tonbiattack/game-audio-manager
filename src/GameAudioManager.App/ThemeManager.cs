using System.Windows;
using System.Windows.Media;

namespace GameAudioManager.App;

/// <summary>
/// Light and dark palettes.
/// </summary>
/// <remarks>
/// Applied by replacing brush values in the application resources, so every control
/// that uses <c>DynamicResource</c> updates without rebuilding the window.
/// </remarks>
public static class ThemeManager
{
    public const string BackgroundKey = "AppBackgroundBrush";
    public const string ForegroundKey = "AppForegroundBrush";
    public const string PanelKey = "AppPanelBrush";
    public const string BorderKey = "AppBorderBrush";
    public const string SubtleKey = "AppSubtleBrush";
    public const string HeaderKey = "AppHeaderBrush";

    public static void Apply(string theme)
    {
        var dark = string.Equals(theme, GameAudioManager.Core.Configuration.ThemeNames.Dark, StringComparison.OrdinalIgnoreCase);
        var resources = System.Windows.Application.Current?.Resources;
        if (resources is null)
        {
            return;
        }

        if (dark)
        {
            Set(resources, BackgroundKey, "#1F1F1F");
            Set(resources, ForegroundKey, "#F3F3F3");
            Set(resources, PanelKey, "#2B2B2B");
            Set(resources, BorderKey, "#3F3F3F");
            Set(resources, SubtleKey, "#A0A0A0");
            Set(resources, HeaderKey, "#3A3A3A");
        }
        else
        {
            Set(resources, BackgroundKey, "#FFFFFF");
            Set(resources, ForegroundKey, "#1B1B1B");
            Set(resources, PanelKey, "#F7F7F7");
            Set(resources, BorderKey, "#C8C8C8");
            Set(resources, SubtleKey, "#606060");
            Set(resources, HeaderKey, "#ECECEC");
        }
    }

    private static void Set(System.Windows.ResourceDictionary resources, string key, string color)
    {
        var brush = new System.Windows.Media.SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(color));
        brush.Freeze();
        resources[key] = brush;
    }
}


