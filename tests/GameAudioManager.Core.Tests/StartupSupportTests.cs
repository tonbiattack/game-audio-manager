using GameAudioManager.Core.Startup;
using Microsoft.Win32;

namespace GameAudioManager.Core.Tests;

public sealed class StartupSupportTests : IDisposable
{
    private const string TestKeyPath = @"Software\GameAudioManagerTests\Run";
    private const string TestValueName = "GameAudioManagerTest";

    public void Dispose()
    {
        Registry.CurrentUser.DeleteSubKeyTree(@"Software\GameAudioManagerTests", throwOnMissingSubKey: false);
    }

    [Fact]
    public void AutoStart_IsDisabledByDefault()
    {
        Assert.False(AutoStartRegistration.IsEnabled(TestKeyPath, TestValueName));
    }

    [Fact]
    public void AutoStart_EnableThenReadBack()
    {
        AutoStartRegistration.Enable(@"C:\apps\game-audio-manager\GameAudioManager.exe", TestKeyPath, TestValueName);

        Assert.True(AutoStartRegistration.IsEnabled(TestKeyPath, TestValueName));
    }

    [Fact]
    public void AutoStart_WritesQuotedPath()
    {
        const string exe = @"C:\Program Files\Game Audio Manager\GameAudioManager.exe";
        AutoStartRegistration.Enable(exe, TestKeyPath, TestValueName);

        using var key = Registry.CurrentUser.OpenSubKey(TestKeyPath);
        var value = key?.GetValue(TestValueName) as string;

        // An unquoted path with spaces is split by the loader.
        Assert.Equal($"\"{exe}\"", value);
    }

    [Fact]
    public void AutoStart_DisableRemovesValue()
    {
        AutoStartRegistration.Enable(@"C:\x\GameAudioManager.exe", TestKeyPath, TestValueName);

        AutoStartRegistration.Disable(TestKeyPath, TestValueName);

        Assert.False(AutoStartRegistration.IsEnabled(TestKeyPath, TestValueName));
    }

    [Fact]
    public void AutoStart_DisableTwiceIsSafe()
    {
        AutoStartRegistration.Disable(TestKeyPath, TestValueName);
        AutoStartRegistration.Disable(TestKeyPath, TestValueName);

        Assert.False(AutoStartRegistration.IsEnabled(TestKeyPath, TestValueName));
    }

    [Fact]
    public void SingleInstance_SecondAcquireIsNotFirst()
    {
        using var first = SingleInstanceGuard.Acquire("GameAudioManager.Tests.SingleInstance");
        Assert.True(first.IsFirstInstance);

        using var second = SingleInstanceGuard.Acquire("GameAudioManager.Tests.SingleInstance");
        Assert.False(second.IsFirstInstance);
    }

    [Fact]
    public void SignalRunningInstance_IsSafeWhenNoInstanceIsListening()
    {
        // Must not throw: the second instance exits either way.
        SingleInstanceGuard.SignalRunningInstance("GameAudioManager.Tests.NoListener");
    }

    [Fact]
    public void ListenForActivation_InvokesCallbackWhenSignalled()
    {
        const string name = "GameAudioManager.Tests.Activate";
        using var guard = SingleInstanceGuard.Acquire(name);
        Assert.True(guard.IsFirstInstance);

        using var signalled = new ManualResetEventSlim();
        var thread = guard.ListenForActivation(() => signalled.Set(), name);
        Assert.NotNull(thread);

        SingleInstanceGuard.SignalRunningInstance(name);

        Assert.True(signalled.Wait(TimeSpan.FromSeconds(5)), "The activation callback must run when signalled.");
    }

    [Fact]
    public void SingleInstance_ActivationEventNameIsStable()
    {
        var a = SingleInstanceGuard.GetActivationEventName("x");
        var b = SingleInstanceGuard.GetActivationEventName("x");
        var c = SingleInstanceGuard.GetActivationEventName("y");

        Assert.Equal(a, b);
        Assert.NotEqual(a, c);
        Assert.Contains("Activate", a, StringComparison.Ordinal);
    }
}

