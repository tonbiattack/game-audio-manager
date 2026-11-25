using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Routing;

namespace GameAudioManager.Core.Tests;

public sealed class DevicePriorityTests
{
    private static AudioDevice Device(string id, bool active, string? name = null)
        => new(id, name ?? id, active ? AudioDeviceState.Active : AudioDeviceState.Unplugged, IsDefault: false);

    [Fact]
    public void SelectPreferred_ReturnsFirstActiveCandidate()
    {
        var devices = new[] { Device("b", active: true), Device("a", active: true) };

        Assert.Equal("a", DevicePriority.SelectPreferred(new[] { "a", "b" }, devices));
    }

    [Fact]
    public void SelectPreferred_SkipsInactiveCandidate()
    {
        var devices = new[] { Device("a", active: false), Device("b", active: true) };

        Assert.Equal("b", DevicePriority.SelectPreferred(new[] { "a", "b" }, devices));
    }

    [Fact]
    public void SelectPreferred_ReturnsNullWhenNoCandidateIsActive()
    {
        var devices = new[] { Device("a", active: false) };

        Assert.Null(DevicePriority.SelectPreferred(new[] { "a", "missing" }, devices));
    }

    [Fact]
    public void SelectPreferred_IgnoresBlankCandidates()
    {
        var devices = new[] { Device("a", active: true) };

        Assert.Equal("a", DevicePriority.SelectPreferred(new[] { "", "  ", "a" }, devices));
    }

    [Fact]
    public void SelectPreferred_IsCaseInsensitive()
    {
        var devices = new[] { Device("ABC", active: true) };

        Assert.Equal("ABC", DevicePriority.SelectPreferred(new[] { "abc" }, devices));
    }

    [Fact]
    public void Decide_AppliesFirstActiveCandidate()
    {
        var rule = new GameAudioManager.Core.Configuration.AppRule { ProcessName = "game", Enabled = true, AutoApply = true };
        var devices = new[] { Device("a", active: true) };

        var decision = DevicePriority.Decide(rule, isRunning: true, new[] { "a" }, devices);

        Assert.True(decision.ShouldApply);
        Assert.Equal("a", decision.DeviceId);
    }

    [Theory]
    [InlineData(RoutingDecisionKind.NotRunning)]
    public void Decide_ReportsNotRunning(RoutingDecisionKind expected)
    {
        var rule = new GameAudioManager.Core.Configuration.AppRule { ProcessName = "game" };
        var devices = new[] { Device("a", active: true) };

        var decision = DevicePriority.Decide(rule, isRunning: false, new[] { "a" }, devices);

        Assert.Equal(expected, decision.Kind);
        Assert.False(decision.ShouldApply);
        Assert.Null(decision.DeviceId);
    }

    [Fact]
    public void Decide_HonoursDisabledRule()
    {
        var rule = new GameAudioManager.Core.Configuration.AppRule { ProcessName = "game", Enabled = false };

        var decision = DevicePriority.Decide(rule, true, new[] { "a" }, new[] { Device("a", true) });

        Assert.Equal(RoutingDecisionKind.RuleDisabled, decision.Kind);
    }

    [Fact]
    public void Decide_HonoursAutoApplyOff()
    {
        var rule = new GameAudioManager.Core.Configuration.AppRule { ProcessName = "game", AutoApply = false };

        var decision = DevicePriority.Decide(rule, true, new[] { "a" }, new[] { Device("a", true) });

        Assert.Equal(RoutingDecisionKind.AutoApplyDisabled, decision.Kind);
    }

    [Fact]
    public void Decide_ReportsMissingCandidates()
    {
        var rule = new GameAudioManager.Core.Configuration.AppRule { ProcessName = "game" };

        var decision = DevicePriority.Decide(rule, true, Array.Empty<string>(), new[] { Device("a", true) });

        Assert.Equal(RoutingDecisionKind.NoCandidates, decision.Kind);
    }

    [Fact]
    public void Decide_ReportsNoActiveCandidate()
    {
        var rule = new GameAudioManager.Core.Configuration.AppRule { ProcessName = "game" };

        var decision = DevicePriority.Decide(rule, true, new[] { "a" }, new[] { Device("a", active: false) });

        Assert.Equal(RoutingDecisionKind.NoActiveCandidate, decision.Kind);
    }

    [Fact]
    public void Move_SwapsWithPrevious()
    {
        var moved = DevicePriority.Move(new[] { "a", "b", "c" }, 2, -1);

        Assert.Equal(new[] { "a", "c", "b" }, moved);
    }

    [Fact]
    public void Move_AtBoundaryIsNoOp()
    {
        var original = new[] { "a", "b" };

        Assert.Same(original, DevicePriority.Move(original, 0, -1));
        Assert.Same(original, DevicePriority.Move(original, 1, 1));
    }

    [Fact]
    public void Move_OutOfRangeIndexIsNoOp()
    {
        var original = new[] { "a" };

        Assert.Same(original, DevicePriority.Move(original, 5, 1));
        Assert.Same(original, DevicePriority.Move(original, -1, 1));
    }

    [Fact]
    public void Add_AppendsNewDevice()
    {
        Assert.Equal(new[] { "a", "b" }, DevicePriority.Add(new[] { "a" }, "b"));
    }

    [Fact]
    public void Add_DoesNotDuplicate()
    {
        var original = new[] { "a", "b" };

        Assert.Same(original, DevicePriority.Add(original, "A"));
    }

    [Fact]
    public void Remove_DropsMatchingDevice()
    {
        Assert.Equal(new[] { "a", "c" }, DevicePriority.Remove(new[] { "a", "B", "c" }, "b"));
    }

    [Fact]
    public void Remove_AbsentDeviceIsNoOp()
    {
        Assert.Equal(new[] { "a" }, DevicePriority.Remove(new[] { "a" }, "zzz"));
    }
}
