namespace GameAudioManager.Core.Configuration;

/// <summary>
/// One application's routing rule.
/// </summary>
/// <remarks>
/// <see cref="OutputDeviceIds"/> is ordered: the first id that is currently active
/// wins. Device ids (not names) are stored because a name can be edited by the user
/// and is not unique across endpoints.
/// </remarks>
public sealed class AppRule
{
    public string Name { get; set; } = string.Empty;

    public string ProcessName { get; set; } = string.Empty;

    public List<string> OutputDeviceIds { get; set; } = new();

    public bool Enabled { get; set; } = true;

    /// <summary>When false the watcher leaves this app alone and only the UI acts on it.</summary>
    public bool AutoApply { get; set; } = true;
}

public sealed class AppSettings
{
    public int WatchIntervalSeconds { get; set; } = 5;

    public bool AutoStartWatcher { get; set; }

    public bool StartMinimized { get; set; }

    public bool AutoStartWithWindows { get; set; }

    /// <summary>"light", "dark" or "system". Unknown values fall back to system.</summary>
    public string Theme { get; set; } = ThemeNames.System;

    /// <summary>"ja", "en", or empty to follow the OS UI language.</summary>
    public string Language { get; set; } = string.Empty;

    public List<AppRule> Rules { get; set; } = new();
}

/// <summary>Supported theme identifiers, kept as constants so a typo cannot silently change the UI.</summary>
public static class ThemeNames
{
    public const string Light = "light";
    public const string Dark = "dark";

    /// <summary>Follow the Windows app theme.</summary>
    public const string System = "system";

    public static string Normalize(string? value)
    {
        if (string.Equals(value, Dark, StringComparison.OrdinalIgnoreCase))
        {
            return Dark;
        }

        if (string.Equals(value, System, StringComparison.OrdinalIgnoreCase))
        {
            return System;
        }

        return Light;
    }
}

