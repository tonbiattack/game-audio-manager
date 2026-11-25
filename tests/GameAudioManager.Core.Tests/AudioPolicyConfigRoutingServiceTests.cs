using GameAudioManager.Core.Routing;

namespace GameAudioManager.Core.Tests;

/// <summary>
/// Pure-logic checks for the undocumented routing layer. The actual COM call needs a
/// live audio stack, so it is covered by the manual checklist in
/// docs/dotnet-migration.md instead.
/// </summary>
public sealed class AudioPolicyConfigRoutingServiceTests
{
    [Theory]
    [InlineData("chrome", "chrome.exe")]
    [InlineData("chrome.exe", "chrome.exe")]
    [InlineData("  chrome.exe  ", "chrome.exe")]
    [InlineData("Chrome.EXE", "Chrome.EXE")]
    public void NormalizeExecutable_AddsExeSuffixOnce(string input, string expected)
    {
        Assert.Equal(expected, AudioPolicyConfigRoutingService.NormalizeExecutable(input));
    }

    [Fact]
    public void NormalizeExecutable_RejectsBlank()
    {
        Assert.ThrowsAny<ArgumentException>(() => AudioPolicyConfigRoutingService.NormalizeExecutable("   "));
    }

    [Fact]
    public void BuildEndpointPath_WrapsShortIdInDeviceInterfacePath()
    {
        const string shortId = "{0.0.0.00000000}.{0fa80fd7-39d7-4164-9c69-e3eac8c51f60}";

        var path = AudioPolicyConfigRoutingService.BuildEndpointPath(shortId);

        Assert.Equal(
            @"\\?\SWD#MMDEVAPI#{0.0.0.00000000}.{0fa80fd7-39d7-4164-9c69-e3eac8c51f60}#{e6327cad-dcec-4949-ae8a-991e976a79d2}",
            path);
    }

    [Fact]
    public void BuildEndpointPath_LeavesFullInterfacePathAlone()
    {
        const string full = @"\\?\SWD#MMDEVAPI#{0.0.0.00000000}.{abc}#{e6327cad-dcec-4949-ae8a-991e976a79d2}";

        Assert.Equal(full, AudioPolicyConfigRoutingService.BuildEndpointPath(full));
    }

    [Fact]
    public void BuildEndpointPath_RejectsBlank()
    {
        Assert.ThrowsAny<ArgumentException>(() => AudioPolicyConfigRoutingService.BuildEndpointPath(" "));
    }

    [Fact]
    public void SetPreferredDevice_RejectsUnknownDevice()
    {
        var service = new AudioPolicyConfigRoutingService(new EmptyDeviceService());

        var result = service.SetPreferredDevice("chrome", "{0.0.0.00000000}.{missing}");

        Assert.False(result.Recorded);
        Assert.Contains("was not found", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void SetPreferredDevice_ReportsWhenAppIsNotRunning()
    {
        var devices = new EmptyDeviceService();
        const string id = "{0.0.0.00000000}.{known}";
        devices.Devices.Add(new Core.Audio.AudioDevice(id, "Speakers", Core.Audio.AudioDeviceState.Active, true));
        var service = new AudioPolicyConfigRoutingService(devices);

        // A process name that cannot exist.
        var result = service.SetPreferredDevice("game-audio-manager-no-such-process", id);

        Assert.False(result.Recorded);
        Assert.Contains("not running", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    private sealed class EmptyDeviceService : Core.Audio.IAudioDeviceService
    {
        public List<Core.Audio.AudioDevice> Devices { get; } = new();

        public IReadOnlyList<Core.Audio.AudioDevice> GetRenderDevices() => Devices;

        public Core.Audio.AudioDevice? FindById(string deviceId) =>
            Devices.FirstOrDefault(d => string.Equals(d.Id, deviceId, StringComparison.OrdinalIgnoreCase));
    }
}
