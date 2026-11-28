using GameAudioManager.Core.Startup;
using Microsoft.Win32;

namespace GameAudioManager.Core.Tests;

public sealed class StartupRegistrationTests : IDisposable
{
    private const string TestKeyPath = @"Software\GameAudioManagerTestsRegistration\Run";
    private const string TestValueName = "GameAudioManagerRegistrationTest";
    private const string Executable = @"C:\Program Files\Game Audio Manager\GameAudioManager.exe";

    public void Dispose()
    {
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(@"Software\GameAudioManagerTestsRegistration", throwOnMissingSubKey: false);
        }
        catch (IOException)
        {
            // Nothing was created by this test; the parent key is absent.
        }
    }

    private static RunKeyStartupRegistration CreateRegistration(Func<string?>? executable = null)
    {
        return new RunKeyStartupRegistration(executable ?? (() => Executable), TestKeyPath, TestValueName);
    }

    [Fact]
    public async Task RunKey_StartsDisabled()
    {
        var status = await CreateRegistration().GetStatusAsync();

        Assert.Equal(StartupRegistrationState.Disabled, status.State);
        Assert.False(status.IsEnabled);
    }

    [Fact]
    public async Task RunKey_EnableWritesTheQuotedPath()
    {
        var registration = CreateRegistration();

        var status = await registration.SetEnabledAsync(true);

        Assert.Equal(StartupRegistrationState.Enabled, status.State);
        Assert.True(status.IsEnabled);
        using var key = Registry.CurrentUser.OpenSubKey(TestKeyPath);
        Assert.Equal($"\"{Executable}\"", key?.GetValue(TestValueName) as string);
    }

    [Fact]
    public async Task RunKey_DisableRemovesTheEntry()
    {
        var registration = CreateRegistration();
        await registration.SetEnabledAsync(true);

        var status = await registration.SetEnabledAsync(false);

        Assert.Equal(StartupRegistrationState.Disabled, status.State);
        using var key = Registry.CurrentUser.OpenSubKey(TestKeyPath);
        Assert.Null(key?.GetValue(TestValueName));
    }

    [Fact]
    public async Task RunKey_WithoutAnExecutablePathReportsUnavailable()
    {
        var registration = new RunKeyStartupRegistration(() => null, TestKeyPath, TestValueName);

        var status = await registration.SetEnabledAsync(true);

        Assert.Equal(StartupRegistrationState.Unavailable, status.State);
        Assert.False(status.IsEnabled);
        Assert.False(string.IsNullOrWhiteSpace(status.Detail));
    }

    [Fact]
    public async Task RunKey_EnabledStatusSurvivesAFreshInstance()
    {
        await CreateRegistration().SetEnabledAsync(true);

        // Mirrors an app restart: a new object must see the persisted registry state.
        var status = await CreateRegistration().GetStatusAsync();

        Assert.True(status.IsEnabled);
    }
}

