using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;
using GameAudioManager.Core.Startup;
using Microsoft.Win32;

namespace MsixProbe;

/// <summary>
/// Measures what the app can actually do from inside an MSIX package.
/// </summary>
/// <remarks>
/// <para>
/// Issue #39 asks whether the packaged app can still set a per-app output device
/// through the undocumented <c>Windows.Media.Internal.AudioPolicyConfig</c> API, and
/// whether the OS keeps that choice outside the package. This probe answers that
/// with the shipped <c>GameAudioManager.Core</c> implementation rather than a copy,
/// so a pass means the product code path works.
/// </para>
/// <para>
/// It never installs, signs or trusts anything; it only reads state and, in the
/// <c>route</c> mode, calls the same API the app calls.
/// </para>
/// </remarks>
internal static class Program
{
    private const int NoPackage = 15700; // APPMODEL_ERROR_NO_PACKAGE

    private static readonly JsonSerializerOptions WriteOptions = new() { WriteIndented = true };

    [STAThread]
    private static int Main(string[] args)
    {
        var result = new ProbeResult
        {
            ProcessId = Environment.ProcessId,
            ProcessPath = Environment.ProcessPath ?? string.Empty,
            BaseDirectory = AppContext.BaseDirectory,
        };

        var scenario = new ProbeScenario();
        string? explicitScenario = null;
        try
        {
            explicitScenario = args.Length > 0 && !args[0].StartsWith('-') ? args[0] : null;
            var (loaded, source, scenarioError) = ProbeScenario.Load(explicitScenario, AppContext.BaseDirectory);
            scenario = loaded;
            result.Mode = scenario.Mode;
            result.ScenarioSource = source;
            result.ScenarioError = scenarioError;

            CollectIdentity(result);
            CollectEnvironment(result);

            var devices = new CoreAudioDeviceService();
            var sessions = new CoreAudioSessionService();
            var routing = new AudioPolicyConfigRoutingService(devices);

            result.Devices = devices.GetRenderDevices()
                .Select(d => new ProbeDevice { Id = d.Id, Name = d.Name, State = d.State.ToString(), IsDefault = d.IsDefault })
                .ToList();

            result.RoutingSupported = AudioPolicyConfigRoutingService.IsSupported;
            result.RoutingAvailable = routing.IsAvailable;
            result.RoutingUnavailableMessage = routing.UnavailableMessage;
            result.TargetProcessIds = FindProcessIds(scenario.TargetExecutable);

            result.DefaultEndpointRegistry = Snapshot(DefaultEndpointKeyPath);

            switch (scenario.Mode.ToLowerInvariant())
            {
                case "route":
                    Route(result, routing, sessions, scenario);
                    break;
                case "reset":
                    Reset(result, routing, sessions, scenario);
                    break;
                case "startup":
                    Startup(result, scenario);
                    break;
                case "settings":
                    Settings(result);
                    break;
                default:
                    Observe(result, routing, sessions, scenario);
                    break;
            }

            result.DefaultEndpointRegistry = Snapshot(DefaultEndpointKeyPath);
        }
        catch (Exception ex)
        {
            result.Error = ex.ToString();
        }

        Save(result, scenario, explicitScenario);
        return result.Error is null ? 0 : 1;
    }

    private const string DefaultEndpointKeyPath = @"Software\Microsoft\Multimedia\Audio\DefaultEndpoint";

    private static void Route(ProbeResult result, AudioPolicyConfigRoutingService routing, CoreAudioSessionService sessions, ProbeScenario scenario)
    {
        if (string.IsNullOrWhiteSpace(scenario.DeviceId))
        {
            result.Error = "The scenario has no deviceId, so there is nothing to route to.";
            return;
        }

        result.SessionsBefore = SnapshotSessions(sessions, scenario.TargetExecutable);

        var set = routing.SetPreferredDevice(scenario.TargetExecutable, scenario.DeviceId);
        result.SetResultRecorded = set.Recorded.ToString();
        result.SetResultAppliedToLiveSession = set.AppliedToLiveSession.ToString();
        result.SetResultMessage = set.Message;
        result.Notes.Add("SetPreferredDevice returned; waiting before reading sessions again.");

        Wait(scenario.WaitAfterRouteSeconds);

        result.SessionsAfter = SnapshotSessions(sessions, scenario.TargetExecutable);
        result.GetPreferredDevice = routing.GetPreferredDevice(scenario.TargetExecutable);
    }

