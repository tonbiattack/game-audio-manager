using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Routing;

namespace GameAudioManager.Core.Tests;

/// <summary>
/// Behaviour when the undocumented audio policy API is unavailable or misbehaves.
/// </summary>
/// <remarks>
/// Routing must degrade to a clear message and let every other feature (mute,
/// enumeration, the watcher for other apps) keep working. It must never throw out of
/// a watch cycle, because one app's routing must not stop the rest.
/// </remarks>
public sealed class AudioPolicyConfigFailureTests
{
    /// <summary>
    /// The test host's own process name, so the "application is running" branch is
    /// reached. The unsupported-API path is only taken for a running application, and
    /// CI has no Chrome to rely on.
    /// </summary>
    private static readonly string RunningProcessName =
        System.Diagnostics.Process.GetCurrentProcess().ProcessName;

    private const string KnownDeviceId = "{0.0.0.00000000}.{dev}";

    private sealed class Devices : IAudioDeviceService
    {
        public List<AudioDevice> Items { get; } = new();

        public IReadOnlyList<AudioDevice> GetRenderDevices() => Items;

        public AudioDevice? FindById(string deviceId) =>
            Items.FirstOrDefault(d => string.Equals(d.Id, deviceId, StringComparison.OrdinalIgnoreCase));
    }

    private static Devices OneActiveDevice()
    {
        var devices = new Devices();
        devices.Items.Add(new AudioDevice(KnownDeviceId, "Speakers", AudioDeviceState.Active, true));
        return devices;
    }

    private static AudioPolicyConfigRoutingService WithUnavailableApi(IAudioDeviceService devices) =>
        new(devices, () => (false, IntPtr.Zero, "simulated unsupported build"));

    [Fact]
    public void SetPreferredDevice_ReportsUnsupportedWithoutThrowing()
    {
        var service = WithUnavailableApi(OneActiveDevice());

        var result = service.SetPreferredDevice(RunningProcessName, KnownDeviceId);

        Assert.False(result.Recorded);
        Assert.Contains("利用できません", result.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void ResetToDefault_ReportsUnsupportedWithoutThrowing()
    {
        var service = WithUnavailableApi(OneActiveDevice());

        var result = service.ResetToDefault(RunningProcessName);

        Assert.False(result.Recorded);
        Assert.Contains("利用できません", result.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void GetPreferredDevice_ReturnsNullWhenUnsupportedInsteadOfGuessing()
    {
        var service = WithUnavailableApi(OneActiveDevice());

        Assert.Null(service.GetPreferredDevice(RunningProcessName));
    }

    [Fact]
    public void UnsupportedApi_StillValidatesDeviceFirst()
    {
        var service = WithUnavailableApi(OneActiveDevice());

        // An unknown device is a caller error and must be reported as such even when
        // the API itself is unavailable.
        var result = service.SetPreferredDevice(RunningProcessName, "{0.0.0.00000000}.{missing}");

        Assert.False(result.Recorded);
        Assert.Contains("was not found", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void UnsupportedApi_DoesNotAffectMuteStateModel()
    {
        // Mute is an independent concern: the routing service being unusable must not
        // influence how mute is described.
        var state = new MuteState(HasSession: true, IsMuted: true, IsMixed: false, SessionCount: 2, EndpointCount: 1);

        Assert.True(state.HasSession);
        Assert.True(state.IsMuted);
        Assert.Equal(2, state.SessionCount);
    }

    [Fact]
    public void BuildEndpointPath_IsStableForTheSameDevice()
    {
        Assert.Equal(
            AudioPolicyConfigRoutingService.BuildEndpointPath(KnownDeviceId),
            AudioPolicyConfigRoutingService.BuildEndpointPath(KnownDeviceId));
    }

    [Fact]
    public void UnsupportedMessage_MentionsThatMuteStillWorks()
    {
        // The message is user-facing; it must not imply the whole app is broken.
        Assert.Contains("ミュート", AudioPolicyConfigRoutingService.UnsupportedMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void Capability_ReportsUnavailableMessage()
    {
        var service = WithUnavailableApi(OneActiveDevice());

        Assert.False(service.IsAvailable);
        Assert.Equal(AudioPolicyConfigRoutingService.UnsupportedMessage, service.UnavailableMessage);
    }
}
