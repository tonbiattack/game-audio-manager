using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;

namespace GameAudioManager.Core.Watching;

/// <summary>Per-application runtime state kept across watch cycles.</summary>
public sealed class AppWatchState
{
    /// <summary>Process id + start time, so a restart is detected even if the pid is reused.</summary>
    public string? ProcessIdentity { get; set; }

    public string? DestinationDeviceId { get; set; }

    public bool DeviceAvailable { get; set; }

    public bool Applied { get; set; }

    public string? AppliedDeviceId { get; set; }

    public string? AppliedDeviceName { get; set; }

    public DateTimeOffset? AppliedAt { get; set; }

    public string? LastError { get; set; }
}

/// <summary>What one cycle should do for one application.</summary>
public sealed record WatchDecision(RoutingState State, string? DeviceId, bool ShouldApply, string? Error);

/// <summary>
/// Decides whether an application must (re)apply its output device.
/// </summary>
/// <remarks>
/// Kept pure and state-driven so the reconnect/restart/retry behaviour can be tested
/// without a live game or audio device. The rules are:
/// <list type="bullet">
/// <item>A restarted process re-applies.</item>
/// <item>A device that disappeared and came back re-applies.</item>
/// <item>Falling back to a different candidate re-applies.</item>
/// <item>A failed apply is retried on the next cycle.</item>
/// <item>A stable process with a stable device is left alone (no needless COM calls).</item>
/// </list>
/// </remarks>
public static class RoutingEngine
{
    public static WatchDecision Decide(
        AppRule? rule,
        bool isRunning,
        string? processIdentity,
        IReadOnlyList<AudioDevice> devices,
        AppWatchState state)
    {
        ArgumentNullException.ThrowIfNull(devices);
        ArgumentNullException.ThrowIfNull(state);

        if (rule is null || !rule.Enabled)
        {
            Reset(state);
            return new WatchDecision(RoutingState.NotConfigured, null, false, null);
        }

        if (!isRunning)
        {
            // Remember that it stopped so the next start re-applies.
            Reset(state, keepError: false);
            return new WatchDecision(RoutingState.NotRunning, null, false, null);
        }

        if (!rule.AutoApply)
        {
            return new WatchDecision(RoutingState.NotConfigured, null, false, null);
        }

        if (rule.OutputDeviceIds.Count == 0)
        {
            return new WatchDecision(RoutingState.NotConfigured, null, false, null);
        }

        var destination = DevicePriority.SelectPreferred(rule.OutputDeviceIds, devices);
        var deviceAvailable = destination is not null;

        // Any change in process, availability, or chosen device invalidates the last apply.
        if (state.ProcessIdentity != processIdentity
            || !deviceAvailable
            || !state.DeviceAvailable
            || !string.Equals(state.DestinationDeviceId, destination, StringComparison.OrdinalIgnoreCase))
        {
            state.Applied = false;
        }

        state.ProcessIdentity = processIdentity;
        state.DeviceAvailable = deviceAvailable;
        state.DestinationDeviceId = destination;

        if (destination is null)
        {
            return new WatchDecision(RoutingState.NoActiveCandidate, null, false, null);
        }

        if (state.Applied)
        {
            return new WatchDecision(RoutingState.Applied, destination, false, null);
        }

        return new WatchDecision(RoutingState.Pending, destination, true, state.LastError);
    }

    /// <summary>Records a successful apply.</summary>
    public static void MarkApplied(AppWatchState state, string deviceId, string? deviceName, DateTimeOffset at)
    {
        ArgumentNullException.ThrowIfNull(state);
        state.Applied = true;
        state.AppliedDeviceId = deviceId;
        state.AppliedDeviceName = deviceName;
        state.AppliedAt = at;
        state.LastError = null;
    }

    /// <summary>Records a failed apply so the next cycle retries.</summary>
    public static void MarkFailed(AppWatchState state, string error)
    {
        ArgumentNullException.ThrowIfNull(state);
        state.Applied = false;
        state.LastError = error;
    }

    /// <summary>
    /// Builds the status the UI renders. Separates "recorded" from "applied in this
    /// run", which is the distinction the old UI lacked.
    /// </summary>
    public static RoutingStatus ToStatus(
        AppRule rule,
        bool isRunning,
        IReadOnlyList<AudioDevice> devices,
        AppWatchState state,
        MuteState mute,
        string? destinationName)
    {
        ArgumentNullException.ThrowIfNull(rule);

        var routingState = rule.OutputDeviceIds.Count == 0 || !rule.Enabled
            ? RoutingState.NotConfigured
            : !isRunning
                ? RoutingState.NotRunning
                : !rule.AutoApply
                    ? RoutingState.NotConfigured
                    : state.LastError is not null && !state.Applied
                        ? RoutingState.Failed
                        : state.Applied
                            ? RoutingState.Applied
                            : state.DestinationDeviceId is null
                                ? RoutingState.NoActiveCandidate
                                : RoutingState.Pending;

        return new RoutingStatus(
            rule.ProcessName,
            string.IsNullOrWhiteSpace(rule.Name) ? rule.ProcessName : rule.Name,
            isRunning,
            routingState,
            state.AppliedDeviceId,
            state.AppliedDeviceName,
            destinationName ?? rule.OutputDeviceIds.FirstOrDefault(),
            mute,
            state.LastError);
    }

    private static void Reset(AppWatchState state, bool keepError = true)
    {
        state.ProcessIdentity = null;
        state.DeviceAvailable = false;
        state.DestinationDeviceId = null;
        state.Applied = false;
        state.AppliedDeviceId = null;
        state.AppliedDeviceName = null;
        state.AppliedAt = null;
        if (!keepError)
        {
            state.LastError = null;
        }
    }
}