    private static void Reset(ProbeResult result, AudioPolicyConfigRoutingService routing, CoreAudioSessionService sessions, ProbeScenario scenario)
    {
        result.SessionsBefore = SnapshotSessions(sessions, scenario.TargetExecutable);

        var reset = routing.ResetToDefault(scenario.TargetExecutable);
        result.SetResultRecorded = reset.Recorded.ToString();
        result.SetResultAppliedToLiveSession = reset.AppliedToLiveSession.ToString();
        result.SetResultMessage = reset.Message;

        Wait(scenario.WaitAfterRouteSeconds);

        result.SessionsAfter = SnapshotSessions(sessions, scenario.TargetExecutable);
        result.GetPreferredDevice = routing.GetPreferredDevice(scenario.TargetExecutable);
    }

    private static void Observe(ProbeResult result, AudioPolicyConfigRoutingService routing, CoreAudioSessionService sessions, ProbeScenario scenario)
    {
        result.SessionsBefore = SnapshotSessions(sessions, scenario.TargetExecutable);
        result.GetPreferredDevice = routing.GetPreferredDevice(scenario.TargetExecutable);
    }

    /// <summary>
    /// Exercises the logon-autostart path from inside the package.
    /// </summary>
    /// <remarks>
    /// The app writes <c>HKCU\...\Run</c>. Packaged apps get their HKCU writes
    /// virtualized, so this is the check that decides whether the current autostart
    /// design survives MSIX at all.
    /// </remarks>
    private static void Startup(ProbeResult result, ProbeScenario scenario)
    {
        var executable = Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "MsixProbe.exe");
        AutoStartRegistration.Enable(executable, null, scenario.StartupValueName);

        result.StartupEnabledAfterWrite = AutoStartRegistration.IsEnabled(null, scenario.StartupValueName).ToString();
        using (var key = Registry.CurrentUser.OpenSubKey(AutoStartRegistration.DefaultRunKeyPath))
        {
            result.StartupRawValue = key?.GetValue(scenario.StartupValueName) as string;
        }

