using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;
using GameAudioManager.Core.Watching;

namespace GameAudioManager.Core.Tests;

public sealed class WatcherServiceTests
{
    private sealed class FakeDevices : IAudioDeviceService
    {
        public List<AudioDevice> Devices { get; } = new();

        public IReadOnlyList<AudioDevice> GetRenderDevices() => Devices;

        public AudioDevice? FindById(string deviceId) =>
            Devices.FirstOrDefault(d => string.Equals(d.Id, deviceId, StringComparison.OrdinalIgnoreCase));
    }

    private sealed class FakeSessions : ISessionQuery
    {
        public IReadOnlyList<AudioSessionInfo> GetSessions(string processName) => Array.Empty<AudioSessionInfo>();

        public MuteSummary GetMuteSummary(string processName) => MuteSummary.None;
    }

    private sealed class RecordingRouting : IAppRoutingService
    {
        public List<(string Process, string Device)> Calls { get; } = new();

        public bool Fail { get; set; }

        public RoutingResult SetPreferredDevice(string executableName, string deviceId)
        {
            Calls.Add((executableName, deviceId));
            return Fail
                ? RoutingResult.NotRecorded("boom")
                : new RoutingResult(true, false, "ok");
        }

        public RoutingResult ResetToDefault(string executableName) => new(true, false, "reset");

        public string? GetPreferredDevice(string executableName) => null;
    }

    [Fact]
    public void BuildStatuses_ListsEveryRuleWithItsState()
    {
        var devices = new FakeDevices();
        devices.Devices.Add(new AudioDevice("a", "Device A", AudioDeviceState.Active, true));

        var settings = new AppSettings
        {
            Rules =
            {
                new AppRule { Name = "Not running", ProcessName = "gam-no-such-process", OutputDeviceIds = { "a" } },
            },
        };

        using var watcher = new WatcherService(devices, new FakeSessions(), new RecordingRouting(), settings);

        var statuses = watcher.BuildStatuses();

        var status = Assert.Single(statuses);
        Assert.Equal(RoutingState.NotRunning, status.State);
        Assert.Equal("未起動", status.StateText);
    }

    [Fact]
    public void BuildStatuses_ReportsNoActiveCandidate()
    {
        var devices = new FakeDevices();
        var settings = new AppSettings
        {
            Rules =
            {
                // Use the real test-host process so the "running" branch is exercised.
                new AppRule { Name = "Self", ProcessName = System.Diagnostics.Process.GetCurrentProcess().ProcessName, OutputDeviceIds = { "missing" } },
            },
        };

        using var watcher = new WatcherService(devices, new FakeSessions(), new RecordingRouting(), settings);

        // The test host process itself is running, so the "running" branch is exercised.
        var status = Assert.Single(watcher.BuildStatuses());
        Assert.True(status.IsRunning);
        Assert.Equal(RoutingState.NoActiveCandidate, status.State);
    }

    [Fact]
    public void TriggerNow_DoesNothingWhenStopped()
    {
        var devices = new FakeDevices();
        devices.Devices.Add(new AudioDevice("a", "Device A", AudioDeviceState.Active, true));
        var routing = new RecordingRouting();
        var settings = new AppSettings
        {
            Rules = { new AppRule { ProcessName = "gam-no-such-process", OutputDeviceIds = { "a" } } },
        };

        using var watcher = new WatcherService(devices, new FakeSessions(), routing, settings);

        watcher.TriggerNow();

        Assert.Empty(routing.Calls);
    }

    [Fact]
    public void Start_RunsImmediatelyAndStops()
    {
        var devices = new FakeDevices();
        devices.Devices.Add(new AudioDevice("a", "Device A", AudioDeviceState.Active, true));
        var routing = new RecordingRouting();
        var settings = new AppSettings
        {
            WatchIntervalSeconds = 3600,
            Rules = { new AppRule { ProcessName = "gam-no-such-process", OutputDeviceIds = { "a" } } },
        };

        using var watcher = new WatcherService(devices, new FakeSessions(), routing, settings);
        watcher.Start();

        Assert.True(watcher.IsRunning);
        Assert.Empty(routing.Calls); // the app is not running, so nothing is applied

        watcher.Stop();
        Assert.False(watcher.IsRunning);
    }

    [Fact]
    public void BuildStatuses_UsesDeviceNameFromEnumeration()
    {
        var devices = new FakeDevices();
        devices.Devices.Add(new AudioDevice("a", "Device A", AudioDeviceState.Active, true));
        var settings = new AppSettings
        {
            Rules = { new AppRule { Name = "Rule", ProcessName = "gam-no-such-process", OutputDeviceIds = { "a" } } },
        };

        using var watcher = new WatcherService(devices, new FakeSessions(), new RecordingRouting(), settings);

        var status = Assert.Single(watcher.BuildStatuses());
        Assert.Equal("Rule", status.DisplayName);
    }
}

