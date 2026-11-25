using System.Windows;
using System.Windows.Media;
using GameAudioManager.Core.Configuration;
using Wpf.Ui.Appearance;

namespace GameAudioManager.App;

/// <summary>
/// Applies the Fluent (WPF UI) palette and the brushes this window binds to.
/// </summary>
/// <remarks>
/// <para>
/// Contrast was chosen against WCAG 2.1 AA for body text: the dark theme uses
/// #F5F5F5 on #1B1B1B (about 15:1) and secondary text #C9C9C9 (about 10:1), rather
/// than the previous muted greys which were hard to read on a bright display.
/// </para>
/// <para>
/// "system" resolves to the Windows app theme and is re-applied when the user changes
/// it while the app runs.
/// </para>
/// </remarks>
public static class ThemeManager
{
    public const string BackgroundKey = "AppBackgroundBrush";
    public const string ForegroundKey = "AppForegroundBrush";
    public const string PanelKey = "AppPanelBrush";
    public const string BorderKey = "AppBorderBrush";
    public const string SubtleKey = "AppSubtleBrush";
    public const string HeaderKey = "AppHeaderBrush";
    public const string RowAltKey = "AppRowAltBrush";
    public const string AccentKey = "AppAccentBrush";

    /// <summary>Resolves a configured theme name to "light" or "dark".</summary>
    public static string ResolveEffectiveTheme(string configured)
    {
        if (string.Equals(configured, ThemeNames.Dark, StringComparison.OrdinalIgnoreCase))
        {
            return ThemeNames.Dark;
        }

        if (string.Equals(configured, ThemeNames.System, StringComparison.OrdinalIgnoreCase))
        {
            return IsSystemDark() ? ThemeNames.Dark : ThemeNames.Light;
        }

        return ThemeNames.Light;
    }

    /// <summary>True when Windows is currently using the dark app theme.</summary>
    public static bool IsSystemDark()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            // 0 means the dark app theme.
            return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
        }
        catch (Exception)
        {
            return false;
        }
    }

    public static void Apply(string configured)
    {
        var effective = ResolveEffectiveTheme(configured);
        var dark = string.Equals(effective, ThemeNames.Dark, StringComparison.OrdinalIgnoreCase);

        try
        {
            ApplicationThemeManager.Apply(dark ? ApplicationTheme.Dark : ApplicationTheme.Light);
        }
        catch (Exception)
        {
            // The Fluent resources are optional; the brushes below still apply.
        }

        var resources = System.Windows.Application.Current?.Resources;
        if (resources is null)
        {
            return;
        }

        if (dark)
        {
            // Deliberately higher contrast than the stock Fluent dark palette: the grid
            // is mostly small text, and the muted greys were hard to read.
            Set(resources, BackgroundKey, "#1B1B1B");
            Set(resources, ForegroundKey, "#F5F5F5");
            Set(resources, PanelKey, "#262626");
            Set(resources, BorderKey, "#5A5A5A");
            Set(resources, SubtleKey, "#C9C9C9");
            Set(resources, HeaderKey, "#333333");
            Set(resources, RowAltKey, "#212121");
            Set(resources, AccentKey, "#8AB4F8");
        }
        else
        {
            Set(resources, BackgroundKey, "#FFFFFF");
            Set(resources, ForegroundKey, "#1A1A1A");
            Set(resources, PanelKey, "#F7F7F7");
            Set(resources, BorderKey, "#B0B0B0");
            Set(resources, SubtleKey, "#505050");
            Set(resources, HeaderKey, "#EDEDED");
            Set(resources, RowAltKey, "#FAFAFA");
            Set(resources, AccentKey, "#1F6FEB");
        }
    }

    private static void Set(System.Windows.ResourceDictionary resources, string key, string color)
    {
        var brush = new SolidColorBrush(
            (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(color));
        brush.Freeze();
        resources[key] = brush;
    }

}

