using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Watching;

namespace GameAudioManager.Core.Tests;

public sealed class RoutingEngineTests
{
    private static AudioDevice Device(string id, bool active)
        => new(id, id, active ? AudioDeviceState.Active : AudioDeviceState.Unplugged, IsDefault: false);

    private static AppRule Rule(params string[] devices) => new()
    {
        Name = "Game",
        ProcessName = "GameExecutable",
        OutputDeviceIds = devices.ToList(),
        Enabled = true,
        AutoApply = true,
    };

    [Fact]
    public void Decide_AppliesOnFirstSightOfRunningProcess()
    {
        var state = new AppWatchState();
        var devices = new[] { Device("a", true) };

        var decision = RoutingEngine.Decide(Rule("a"), isRunning: true, "1:100", devices, state);

        Assert.True(decision.ShouldApply);
        Assert.Equal("a", decision.DeviceId);
        Assert.Equal(RoutingState.Pending, decision.State);
    }

    [Fact]
    public void Decide_DoesNotReapplyWhileStable()
    {
        var state = new AppWatchState();
        var devices = new[] { Device("a", true) };
        var rule = Rule("a");

        var first = RoutingEngine.Decide(rule, true, "1:100", devices, state);
        Assert.True(first.ShouldApply);
        RoutingEngine.MarkApplied(state, "a", "Device A", DateTimeOffset.UtcNow);

        var second = RoutingEngine.Decide(rule, true, "1:100", devices, state);

        Assert.False(second.ShouldApply);
        Assert.Equal(RoutingState.Applied, second.State);
    }

    [Fact]
    public void Decide_ReappliesAfterRestart()
    {
        var state = new AppWatchState();
        var devices = new[] { Device("a", true) };
        var rule = Rule("a");

        RoutingEngine.Decide(rule, true, "1:100", devices, state);
        RoutingEngine.MarkApplied(state, "a", "Device A", DateTimeOffset.UtcNow);

        // Same device, new process identity.
        var decision = RoutingEngine.Decide(rule, true, "2:200", devices, state);

        Assert.True(decision.ShouldApply);
    }

    [Fact]
    public void Decide_ReappliesAfterDeviceReconnect()
    {
        var state = new AppWatchState();
        var rule = Rule("a");
        var devices = new[] { Device("a", true) };

        RoutingEngine.Decide(rule, true, "1:100", devices, state);
        RoutingEngine.MarkApplied(state, "a", "Device A", DateTimeOffset.UtcNow);

        // Device disappears.
        var gone = new[] { Device("a", false) };
        var whileGone = RoutingEngine.Decide(rule, true, "1:100", gone, state);
        Assert.Equal(RoutingState.NoActiveCandidate, whileGone.State);
        Assert.False(whileGone.ShouldApply);

        // Device returns.
        var back = RoutingEngine.Decide(rule, true, "1:100", devices, state);
        Assert.True(back.ShouldApply);
    }

    [Fact]
    public void Decide_ReappliesWhenFallingBackToAnotherCandidate()
    {
        var state = new AppWatchState();
        var rule = Rule("preferred", "fallback");
        var bothUp = new[] { Device("preferred", true), Device("fallback", true) };

        RoutingEngine.Decide(rule, true, "1:100", bothUp, state);
        RoutingEngine.MarkApplied(state, "preferred", "Preferred", DateTimeOffset.UtcNow);

        var onlyFallback = new[] { Device("preferred", false), Device("fallback", true) };
        var decision = RoutingEngine.Decide(rule, true, "1:100", onlyFallback, state);

        Assert.True(decision.ShouldApply);
        Assert.Equal("fallback", decision.DeviceId);
    }

    [Fact]
    public void Decide_ReportsNotRunningAndForgetsIdentity()
    {
        var state = new AppWatchState();
        var devices = new[] { Device("a", true) };
        var rule = Rule("a");

        RoutingEngine.Decide(rule, true, "1:100", devices, state);
        RoutingEngine.MarkApplied(state, "a", "Device A", DateTimeOffset.UtcNow);

        var stopped = RoutingEngine.Decide(rule, false, null, devices, state);

        Assert.Equal(RoutingState.NotRunning, stopped.State);
        Assert.False(stopped.ShouldApply);
        Assert.Null(state.ProcessIdentity);
    }

    [Fact]
    public void Decide_ReappliesAfterStopAndStart()
    {
        var state = new AppWatchState();
        var devices = new[] { Device("a", true) };
        var rule = Rule("a");

        RoutingEngine.Decide(rule, true, "1:100", devices, state);
        RoutingEngine.MarkApplied(state, "a", "Device A", DateTimeOffset.UtcNow);
        RoutingEngine.Decide(rule, false, null, devices, state);

        var restarted = RoutingEngine.Decide(rule, true, "1:100", devices, state);

        Assert.True(restarted.ShouldApply);
    }

    [Fact]
    public void Decide_RetriesAfterFailure()
    {
        var state = new AppWatchState();
        var devices = new[] { Device("a", true) };
        var rule = Rule("a");

        RoutingEngine.Decide(rule, true, "1:100", devices, state);
        RoutingEngine.MarkFailed(state, "boom");

        var retry = RoutingEngine.Decide(rule, true, "1:100", devices, state);

        Assert.True(retry.ShouldApply);
        Assert.Equal("boom", retry.Error);
    }

    [Fact]
    public void Decide_HonoursAutoApplyOff()
    {
        var rule = Rule("a");
        rule.AutoApply = false;

        var decision = RoutingEngine.Decide(rule, true, "1:100", new[] { Device("a", true) }, new AppWatchState());

        Assert.False(decision.ShouldApply);
        Assert.Equal(RoutingState.NotConfigured, decision.State);
    }

    [Fact]
    public void Decide_HonoursDisabledRule()
    {
        var rule = Rule("a");
        rule.Enabled = false;

        var decision = RoutingEngine.Decide(rule, true, "1:100", new[] { Device("a", true) }, new AppWatchState());

        Assert.Equal(RoutingState.NotConfigured, decision.State);
    }

    [Fact]
    public void Decide_ReportsMissingCandidates()
    {
        var decision = RoutingEngine.Decide(Rule(), true, "1:100", new[] { Device("a", true) }, new AppWatchState());

        Assert.Equal(RoutingState.NotConfigured, decision.State);
    }

    [Fact]
    public void ToStatus_DistinguishesPendingAndFailed()
    {
        var rule = Rule("a");
        var devices = new[] { Device("a", true) };

        var pending = RoutingEngine.ToStatus(rule, true, devices, new AppWatchState { DestinationDeviceId = "a" }, MuteState.None, "Device A");
        Assert.Equal(RoutingState.Pending, pending.State);

        var failed = new AppWatchState { LastError = "boom" };
        var failedStatus = RoutingEngine.ToStatus(rule, true, devices, failed, MuteState.None, "Device A");
        Assert.Equal(RoutingState.Failed, failedStatus.State);

        var appliedState = new AppWatchState { DestinationDeviceId = "a" };
        RoutingEngine.MarkApplied(appliedState, "a", "Device A", DateTimeOffset.UtcNow);
        var applied = RoutingEngine.ToStatus(rule, true, devices, appliedState, MuteState.None, "Device A");
        Assert.Equal(RoutingState.Applied, applied.State);
    }
}
