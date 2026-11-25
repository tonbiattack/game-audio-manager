using GameAudioManager.Core.Routing;

namespace GameAudioManager.Core.Tests;

public sealed class AppRoutingServiceTests
{
    [Theory]
    [InlineData("chrome", "chrome.exe")]
    [InlineData("chrome.exe", "chrome.exe")]
    [InlineData("Chrome.EXE", "Chrome.EXE")]
    [InlineData("  chrome.exe  ", "chrome.exe")]
    public void NormalizeExecutable_AddsExeSuffixOnce(string input, string expected)
    {
        Assert.Equal(expected, AppRoutingService.NormalizeExecutable(input));
    }

    [Fact]
    public void NormalizeExecutable_RejectsBlank()
    {
        Assert.ThrowsAny<ArgumentException>(() => AppRoutingService.NormalizeExecutable("   "));
    }

    [Fact]
    public void ExtractEndpointToken_PullsEndpointPair()
    {
        const string deviceId = @"\\?\SWD#MMDEVAPI#{0.0.0.00000000}.{0fa80fd7-39d7-4164-9c69-e3eac8c51f60}#{e6327cad-dcec-4949-ae8a-991e976a79d2}";

        Assert.Equal("{0.0.0.00000000}.{0fa80fd7-39d7-4164-9c69-e3eac8c51f60}", AppRoutingService.ExtractEndpointToken(deviceId));
    }

    [Fact]
    public void ExtractEndpointToken_ReturnsInputWhenNoBracePresent()
    {
        Assert.Equal("plain", AppRoutingService.ExtractEndpointToken("plain"));
    }
}
