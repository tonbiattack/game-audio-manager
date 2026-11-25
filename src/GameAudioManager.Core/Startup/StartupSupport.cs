using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace GameAudioManager.Core.Startup;

/// <summary>
/// Prevents a second copy of the app from running.
/// </summary>
/// <remarks>
/// Two copies would both poll and both write routing, producing confusing fights over
/// the same app. A named mutex in the per-user namespace is the simplest reliable
/// guard on Windows.
/// </remarks>
public sealed class SingleInstanceGuard : IDisposable
{
    private readonly Mutex _mutex;
    private bool _disposed;

    private SingleInstanceGuard(Mutex mutex, bool isFirstInstance)
    {
        _mutex = mutex;
        IsFirstInstance = isFirstInstance;
    }

    /// <summary>True when this process is the one that may run.</summary>
    public bool IsFirstInstance { get; }

    public static SingleInstanceGuard Acquire(string name = "GameAudioManager.SingleInstance")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        var mutex = new Mutex(initiallyOwned: true, @"Local\" + name, out var createdNew);

        if (!createdNew)
        {
            // Someone else owns it; release our handle to avoid leaking.
            mutex.Dispose();
            return new SingleInstanceGuard(new Mutex(false, @"Local\" + name), isFirstInstance: false);
        }

        return new SingleInstanceGuard(mutex, isFirstInstance: true);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        try
        {
            _mutex.ReleaseMutex();
        }
        catch (ApplicationException)
        {
            // Not owned by this thread; nothing to release.
        }

        _mutex.Dispose();
    }

    /// <summary>
    /// Stable name for the "already running" broadcast. Message filters need a value
    /// derived from the mutex name so both copies agree.
    /// </summary>
    public static string GetActivationMessageName(string name = "GameAudioManager.SingleInstance")
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(name));
        return "GameAudioManager.Activate." + Convert.ToHexString(hash.AsSpan(0, 8));
    }
}

/// <summary>
/// Adds or removes the per-user "run at logon" entry.
/// </summary>
/// <remarks>
/// HKCU\...\Run is used instead of a Startup shortcut or a scheduled task: it needs
/// no elevation, is visible in Task Manager's Startup tab so the user can disable it,
/// and is trivially reversible. The user opts in from settings; it is never enabled
/// silently.
/// </remarks>
public static class AutoStartRegistration
{
    public const string DefaultRunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string DefaultValueName = "GameAudioManager";

    public static bool IsEnabled(string? runKeyPath = null, string? valueName = null)
    {
        using var key = Registry.CurrentUser.OpenSubKey(runKeyPath ?? DefaultRunKeyPath);
        return key?.GetValue(valueName ?? DefaultValueName) is string value && !string.IsNullOrWhiteSpace(value);
    }

    public static void Enable(string executablePath, string? runKeyPath = null, string? valueName = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);
        using var key = Registry.CurrentUser.CreateSubKey(runKeyPath ?? DefaultRunKeyPath, writable: true)
            ?? throw new InvalidOperationException("Could not open the Run registry key.");

        // Quotes matter: an unquoted path with spaces is split by the loader.
        key.SetValue(valueName ?? DefaultValueName, $"\"{executablePath}\"", RegistryValueKind.String);
    }

    public static void Disable(string? runKeyPath = null, string? valueName = null)
    {
        using var key = Registry.CurrentUser.OpenSubKey(runKeyPath ?? DefaultRunKeyPath, writable: true);
        key?.DeleteValue(valueName ?? DefaultValueName, throwOnMissingValue: false);
    }
}
