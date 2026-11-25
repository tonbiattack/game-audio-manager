using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace GameAudioManager.Core.Startup;

/// <summary>
/// Prevents a second copy of the app from running, and wakes the first one instead.
/// </summary>
/// <remarks>
/// <para>
/// Two copies would both poll and both write routing, producing confusing fights over
/// the same app. A named mutex in the per-user namespace is the simplest reliable
/// guard on Windows.
/// </para>
/// <para>
/// The app lives in the tray, so a second launch would otherwise look like "nothing
/// happened": the new process exits and the existing window stays hidden. The second
/// instance therefore signals a named event and the first instance brings its window
/// to the front.
/// </para>
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

    /// <summary>Name of the event a second instance uses to ask for the window.</summary>
    public static string GetActivationEventName(string name = "GameAudioManager.SingleInstance")
    {
        return @"Local\" + name + ".Activate";
    }

    /// <summary>
    /// Called by the second instance: asks the running instance to show its window.
    /// Best effort; the caller exits either way.
    /// </summary>
    public static void SignalRunningInstance(string name = "GameAudioManager.SingleInstance")
    {
        try
        {
            using var handle = EventWaitHandle.OpenExisting(GetActivationEventName(name));
            handle.Set();
        }
        catch (WaitHandleCannotBeOpenedException)
        {
            // The other instance is starting up or already gone; nothing to wake.
        }
        catch (UnauthorizedAccessException)
        {
            // Different integrity level; ignore.
        }
    }

    /// <summary>
    /// Starts a background listener that invokes <paramref name="onActivate"/> whenever
    /// another instance asks for the window. Returns the thread so it can be stopped.
    /// </summary>
    public Thread ListenForActivation(Action onActivate, string name = "GameAudioManager.SingleInstance")
    {
        ArgumentNullException.ThrowIfNull(onActivate);

        var handle = new EventWaitHandle(false, EventResetMode.AutoReset, GetActivationEventName(name));
        var thread = new Thread(() =>
        {
            while (!_disposed)
            {
                try
                {
                    if (handle.WaitOne(500))
                    {
                        onActivate();
                    }
                }
                catch (ObjectDisposedException)
                {
                    return;
                }
            }
        })
        {
            IsBackground = true,
            Name = "GameAudioManager.ActivationListener",
        };

        thread.Start();
        return thread;
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

