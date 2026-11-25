using System.Diagnostics;
using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;

namespace GameAudioManager.Core.Watching;

/// <summary>
/// Keeps every configured application on its preferred device.
/// </summary>
/// <remarks>
/// <para>
/// Runs inside the app process rather than as a separate watcher process. That is
/// intentional: the old PowerShell design needed a second process because the GUI was
/// a script. Here the app is a tray-resident single instance, so there is nothing to
/// keep alive separately, and "close the window" no longer stops the watching.
/// </para>
/// <para>
/// Polling is used rather than session notifications. `IMMNotificationClient` would
/// report device changes, but the interesting moments (a game starting, a session
/// being created after the menu loads) are not reliably reported, so a short poll is
/// both simpler and more predictable. The interval is user-configurable.
/// </para>
/// </remarks>
public sealed class WatcherService : IDisposable
{
    private readonly IAudioDeviceService _devices;
    private readonly ISessionQuery _sessions;
    private readonly IAppRoutingService _routing;
    private readonly Dictionary<string, AppWatchState> _states = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();
    private readonly System.Threading.Timer _timer;

    private AppSettings _settings;
    private bool _running;
    private bool _disposed;

    public WatcherService(
        IAudioDeviceService devices,
        ISessionQuery sessions,
        IAppRoutingService routing,
        AppSettings settings)
    {
        _devices = devices ?? throw new ArgumentNullException(nameof(devices));
        _sessions = sessions ?? throw new ArgumentNullException(nameof(sessions));
        _routing = routing ?? throw new ArgumentNullException(nameof(routing));
        _settings = settings ?? throw new ArgumentNullException(nameof(settings));
        _timer = new System.Threading.Timer(_ => SafeTick(), null, Timeout.Infinite, Timeout.Infinite);
    }

    /// <summary>Raised after every cycle with the current status of every rule.</summary>
    public event EventHandler<IReadOnlyList<RoutingStatus>>? StatusUpdated;

    /// <summary>Raised when a cycle throws.</summary>
    public event EventHandler<string>? CycleFailed;

    public bool IsRunning
    {
        get
        {
            lock (_gate)
            {
                return _running;
            }
        }
    }

    public void UpdateSettings(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        lock (_gate)
        {
            _settings = settings;
            if (_running)
            {
                ScheduleLocked();
            }
        }
    }

    public void Start()
    {
        lock (_gate)
        {
            if (_running || _disposed)
            {
                return;
            }

            _running = true;
            ScheduleLocked();
        }

        // Apply immediately instead of waiting for the first tick.
        SafeTick();
    }

    public void Stop()
    {
        lock (_gate)
        {
            _running = false;
            _timer.Change(Timeout.Infinite, Timeout.Infinite);
        }
    }

    /// <summary>Forces one cycle, used by the refresh button and by tests.</summary>
    public void TriggerNow() => SafeTick();

    public IReadOnlyList<RoutingStatus> BuildStatuses()
    {
        var devices = _devices.GetRenderDevices();
        var statuses = new List<RoutingStatus>();
        List<AppRule> rules;
        lock (_gate)
        {
            rules = _settings.Rules.ToList();
        }

        foreach (var rule in rules)
        {
            var processName = Path.GetFileNameWithoutExtension(rule.ProcessName);
            if (string.IsNullOrWhiteSpace(processName))
            {
                continue;
            }

            var running = FindProcesses(processName);
            var state = GetState(processName);
            MuteState mute;
            try
            {
                mute = MuteStateFrom(_sessions.GetMuteSummary(processName));
            }
            catch (Exception)
            {
                mute = MuteState.None;
            }

            var destinationName = devices
                .FirstOrDefault(d => string.Equals(d.Id, state.DestinationDeviceId, StringComparison.OrdinalIgnoreCase))
                ?.Name;

            statuses.Add(RoutingEngine.ToStatus(rule, running.Count > 0, devices, state, mute, destinationName));
        }

        return statuses;
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _disposed = true;
            _running = false;
        }

        _timer.Dispose();
    }

    private void ScheduleLocked()
    {
        var seconds = Math.Clamp(_settings.WatchIntervalSeconds, 1, 3600);
        _timer.Change(TimeSpan.FromSeconds(seconds), TimeSpan.FromSeconds(seconds));
    }

    private void SafeTick()
    {
        try
        {
            Tick();
        }
        catch (Exception ex)
        {
            CycleFailed?.Invoke(this, ex.Message);
        }
    }

    private void Tick()
    {
        List<AppRule> rules;
        lock (_gate)
        {
            if (!_running || _disposed)
            {
                return;
            }

            rules = _settings.Rules.ToList();
        }

        var devices = _devices.GetRenderDevices();
        var now = DateTimeOffset.UtcNow;

        foreach (var rule in rules)
        {
            var processName = Path.GetFileNameWithoutExtension(rule.ProcessName);
            if (string.IsNullOrWhiteSpace(processName))
            {
                continue;
            }

            var processes = FindProcesses(processName);
            var identity = processes.Count == 0 ? null : processes[0].Identity;
            var state = GetState(processName);

            var decision = RoutingEngine.Decide(rule, processes.Count > 0, identity, devices, state);
            if (!decision.ShouldApply || decision.DeviceId is null)
            {
                continue;
            }

            Apply(rule, processName, decision.DeviceId, devices, state, now);
        }

        StatusUpdated?.Invoke(this, BuildStatuses());
    }

    private void Apply(
        AppRule rule,
        string processName,
        string deviceId,
        IReadOnlyList<AudioDevice> devices,
        AppWatchState state,
        DateTimeOffset now)
    {
        try
        {
            var result = _routing.SetPreferredDevice(processName, deviceId);
            if (!result.Recorded)
            {
                RoutingEngine.MarkFailed(state, result.Message);
                return;
            }

            var name = devices.FirstOrDefault(d => string.Equals(d.Id, deviceId, StringComparison.OrdinalIgnoreCase))?.Name;
            RoutingEngine.MarkApplied(state, deviceId, name, now);
        }
        catch (Exception ex)
        {
            // One failing app must not stop the others from being handled.
            RoutingEngine.MarkFailed(state, ex.Message);
        }
    }

    private AppWatchState GetState(string processName)
    {
        lock (_states)
        {
            if (!_states.TryGetValue(processName, out var state))
            {
                state = new AppWatchState();
                _states[processName] = state;
            }

            return state;
        }
    }

    private static List<ProcessSnapshot> FindProcesses(string processName)
    {
        var found = new List<ProcessSnapshot>();
        foreach (var process in Process.GetProcessesByName(processName))
        {
            using (process)
            {
                try
                {
                    found.Add(new ProcessSnapshot(
                        process.Id,
                        $"{process.Id}:{process.StartTime.ToUniversalTime().Ticks}"));
                }
                catch (InvalidOperationException)
                {
                    // Exited between enumeration and access.
                }
            }
        }

        return found;
    }

    private static MuteState MuteStateFrom(MuteSummary summary)
    {
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

    private sealed record ProcessSnapshot(int Id, string Identity);
}
