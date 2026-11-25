using System.Diagnostics;
using System.Globalization;
using GameAudioManager.Core.Audio;
using Microsoft.Win32;

namespace GameAudioManager.Core.Routing;

/// <summary>
/// Per-application output routing.
/// </summary>
/// <remarks>
/// <para>
/// Windows has no <em>documented</em> API for setting another application's output
/// endpoint. The supported-looking UI does it through the undocumented
/// <c>AudioPolicyConfig</c> interfaces, and the setting is persisted under
/// <c>HKCU\Software\Microsoft\Multimedia\Audio\DefaultEndpoint</c> keyed by an
/// undocumented hash of the executable path.
/// </para>
/// <para>
/// This implementation therefore:
/// </para>
/// <list type="bullet">
/// <item>reads the recorded preference natively from that registry key, and</item>
/// <item>writes it by invoking the bundled SoundVolumeCommandLine (<c>svcl.exe</c>),
/// which performs the undocumented call for us.</item>
/// </list>
/// <para>
/// The write dependency is the reason the Microsoft Store packaging task (#35) is
/// blocked: an external helper executable cannot be shipped in an MSIX package that
/// passes certification, and registry writes from a packaged app are virtualized so
/// the audio service would not observe them.
/// </para>
/// </remarks>
public sealed class AppRoutingService : IAppRoutingService
{
    private const string DefaultEndpointKeyPath = @"Software\Microsoft\Multimedia\Audio\DefaultEndpoint";

    private readonly string _svclPath;
    private readonly IAudioDeviceService _deviceService;

    public AppRoutingService(string svclPath, IAudioDeviceService deviceService)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(svclPath);
        _svclPath = svclPath;
        _deviceService = deviceService ?? throw new ArgumentNullException(nameof(deviceService));
    }

    public RoutingResult SetPreferredDevice(string executableName, string deviceId)
    {
        var (exe, device) = Validate(executableName, deviceId);

        // Reject an unknown device before touching the OS. svcl.exe exits 0 even
        // for a device name it cannot resolve, which is how issue #27 happened.
        var target = _deviceService.GetRenderDevices()
            .FirstOrDefault(d => string.Equals(d.Id, device, StringComparison.OrdinalIgnoreCase));
        if (target is null)
        {
            return RoutingResult.NotRecorded($"Output device was not found: '{device}'.");
        }

        if (!target.IsActive)
        {
            return RoutingResult.NotRecorded($"Output device is not active: '{target.Name}'.");
        }

        var exitCode = RunSvcl("/SetAppDefault", target.Name, "all", exe);
        if (exitCode != 0)
        {
            return RoutingResult.NotRecorded($"svcl.exe failed with exit code {exitCode}.");
        }

        return RoutingResult.RecordedPendingSession(
            $"Recorded '{target.Name}' for {exe}. Windows applies it the next time the application creates an audio session.");
    }

    public RoutingResult ResetToDefault(string executableName)
    {
        var exe = NormalizeExecutable(executableName);
        var exitCode = RunSvcl("/SetAppDefault", "DefaultRenderDevice", "all", exe);
        if (exitCode != 0)
        {
            return RoutingResult.NotRecorded($"svcl.exe failed with exit code {exitCode}.");
        }

        return RoutingResult.RecordedPendingSession(
            $"{exe} now follows the Windows default output device.");
    }

    public string? GetPreferredDevice(string executableName)
    {
        var exe = NormalizeExecutable(executableName);

        using var root = Registry.CurrentUser.OpenSubKey(DefaultEndpointKeyPath);
        if (root is null)
        {
            return null;
        }

        // The key name is an undocumented hash of the path, so locate the entry by
        // its stored executable path and read the endpoint it points at.
        foreach (var subKeyName in root.GetSubKeyNames())
        {
            using var subKey = root.OpenSubKey(subKeyName);
            if (subKey is null)
            {
                continue;
            }

            var storedPath = subKey.GetValue(null) as string;
            if (string.IsNullOrEmpty(storedPath)
                || !string.Equals(Path.GetFileName(storedPath), exe, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var endpoint = FindEndpointValue(subKey);
            if (endpoint is null)
            {
                continue;
            }

            // The stored value is an MMDevice interface path; match it against the
            // enumerated devices so callers get a device id, not a registry blob.
            return _deviceService.GetRenderDevices()
                .FirstOrDefault(d => endpoint.Contains(ExtractEndpointToken(d.Id), StringComparison.OrdinalIgnoreCase))
                ?.Id;
        }

        return null;
    }

    private static string? FindEndpointValue(RegistryKey subKey)
    {
        // Values are named <nnn>_<role> with a matching <nnn>_<role>_p policy guid.
        // Role 000 is the one SoundVolumeView writes for "all".
        foreach (var name in subKey.GetValueNames())
        {
            if (string.IsNullOrEmpty(name) || name.EndsWith("_p", StringComparison.Ordinal) || name == "0")
            {
                continue;
            }

            if (subKey.GetValue(name) is string value && value.Contains("MMDEVAPI", StringComparison.OrdinalIgnoreCase))
            {
                return value;
            }
        }

        return null;
    }

    /// <summary>
    /// Extracts the "{0.0.0.xxxxxxxx}.{guid}" token that appears both in an MMDevice
    /// id and in the stored registry value.
    /// </summary>
    internal static string ExtractEndpointToken(string deviceId)
    {
        var start = deviceId.IndexOf('{', StringComparison.Ordinal);
        if (start < 0)
        {
            return deviceId;
        }

        var secondClose = deviceId.IndexOf('}', deviceId.IndexOf('}', start) + 1);
        if (secondClose < 0)
        {
            return deviceId[start..];
        }

        return deviceId[start..(secondClose + 1)];
    }

    private static (string Executable, string DeviceId) Validate(string executableName, string deviceId)
    {
        var exe = NormalizeExecutable(executableName);
        if (string.IsNullOrWhiteSpace(deviceId))
        {
            throw new ArgumentException("A device id is required.", nameof(deviceId));
        }

        return (exe, deviceId.Trim());
    }

    internal static string NormalizeExecutable(string executableName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executableName);
        var name = Path.GetFileName(executableName.Trim());
        if (!name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
        {
            name += ".exe";
        }

        return name;
    }

    private int RunSvcl(params string[] arguments)
    {
        if (!File.Exists(_svclPath))
        {
            throw new FileNotFoundException($"svcl.exe was not found: {_svclPath}", _svclPath);
        }

        var startInfo = new ProcessStartInfo(_svclPath)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"Could not start {_svclPath}.");

        _ = process.StandardOutput.ReadToEnd();
        _ = process.StandardError.ReadToEnd();

        if (!process.WaitForExit(TimeSpan.FromSeconds(30)))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
                // Already exited.
            }

            throw new TimeoutException("svcl.exe did not finish within 30 seconds.");
        }

        return process.ExitCode;
    }

    internal static string FormatInvariant(string format, params object[] args)
    {
        return string.Format(CultureInfo.InvariantCulture, format, args);
    }
}
