using System.Windows;
using GameAudioManager.Core.Configuration;
using Wpf.Ui.Appearance;

namespace GameAudioManager.App;

/// <summary>
/// Applies the Fluent (WPF UI) palette and the small set of brushes the window binds to.
/// </summary>
/// <remarks>
/// <para>
/// <c>ApplicationThemeManager.Apply</c> restyles the standard controls. The named
/// brushes below are what this app's XAML uses directly, so they are refreshed from the
/// same choice to keep custom panels consistent with the Fluent controls.
/// </para>
/// <para>
/// "system" mode resolves to the Windows app theme and is re-applied when the user
/// changes it while the app runs.
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
            Set(resources, BackgroundKey, "#202020");
            Set(resources, ForegroundKey, "#F3F3F3");
            Set(resources, PanelKey, "#2B2B2B");
            Set(resources, BorderKey, "#3F3F3F");
            Set(resources, SubtleKey, "#B0B0B0");
            Set(resources, HeaderKey, "#333333");
        }
        else
        {
            Set(resources, BackgroundKey, "#FFFFFF");
            Set(resources, ForegroundKey, "#1B1B1B");
            Set(resources, PanelKey, "#F7F7F7");
            Set(resources, BorderKey, "#D6D6D6");
            Set(resources, SubtleKey, "#5A5A5A");
            Set(resources, HeaderKey, "#F0F0F0");
        }
    }

    private static void Set(System.Windows.ResourceDictionary resources, string key, string color)
    {
        var brush = new System.Windows.Media.SolidColorBrush(
            (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(color));
        brush.Freeze();
        resources[key] = brush;
    }
}

