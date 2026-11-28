namespace GameAudioManager.Core.Startup;

/// <summary>How the app is registered to start at logon.</summary>
public enum StartupRegistrationState
{
    /// <summary>Registered and active.</summary>
    Enabled,

    /// <summary>Not registered.</summary>
    Disabled,

    /// <summary>Registered, but the user turned it off in Windows; the app must ask them to re-enable it.</summary>
    DisabledByUser,

    /// <summary>This distribution channel has no usable mechanism, or the call failed.</summary>
    Unavailable,
}

/// <summary>Result of reading or changing the logon registration.</summary>
/// <param name="State">Current state after the call.</param>
/// <param name="Detail">Optional diagnostic text (error message, API name).</param>
public sealed record StartupRegistrationStatus(StartupRegistrationState State, string? Detail = null)
{
    public bool IsEnabled => State == StartupRegistrationState.Enabled;
}

/// <summary>
/// Logon autostart, which differs between the portable and the packaged build.
/// </summary>
/// <remarks>
/// The portable build writes <c>HKCU\...\Run</c>. MSIX virtualizes <c>HKCU</c>, so the
/// same write from a packaged process lands in a private hive and the logon shell never
/// sees it; the packaged build must declare a <c>uap5:StartupTask</c> instead and ask
/// the OS through <c>Windows.ApplicationModel.StartupTask</c>.
/// </remarks>
public interface IStartupRegistration
{
    /// <summary>Reads the current state without changing it.</summary>
    Task<StartupRegistrationStatus> GetStatusAsync();

    /// <summary>Requests the given state and reports what the OS actually applied.</summary>
    Task<StartupRegistrationStatus> SetEnabledAsync(bool enabled);
}

/// <summary>
/// <c>HKCU\...\Run</c> registration used by the portable build.
/// </summary>
public sealed class RunKeyStartupRegistration : IStartupRegistration
{
    private readonly Func<string?> _executablePath;
    private readonly string? _runKeyPath;
    private readonly string? _valueName;

    /// <param name="executablePath">Executable to register; defaults to this process.</param>
    /// <param name="runKeyPath">Overrides the Run key path, used by tests.</param>
    /// <param name="valueName">Overrides the value name, used by tests.</param>
    public RunKeyStartupRegistration(
        Func<string?>? executablePath = null,
        string? runKeyPath = null,
        string? valueName = null)
    {
        _executablePath = executablePath ?? (() => Environment.ProcessPath);
        _runKeyPath = runKeyPath;
        _valueName = valueName;
    }

    public Task<StartupRegistrationStatus> GetStatusAsync()
    {
        var state = AutoStartRegistration.IsEnabled(_runKeyPath, _valueName)
            ? StartupRegistrationState.Enabled
            : StartupRegistrationState.Disabled;
        return Task.FromResult(new StartupRegistrationStatus(state));
    }

    public Task<StartupRegistrationStatus> SetEnabledAsync(bool enabled)
    {
        if (enabled)
        {
            var executable = _executablePath();
            if (string.IsNullOrWhiteSpace(executable))
            {
                return Task.FromResult(new StartupRegistrationStatus(
                    StartupRegistrationState.Unavailable,
                    "The executable path is not available."));
            }

            AutoStartRegistration.Enable(executable, _runKeyPath, _valueName);
        }
        else
        {
            AutoStartRegistration.Disable(_runKeyPath, _valueName);
        }

        return GetStatusAsync();
    }
}
