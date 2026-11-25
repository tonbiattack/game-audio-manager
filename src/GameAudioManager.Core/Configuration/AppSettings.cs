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

    public List<AppRule> Rules { get; set; } = new();
}