        result.RunKeyRegistry = Snapshot(AutoStartRegistration.DefaultRunKeyPath);
    }

    private static void Settings(ProbeResult result)
    {
        // Two markers: one in a directory the unpackaged app already created, one in a
        // directory that does not exist yet. MSIX file redirection sends the first to
        // the real folder (fall-through) and the second to the package LocalCache, so
        // comparing them shows whether settings would survive uninstall.
        var markers = new[]
        {
            Path.Combine(result.LocalApplicationData, "GameAudioManager", "msix-probe-marker.txt"),
            Path.Combine(result.LocalApplicationData, "GameAudioManagerMsixProbe", "msix-probe-marker.txt"),
        };

        var written = new List<string>();
        try
        {
            foreach (var marker in markers)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(marker)!);
                File.WriteAllText(marker, $"probe {DateTimeOffset.UtcNow:O} packaged={result.IsPackaged}");
                written.Add($"{marker} (exists={File.Exists(marker)})");
            }

            result.SettingsWriteResult = string.Join(" | ", written);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            result.SettingsWriteResult = $"Could not write markers ({string.Join(" | ", written)}): {ex.Message}";
        }
    }

    private static List<ProbeSession> SnapshotSessions(CoreAudioSessionService sessions, string executable)
    {
        return sessions.GetSessions(executable)
            .Select(s => new ProbeSession
            {
                ProcessId = s.ProcessId,
                ProcessName = s.ProcessName,
                DeviceId = s.DeviceId,
                DeviceName = s.DeviceName,
                IsMuted = s.IsMuted,
            })
            .ToList();
    }

    private static List<int> FindProcessIds(string executable)
    {
        var name = Path.GetFileNameWithoutExtension(executable);
        var ids = new List<int>();
        foreach (var process in Process.GetProcessesByName(name))
        {
            using (process)
            {
                ids.Add(process.Id);
            }
        }

        return ids;
    }

    private static ProbeRegistry Snapshot(string path)
    {
        var snapshot = new ProbeRegistry { Path = @"HKCU\" + path };
        using var key = Registry.CurrentUser.OpenSubKey(path);
        if (key is null)
        {
            return snapshot;
        }

        snapshot.Exists = true;
        var subKeys = key.GetSubKeyNames();
        snapshot.SubKeys.AddRange(subKeys.Take(40));

        foreach (var valueName in key.GetValueNames().Take(40))
        {
            snapshot.Values[valueName] = Describe(key.GetValue(valueName));
        }

        foreach (var childName in subKeys.Take(20))
        {
            using var child = key.OpenSubKey(childName);
            if (child is null)
            {
                continue;
            }

            var values = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var valueName in child.GetValueNames().Take(20))
            {
                values[valueName] = Describe(child.GetValue(valueName));
            }

            snapshot.Children[childName] = values;
        }

        return snapshot;
    }

    private static string Describe(object? value)
    {
        return value switch
        {
            null => "(null)",
            byte[] bytes => Convert.ToHexString(bytes),
            string text => text,
            _ => value.ToString() ?? string.Empty,
        };
    }

    private static void CollectIdentity(ProbeResult result)
    {
        var length = 0;
        var hr = GetCurrentPackageFullName(ref length, null);
        if (hr == NoPackage || length == 0)
        {
            result.IsPackaged = false;
            return;
        }

        var fullName = new char[length];
        hr = GetCurrentPackageFullName(ref length, fullName);
        if (hr != 0)
        {
            result.IsPackaged = false;
            result.Notes.Add($"GetCurrentPackageFullName failed: 0x{hr:X8}");
            return;
        }

        result.IsPackaged = true;
        result.PackageFullName = ToString(fullName, length);

        var pathLength = 0;
        _ = GetCurrentPackagePath(ref pathLength, null);
        if (pathLength > 0)
        {
            var path = new char[pathLength];
            if (GetCurrentPackagePath(ref pathLength, path) == 0)
            {
                result.PackageInstallLocation = ToString(path, pathLength);
            }
        }

        result.PackageFamilyName = DerivePackageFamilyName(result.PackageFullName);
    }

    /// <summary>
    /// PackageFamilyName is Name + "_" + the last five chars of the publisher hash.
    /// </summary>
    private static string DerivePackageFamilyName(string packageFullName)
    {
        var parts = packageFullName.Split('_');
        return parts.Length >= 5 ? $"{parts[0]}_{parts[^1]}" : packageFullName;
    }

    /// <summary>Turns a length-prefixed native string buffer into a managed string.</summary>
    private static string ToString(char[] buffer, int lengthIncludingTerminator)
    {
        var length = Math.Max(0, lengthIncludingTerminator - 1);
        while (length > 0 && buffer[length - 1] == '\0')
        {
            length--;
        }

        return new string(buffer, 0, length);
    }

    private static void CollectEnvironment(ProbeResult result)
    {
        result.LocalApplicationData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        result.SettingsPath = SettingsStore.GetDefaultPath();
        result.SettingsFileExists = File.Exists(result.SettingsPath);
    }

    private static void Wait(int seconds)
    {
        if (seconds <= 0)
        {
            return;
        }

        Thread.Sleep(TimeSpan.FromSeconds(Math.Min(seconds, 30)));
    }

    private static void Save(ProbeResult result, ProbeScenario scenario, string? explicitScenarioPath)
    {
        var target = scenario.OutPath;
        if (string.IsNullOrWhiteSpace(target))
        {
            // When the caller passed a scenario path explicitly, prefer that file's
            // OutPath so a run without args still lands where the caller expects.
            var (loaded, _, _) = ProbeScenario.Load(explicitScenarioPath, AppContext.BaseDirectory);
            target = loaded.OutPath;
        }

        if (string.IsNullOrWhiteSpace(target))
        {
            target = Path.Combine(Path.GetTempPath(), "msix-probe-result.json");
        }

        try
        {
            var directory = Path.GetDirectoryName(target);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(target, JsonSerializer.Serialize(result, WriteOptions));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Fall back somewhere the packaged process can always write, so a failed
            // run still leaves evidence behind.
            var fallback = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "GameAudioManager",
                "msix-probe-result.json");
            Directory.CreateDirectory(Path.GetDirectoryName(fallback)!);
            result.Notes.Add($"Could not write {target} ({ex.Message}); wrote {fallback} instead.");
            File.WriteAllText(fallback, JsonSerializer.Serialize(result, WriteOptions));
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
    private static extern int GetCurrentPackageFullName(ref int packageFullNameLength, [Out] char[]? packageFullName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
    private static extern int GetCurrentPackagePath(ref int pathLength, [Out] char[]? path);
}
