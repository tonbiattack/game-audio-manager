using System.Collections.ObjectModel;
using System.IO;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;

namespace GameAudioManager.App;

/// <summary>One row in the application list.</summary>
public sealed class AppRow : INotifyPropertyChanged
{
    private string? _preferredDeviceId;
    private bool _isRunning;
    private MuteState _muteState = MuteState.None;

    public AppRow(string processName, string displayName)
    {
        ProcessName = processName;
        DisplayName = displayName;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string ProcessName { get; }

    public string DisplayName { get; }

    public bool IsRunning
    {
        get => _isRunning;
        set => Set(ref _isRunning, value);
    }

    public string? PreferredDeviceId
    {
        get => _preferredDeviceId;
        set
        {
            if (Set(ref _preferredDeviceId, value))
            {
                Raise(nameof(StatusText));
            }
        }
    }

    public MuteState MuteState
    {
        get => _muteState;
        set
        {
            if (Set(ref _muteState, value))
            {
                Raise(nameof(MuteText));
                Raise(nameof(StatusText));
            }
        }
    }

    public string MuteText => MuteState switch
    {
        { HasSession: false } => "—",
        { IsMixed: true } => $"混在 ({MuteState.SessionCount})",
        { IsMuted: true } => "ミュート中",
        _ => "解除",
    };

    public string StatusText
    {
        get
        {
            if (!IsRunning)
            {
                return "未起動";
            }

            return PreferredDeviceId is null ? "既定の出力" : "設定済み";
        }
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        Raise(name);
        return true;
    }

    private void Raise(string? name) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>
/// Main screen state.
/// </summary>
/// <remarks>
/// The list is built from configured rules plus every running process that owns a
/// visible window, so the common case (control an app that was never configured)
/// needs no JSON editing. Refresh runs on a timer and never blocks the UI thread.
/// </remarks>
public sealed class MainViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly IAudioDeviceService _devices;
    private readonly IAudioSessionService _sessions;
    private readonly IAppRoutingService _routing;
    private readonly SettingsStore _store;
    private readonly DispatcherTimer _timer;
    private readonly SynchronizationContext _context;

    private AppRow? _selectedApp;
    private string _statusMessage = "準備中…";
    private AudioDevice? _selectedDevice;
    private bool _isBusy;

    public MainViewModel(
        IAudioDeviceService devices,
        IAudioSessionService sessions,
        IAppRoutingService routing,
        SettingsStore store)
    {
        _devices = devices;
        _sessions = sessions;
        _routing = routing;
        _store = store;
        _context = SynchronizationContext.Current ?? new SynchronizationContext();

        Settings = _store.Load();

        _timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(Math.Clamp(Settings.WatchIntervalSeconds, 1, 60)),
        };
        _timer.Tick += async (_, _) => await RefreshAsync().ConfigureAwait(true);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<AppRow> Apps { get; } = new();

    public ObservableCollection<AudioDevice> Devices { get; } = new();

    public AppSettings Settings { get; }

    public AppRow? SelectedApp
    {
        get => _selectedApp;
        set
        {
            if (Set(ref _selectedApp, value))
            {
                OnPropertyChanged(nameof(CanActOnSelection));
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

    public string StatusMessage
    {
        get => _statusMessage;
        private set => Set(ref _statusMessage, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set
        {
            if (Set(ref _isBusy, value))
            {
                OnPropertyChanged(nameof(CanActOnSelection));
            }
        }
    }

    public bool CanActOnSelection => !IsBusy;

    public void Start()
    {
        _timer.Start();
        _ = RefreshAsync();
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
            // Device enumeration and session reads touch COM, so keep them off the
            // dispatcher thread.
            var snapshot = await Task.Run(() => BuildSnapshot()).ConfigureAwait(true);

            MergeDevices(snapshot.Devices);
            MergeApps(snapshot.Rows);
            StatusMessage = $"更新: {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            StatusMessage = "更新に失敗しました: " + ex.Message;
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

        await RunActionAsync(async () =>
        {
            var app = SelectedApp;
            var device = SelectedDevice;
            var result = await Task.Run(() => _routing.SetPreferredDevice(app.ProcessName, device.Id)).ConfigureAwait(true);
            StatusMessage = result.Message;
            if (result.Recorded)
            {
                PersistPreferredDevice(app, device.Id);
            }
        }).ConfigureAwait(true);
    }

    public async Task ResetSelectedAsync()
    {
        if (SelectedApp is null)
        {
            return;
        }

        await RunActionAsync(async () =>
        {
            var app = SelectedApp;
            var result = await Task.Run(() => _routing.ResetToDefault(app.ProcessName)).ConfigureAwait(true);
            StatusMessage = result.Message;
            if (result.Recorded)
            {
                PersistPreferredDevice(app, null);
            }
        }).ConfigureAwait(true);
    }

    public async Task ToggleMuteAsync()
    {
        if (SelectedApp is null)
        {
            return;
        }

        if (!SelectedApp.MuteState.HasSession)
        {
            StatusMessage = $"{SelectedApp.DisplayName}: 音声セッションがありません。音声を再生してから更新してください。";
            return;
        }

        await RunActionAsync(async () =>
        {
            var app = SelectedApp;
            var desired = await Task.Run(() =>
            {
                var sessions = _sessions.GetSessions(app.ProcessName);
                if (sessions.Count == 0)
                {
                    return (bool?)null;
                }

                // Match the CLI rule: any unmuted session means mute them all.
                var anyUnmuted = sessions.Any(s => !s.IsMuted);
                var changed = _sessions.SetMute(app.ProcessName, anyUnmuted);
                return changed > 0 ? anyUnmuted : null;
            }).ConfigureAwait(true);

            if (desired is null)
            {
                StatusMessage = $"{app.DisplayName}: ミュートを変更できませんでした。";
                return;
            }

            app.MuteState = ReadMuteState(app.ProcessName);
            StatusMessage = $"{app.DisplayName}: {(desired.Value ? "ミュートしました" : "ミュートを解除しました")}";
        }).ConfigureAwait(true);
    }

    public void SaveSettings()
    {
        try
        {
            _store.Save(Settings);
            StatusMessage = "設定を保存しました: " + _store.Path;
        }
        catch (Exception ex)
        {
            StatusMessage = "設定の保存に失敗しました: " + ex.Message;
        }
    }

    public void Dispose()
    {
        _timer.Stop();
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
            StatusMessage = "操作に失敗しました: " + ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private Snapshot BuildSnapshot()
    {
        var devices = _devices.GetRenderDevices();
        var running = GetRunningProcessNames();
        var rows = new List<AppRow>();

        var configured = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rule in Settings.Rules)
        {
            var name = Path.GetFileNameWithoutExtension(rule.ProcessName);
            if (!configured.Add(name))
            {
                continue;
            }

            var row = new AppRow(name, string.IsNullOrWhiteSpace(rule.Name) ? name : rule.Name)
            {
                IsRunning = running.Contains(name),
                PreferredDeviceId = rule.OutputDeviceIds.FirstOrDefault(),
            };
            row.MuteState = row.IsRunning ? ReadMuteState(name) : MuteState.None;
            rows.Add(row);
        }

        // Running apps with a window that have no rule: discoverable without config.
        foreach (var name in running)
        {
            if (configured.Contains(name))
            {
                continue;
            }

            var row = new AppRow(name, name) { IsRunning = true };
            row.MuteState = ReadMuteState(name);
            rows.Add(row);
        }

        return new Snapshot(devices, rows.OrderBy(r => r.DisplayName, StringComparer.CurrentCultureIgnoreCase).ToList());
    }

    private MuteState ReadMuteState(string processName)
    {
        try
        {
            var sessions = _sessions.GetSessions(processName);
            if (sessions.Count == 0)
            {
                return MuteState.None;
            }

            var muted = sessions.Count(s => s.IsMuted);
            return new MuteState(
                HasSession: true,
                IsMuted: muted == sessions.Count,
                IsMixed: muted > 0 && muted < sessions.Count,
                SessionCount: sessions.Count,
                EndpointCount: sessions.Select(s => s.DeviceId).Distinct(StringComparer.OrdinalIgnoreCase).Count());
        }
        catch (Exception)
        {
            return MuteState.None;
        }
    }

    /// <summary>
    /// Windows shell hosts that own a window title of their own but are not
    /// applications the user controls audio for. Listing them only adds noise.
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
    };

    private static HashSet<string> GetRunningProcessNames()
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                // Require a visible window title: handle-only processes only add noise.
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

    private void MergeDevices(IReadOnlyList<AudioDevice> devices)
    {
        var currentId = SelectedDevice?.Id ?? Devices.FirstOrDefault(d => d.IsDefault)?.Id;
        Devices.Clear();

        // Only active endpoints are offered as a destination: routing to a
        // disconnected device would be recorded but never take effect.
        foreach (var device in devices.Where(d => d.IsActive))
        {
            Devices.Add(device);
        }

        SelectedDevice = Devices.FirstOrDefault(d => string.Equals(d.Id, currentId, StringComparison.OrdinalIgnoreCase))
            ?? Devices.FirstOrDefault(d => d.IsDefault)
            ?? Devices.FirstOrDefault();
    }

    private void MergeApps(IReadOnlyList<AppRow> rows)
    {
        var selectedName = SelectedApp?.ProcessName;
        Apps.Clear();
        foreach (var row in rows)
        {
            Apps.Add(row);
        }

        SelectedApp = Apps.FirstOrDefault(a => string.Equals(a.ProcessName, selectedName, StringComparison.OrdinalIgnoreCase))
            ?? Apps.FirstOrDefault();
    }

    private void PersistPreferredDevice(AppRow app, string? deviceId)
    {
        var rule = Settings.Rules.FirstOrDefault(r =>
            string.Equals(Path.GetFileNameWithoutExtension(r.ProcessName), app.ProcessName, StringComparison.OrdinalIgnoreCase));

        if (rule is null)
        {
            rule = new AppRule { Name = app.DisplayName, ProcessName = app.ProcessName };
            Settings.Rules.Add(rule);
        }

        rule.OutputDeviceIds.Clear();
        if (deviceId is not null)
        {
            rule.OutputDeviceIds.Add(deviceId);
        }

        app.PreferredDeviceId = deviceId;
        SaveSettings();
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

    private void OnPropertyChanged(string? name) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private sealed record Snapshot(IReadOnlyList<AudioDevice> Devices, IReadOnlyList<AppRow> Rows);
}
