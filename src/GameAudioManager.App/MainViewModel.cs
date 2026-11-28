using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Data;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;
using GameAudioManager.Core.Startup;
using GameAudioManager.Core.Watching;

namespace GameAudioManager.App;

/// <summary>
/// Main screen state.
/// </summary>
/// <remarks>
/// The list is built from configured rules plus every running process that owns a
/// visible window, so controlling an app that was never configured needs no file
/// editing. Cycle work runs on the watcher's timer thread and is marshalled back to
/// the dispatcher, so the UI never blocks on COM.
/// </remarks>
public sealed class MainViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IAudioDeviceService _devices;
    private readonly IAudioSessionService _sessions;
    private readonly IAppRoutingService _routing;
    private readonly SettingsStore _store;
    private readonly IStartupRegistration _startupRegistration;
    private readonly WatcherService _watcher;
    private readonly Dispatcher _dispatcher;

    private AppRow? _selectedApp;
    private AudioDevice? _selectedDevice;
    private string _filterText = string.Empty;
    private bool _showNotRunning = true;
    private string _statusMessage = "準備中…";
    private bool _isBusy;

    public MainViewModel(
        IAudioDeviceService devices,
        IAudioSessionService sessions,
        IAppRoutingService routing,
        SettingsStore store,
        IStartupRegistration startupRegistration)
    {
        _devices = devices;
        _sessions = sessions;
        _routing = routing;
        _store = store;
        _startupRegistration = startupRegistration ?? throw new ArgumentNullException(nameof(startupRegistration));
        _dispatcher = Dispatcher.CurrentDispatcher;

        Settings = _store.Load();
        _watcher = new WatcherService(devices, new SessionQuery(sessions), routing, Settings);
        _watcher.StatusUpdated += OnStatusUpdated;
        _watcher.CycleFailed += OnCycleFailed;

        AppsView = CollectionViewSource.GetDefaultView(Apps);
        AppsView.Filter = FilterRow;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<AppRow> Apps { get; } = new();

    /// <summary>Filtered view the list is bound to.</summary>
    public ICollectionView AppsView { get; }

    public ObservableCollection<AudioDevice> Devices { get; } = new();

    public ObservableCollection<string> PriorityDeviceNames { get; } = new();

    public AppSettings Settings { get; }

    public string SettingsPath => _store.Path;

    public AppRow? SelectedApp
    {
        get => _selectedApp;
        set
        {
            if (Set(ref _selectedApp, value))
            {
                RebuildPriorityList();
                OnPropertyChanged(nameof(CanActOnSelection));
                OnPropertyChanged(nameof(SelectedAppSummary));
            }
        }
    }

    public AudioDevice? SelectedDevice
    {
        get => _selectedDevice;
        set
        {
            if (Set(ref _selectedDevice, value))
            {
                OnPropertyChanged(nameof(CanActOnSelection));
            }
        }
    }

    public string FilterText
    {
        get => _filterText;
        set
        {
            if (Set(ref _filterText, value))
            {
                AppsView.Refresh();
            }
        }
    }

    private bool FilterRow(object item)
    {
        if (item is not AppRow row)
        {
            return false;
        }

        if (!ShowNotRunning && !row.Status.IsRunning)
        {
            return false;
        }

        return row.Matches(FilterText);
    }

    public bool ShowNotRunning
    {
        get => _showNotRunning;
        set
        {
            if (Set(ref _showNotRunning, value))
            {
                AppsView.Refresh();
            }
        }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        private set => Set(ref _statusMessage, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => Set(ref _isBusy, value);
    }

    public bool CanActOnSelection => _selectedApp is { Status.IsRunning: true } && !IsBusy;

    public bool AutoStartWithWindows
    {
        get => Settings.AutoStartWithWindows;
        set
        {
            if (Settings.AutoStartWithWindows == value)
            {
                return;
            }

            Settings.AutoStartWithWindows = value;
            OnPropertyChanged(nameof(AutoStartWithWindows));
            SaveSettings();
            _ = ApplyAutoStartAsync(value);
        }
    }

    public bool WatcherRunning => _watcher.IsRunning;

    /// <summary>Applies and persists a theme choice ("light", "dark" or "system").</summary>
    public void SetTheme(string theme)
    {
        var normalized = ThemeNames.Normalize(theme);
        if (string.Equals(Settings.Theme, normalized, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        Settings.Theme = normalized;
        ThemeManager.Apply(normalized);
        SaveSettings();
        StatusMessage = normalized switch
        {
            ThemeNames.Dark => Localization.Instance["StatusThemeDark"],
            ThemeNames.Light => Localization.Instance["StatusThemeLight"],
            _ => Localization.Instance["StatusThemeSystem"],
        };
    }

    /// <summary>True when the UI is currently Japanese.</summary>
    public bool IsJapanese => Localization.Instance.IsJapanese;

    /// <summary>Switches the UI language and persists it.</summary>
    public void SetLanguage(string language)
    {
        var normalized = string.Equals(language, Localization.Japanese, StringComparison.OrdinalIgnoreCase)
            ? Localization.Japanese
            : Localization.English;

        Settings.Language = normalized;
        Localization.Instance.Language = normalized;
        SaveSettings();
        OnPropertyChanged(nameof(IsJapanese));
        StatusMessage = Localization.Instance["StatusLanguageChanged"];
        RefreshFromWatcher();
    }

    /// <summary>Re-renders the rows so localized text is refreshed.</summary>
    public void RefreshRows() => RefreshFromWatcher();

    /// <summary>
    /// Called when the OS reports a device or power change. Re-runs the watcher so a
    /// reconnected headset or a resume from sleep is picked up immediately instead of
    /// at the next poll.
    /// </summary>
    public void OnExternalChange()
    {
        _dispatcher.BeginInvoke(() =>
        {
            _watcher.TriggerNow();
            RefreshFromWatcher();
        });
    }

    public string SelectedAppSummary => _selectedApp is null
        ? string.Empty
        : $"{_selectedApp.DisplayName}: {_selectedApp.StateText} / ミュート {_selectedApp.MuteText}";

    public void Initialize()
    {
        MergeDevices(_devices.GetRenderDevices());

        if (Settings.AutoStartWatcher || Settings.Rules.Count > 0)
        {
            _watcher.Start();
        }
        else
        {
            _watcher.TriggerNow();
        }

        OnPropertyChanged(nameof(WatcherRunning));
        RefreshFromWatcher();
        StatusMessage = Localization.Instance[_watcher.IsRunning ? "StatusRunning" : "StatusStopped"];
    }

    public void ToggleWatcher()
    {
        if (_watcher.IsRunning)
        {
            _watcher.Stop();
            StatusMessage = Localization.Instance["StatusAutoStopped"];
        }
        else
        {
            _watcher.Start();
            StatusMessage = Localization.Instance["StatusAutoStarted"];
        }

        OnPropertyChanged(nameof(WatcherRunning));
    }

    public async Task RefreshAsync()
    {
        if (IsBusy)
        {
            return;
        }

        IsBusy = true;
        try
        {
            var devices = await Task.Run(() => _devices.GetRenderDevices()).ConfigureAwait(true);
            MergeDevices(devices);
            _watcher.TriggerNow();
            StatusMessage = $"更新: {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            StatusMessage = Localization.Instance.Format("StatusRefreshFailed", ex.Message);
        }
        finally
        {
            IsBusy = false;
        }
    }

    public async Task ApplySelectedDeviceAsync()
    {
        if (SelectedApp is null || SelectedDevice is null)
        {
            return;
        }

        await RunActionAsync(() =>
        {
            var app = SelectedApp;
            var device = SelectedDevice;

            // The rule list is the source of truth, and the watcher applies it when the
            // process is seen. Recording it first means a not-yet-started app is handled
            // as soon as it starts.
            var rule = EnsureRule(app);
            rule.OutputDeviceIds.Clear();
            rule.OutputDeviceIds.Add(device.Id);
            SaveSettings();
            RebuildPriorityList();

            var result = _routing.SetPreferredDevice(app.ProcessName, device.Id);
            StatusMessage = result.Recorded
                ? $"{app.DisplayName} → {device.Name}。{result.Message}"
                : result.Message;

            _watcher.UpdateSettings(Settings);
            _watcher.TriggerNow();
            return Task.CompletedTask;
        }).ConfigureAwait(true);
    }

    public async Task ResetSelectedAsync()
    {
        if (SelectedApp is null)
        {
            return;
        }

        await RunActionAsync(() =>
        {
            var app = SelectedApp;
            var rule = EnsureRule(app);
            rule.OutputDeviceIds.Clear();
            SaveSettings();
            RebuildPriorityList();

            var result = _routing.ResetToDefault(app.ProcessName);
            StatusMessage = result.Message;
            _watcher.UpdateSettings(Settings);
            _watcher.TriggerNow();
            return Task.CompletedTask;
        }).ConfigureAwait(true);
    }

    public async Task ToggleMuteAsync()
    {
        if (SelectedApp is null)
        {
            return;
        }

        if (!SelectedApp.Status.Mute.HasSession)
        {
            StatusMessage = Localization.Instance.Format("StatusNoSession", SelectedApp.DisplayName);
            return;
        }

        await RunActionAsync(() =>
        {
            var app = SelectedApp;
            var sessions = _sessions.GetSessions(app.ProcessName);
            if (sessions.Count == 0)
            {
                return Task.CompletedTask;
            }

            // Same rule as the CLI: any unmuted session means mute them all.
            var anyUnmuted = sessions.Any(s => !s.IsMuted);
            var changed = _sessions.SetMute(app.ProcessName, anyUnmuted);
            StatusMessage = changed > 0
                ? Localization.Instance.Format(anyUnmuted ? "StatusMuted" : "StatusUnmuted", app.DisplayName)
                : Localization.Instance.Format("StatusMuteFailed", app.DisplayName);

            _watcher.TriggerNow();
            return Task.CompletedTask;
        }).ConfigureAwait(true);
    }

    /// <summary>Turns automatic applying on or off for one row and persists it.</summary>
    public void SetAutoApply(AppRow row, bool enabled)
    {
        if (row is null)
        {
            return;
        }

        var rule = EnsureRule(row);
        rule.AutoApply = enabled;
        row.AutoApply = enabled ? 1 : 0;
        SaveSettings();
        _watcher.UpdateSettings(Settings);
        StatusMessage = Localization.Instance.Format(enabled ? "StatusAutoApplyOn" : "StatusAutoApplyOff", row.DisplayName);
    }

    public void AddPriorityDevice()
    {
        if (SelectedApp is null || SelectedDevice is null)
        {
            return;
        }

        var rule = EnsureRule(SelectedApp);
        var updated = DevicePriority.Add(rule.OutputDeviceIds, SelectedDevice.Id);
        rule.OutputDeviceIds.Clear();
        rule.OutputDeviceIds.AddRange(updated);
        SaveSettings();
        RebuildPriorityList();
        _watcher.UpdateSettings(Settings);
    }

    public void RemovePriorityDeviceAt(int index)
    {
        if (SelectedApp is null || index < 0)
        {
            return;
        }

        var rule = EnsureRule(SelectedApp);
        if (index >= rule.OutputDeviceIds.Count)
        {
            return;
        }

        var updated = DevicePriority.Remove(rule.OutputDeviceIds, rule.OutputDeviceIds[index]);
        rule.OutputDeviceIds.Clear();
        rule.OutputDeviceIds.AddRange(updated);
        SaveSettings();
        RebuildPriorityList();
        _watcher.UpdateSettings(Settings);
    }

    public void MovePriorityDeviceAt(int index, int offset)
    {
        if (SelectedApp is null || index < 0)
        {
            return;
        }

        var rule = EnsureRule(SelectedApp);
        if (index >= rule.OutputDeviceIds.Count)
        {
            return;
        }

        var updated = DevicePriority.Move(rule.OutputDeviceIds, index, offset);
        rule.OutputDeviceIds.Clear();
        rule.OutputDeviceIds.AddRange(updated);
        SaveSettings();
        RebuildPriorityList();
        _watcher.UpdateSettings(Settings);
    }

    public void SaveSettings()
    {
        try
        {
            _store.Save(Settings);
        }
        catch (Exception ex)
        {
            StatusMessage = Localization.Instance.Format("StatusSaveFailed", ex.Message);
        }
    }

    public void Dispose()
    {
        _watcher.StatusUpdated -= OnStatusUpdated;
        _watcher.CycleFailed -= OnCycleFailed;
        _watcher.Dispose();
    }

    /// <summary>
    /// Syncs the stored autostart flag with what the OS actually has, once at startup.
    /// </summary>
    /// <remarks>
    /// The user can turn the entry off from Task Manager without opening the app, so the
    /// checkbox must not keep claiming a state Windows no longer holds. Failures are
    /// reported but never block startup.
    /// </remarks>
    public void InitializeAutoStart() => _ = ReconcileAutoStartAsync();

    private async Task ReconcileAutoStartAsync()
    {
        try
        {
            var status = await _startupRegistration.GetStatusAsync();
            if (status.State == StartupRegistrationState.Unavailable)
            {
                // No usable mechanism on this channel; keep the stored preference rather
                // than silently clearing it.
                return;
            }

            // Correct the checkbox silently. The watcher owns the status line at startup,
            // and a "blocked" notice written here would be overwritten by it; the notice is
            // shown when the user actually tries to enable the entry.
            if (status.IsEnabled != Settings.AutoStartWithWindows)
            {
                Settings.AutoStartWithWindows = status.IsEnabled;
                OnPropertyChanged(nameof(AutoStartWithWindows));
                SaveSettings();
            }
        }
        catch (Exception ex)
        {
            StatusMessage = Localization.Instance.Format("StatusAutoStartFailed", ex.Message);
        }
    }

    private async Task ApplyAutoStartAsync(bool enabled)
    {
        try
        {
            var status = await _startupRegistration.SetEnabledAsync(enabled);
            if (status.IsEnabled == enabled)
            {
                StatusMessage = Localization.Instance[enabled ? "StatusAutoStartOn" : "StatusAutoStartOff"];
                return;
            }

            // The OS refused the change (or the channel has no mechanism). Show what it
            // actually applied instead of leaving the checkbox out of sync.
            Settings.AutoStartWithWindows = status.IsEnabled;
            OnPropertyChanged(nameof(AutoStartWithWindows));
            SaveSettings();
            StatusMessage = status.State switch
            {
                StartupRegistrationState.DisabledByUser => Localization.Instance["StatusAutoStartBlockedByUser"],
                _ => Localization.Instance.Format("StatusAutoStartFailed", status.Detail ?? status.State.ToString()),
            };
        }
        catch (Exception ex)
        {
            Settings.AutoStartWithWindows = !enabled;
            OnPropertyChanged(nameof(AutoStartWithWindows));
            SaveSettings();
            StatusMessage = Localization.Instance.Format("StatusAutoStartFailed", ex.Message);
        }
    }

    private void OnStatusUpdated(object? sender, IReadOnlyList<RoutingStatus> statuses)
    {
        _dispatcher.BeginInvoke(() => ApplyStatuses(statuses));
    }

    private void OnCycleFailed(object? sender, string message)
    {
        _dispatcher.BeginInvoke(() => StatusMessage = Localization.Instance.Format("StatusWatchCycleFailed", message));
    }

    private void RefreshFromWatcher()
    {
        ApplyStatuses(_watcher.BuildStatuses());
    }

    private void ApplyStatuses(IReadOnlyList<RoutingStatus> statuses)
    {
        var byProcess = statuses.ToDictionary(s => s.ProcessName, StringComparer.OrdinalIgnoreCase);
        var running = GetRunningProcessNames();

        foreach (var row in Apps.ToList())
        {
            if (byProcess.TryGetValue(row.ProcessName, out var status))
            {
                row.Update(status, row.Rule);
                continue;
            }

            // A discovered app with no rule: refresh its running flag only.
            var isRunning = running.Contains(row.ProcessName);
            row.Update(row.Status with { IsRunning = isRunning, State = isRunning ? RoutingState.NotConfigured : RoutingState.NotRunning }, row.Rule);
        }

        // Add rules that are not in the list yet.
        foreach (var status in statuses)
        {
            if (Apps.Any(a => string.Equals(a.ProcessName, status.ProcessName, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            var rule = FindRule(status.ProcessName);
            Apps.Add(new AppRow(status, rule));
        }

        // Add running apps that have no rule, so they can be configured without JSON.
        foreach (var name in running)
        {
            if (Apps.Any(a => string.Equals(a.ProcessName, name, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            var status = new RoutingStatus(
                name, name, true, RoutingState.NotConfigured, null, null, null, ReadMute(name), null);
            Apps.Add(new AppRow(status, null));
        }

        SelectedApp ??= Apps.FirstOrDefault();
    }

    private AppRule EnsureRule(AppRow row)
    {
        var existing = FindRule(row.ProcessName);
        if (existing is not null)
        {
            return existing;
        }

        var rule = new AppRule { Name = row.DisplayName, ProcessName = row.ProcessName };
        Settings.Rules.Add(rule);
        return rule;
    }

    private AppRule? FindRule(string processName)
    {
        return Settings.Rules.FirstOrDefault(r =>
            string.Equals(
                Path.GetFileNameWithoutExtension(r.ProcessName),
                Path.GetFileNameWithoutExtension(processName),
                StringComparison.OrdinalIgnoreCase));
    }

    private void RebuildPriorityList()
    {
        PriorityDeviceNames.Clear();
        var rule = _selectedApp is null ? null : FindRule(_selectedApp.ProcessName);
        if (rule is null)
        {
            return;
        }

        foreach (var id in rule.OutputDeviceIds)
        {
            var name = Devices.FirstOrDefault(d => string.Equals(d.Id, id, StringComparison.OrdinalIgnoreCase))?.Name
                ?? _devices.GetRenderDevices().FirstOrDefault(d => string.Equals(d.Id, id, StringComparison.OrdinalIgnoreCase))?.Name
                ?? "(未接続)";
            PriorityDeviceNames.Add(name);
        }
    }

    private MuteState ReadMute(string processName)
    {
        try
        {
            var summary = new SessionQuery(_sessions).GetMuteSummary(processName);
            if (!summary.HasSession)
            {
                return MuteState.None;
            }

            return new MuteState(
                true,
                summary.MutedCount == summary.SessionCount,
                summary.MutedCount > 0 && summary.MutedCount < summary.SessionCount,
                summary.SessionCount,
                summary.EndpointCount);
        }
        catch (Exception)
        {
            return MuteState.None;
        }
    }

    private static HashSet<string> GetRunningProcessNames()
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (string.IsNullOrWhiteSpace(process.MainWindowTitle) || ShellHosts.Contains(process.ProcessName))
                {
                    continue;
                }

                names.Add(process.ProcessName);
            }
            catch (InvalidOperationException)
            {
                // Process exited while enumerating.
            }
            finally
            {
                process.Dispose();
            }
        }

        return names;
    }

    /// <summary>
    /// Windows shell hosts that own a window title but are not applications the user
    /// controls audio for.
    /// </summary>
    private static readonly HashSet<string> ShellHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "ApplicationFrameHost",
        "TextInputHost",
        "ShellExperienceHost",
        "SearchHost",
        "StartMenuExperienceHost",
        "LockApp",
        "Widgets",
        "WidgetService",
        "GameAudioManager",
    };

    private void MergeDevices(IReadOnlyList<AudioDevice> devices)
    {
        var currentId = SelectedDevice?.Id;
        Devices.Clear();
        foreach (var device in devices.Where(d => d.IsActive))
        {
            Devices.Add(device);
        }

        SelectedDevice = Devices.FirstOrDefault(d => string.Equals(d.Id, currentId, StringComparison.OrdinalIgnoreCase))
            ?? Devices.FirstOrDefault(d => d.IsDefault)
            ?? Devices.FirstOrDefault();
    }

    private async Task RunActionAsync(Func<Task> action)
    {
        if (IsBusy)
        {
            return;
        }

        IsBusy = true;
        try
        {
            await action().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            StatusMessage = Localization.Instance.Format("StatusActionFailed", ex.Message);
        }
        finally
        {
            IsBusy = false;
        }
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(name);
        return true;
    }

    private void OnPropertyChanged(string? name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}












