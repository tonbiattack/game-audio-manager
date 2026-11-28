using System.Text.Json;
using System.Text.Json.Serialization;

namespace MsixProbe;

/// <summary>
/// What the probe should exercise in this run.
/// </summary>
/// <remarks>
/// The packaged app cannot receive command-line arguments when it is started from
/// the Start menu or <c>shell:AppsFolder</c>, so the scenario lives in a file next
/// to the executable. <see cref="ScenarioPath"/> points at a file outside the package
/// so a run can be re-configured without repacking.
/// </remarks>
internal sealed class ProbeScenario
{
    /// <summary>Absolute path of the scenario file to read instead of the packaged defaults.</summary>
    public string? ScenarioPath { get; set; }

    /// <summary>route | reset | observe | startup | settings</summary>
    public string Mode { get; set; } = "observe";

    public string TargetExecutable { get; set; } = "powershell.exe";

    /// <summary>Device id as returned by IMMDevice::GetId, or a full SWD\MMDEVAPI path.</summary>
    public string? DeviceId { get; set; }

    /// <summary>Seconds to wait after changing routing before sessions are read again.</summary>
    public int WaitAfterRouteSeconds { get; set; } = 3;

    /// <summary>Where the JSON result is written. Absolute, outside any package folder.</summary>
    public string? OutPath { get; set; }

    /// <summary>Name used for the HKCU\...\Run test value.</summary>
    public string StartupValueName { get; set; } = "GameAudioManagerProbe";

    private static readonly JsonSerializerOptions ReadOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    /// <summary>
    /// Loads the scenario. An explicit path wins, then the packaged default file, and
    /// a packaged default may point somewhere else for re-configuration.
    /// </summary>
    public static (ProbeScenario Scenario, string Source, string? Error) Load(string? explicitPath, string baseDirectory)
    {
        var candidates = new List<string>();
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            candidates.Add(explicitPath);
        }

        candidates.Add(Path.Combine(baseDirectory, "probe-config.json"));

        foreach (var candidate in candidates)
        {
            if (!File.Exists(candidate))
            {
                continue;
            }

            try
            {
                var scenario = JsonSerializer.Deserialize<ProbeScenario>(File.ReadAllText(candidate), ReadOptions)
                    ?? new ProbeScenario();

                if (!string.IsNullOrWhiteSpace(scenario.ScenarioPath)
                    && !string.Equals(scenario.ScenarioPath, candidate, StringComparison.OrdinalIgnoreCase)
                    && File.Exists(scenario.ScenarioPath))
                {
                    var redirected = JsonSerializer.Deserialize<ProbeScenario>(File.ReadAllText(scenario.ScenarioPath), ReadOptions)
                        ?? new ProbeScenario();
                    return (redirected, scenario.ScenarioPath, null);
                }

                return (scenario, candidate, null);
            }
            catch (JsonException ex)
            {
                return (new ProbeScenario(), candidate, $"Could not parse {candidate}: {ex.Message}");
            }
            catch (IOException ex)
            {
                return (new ProbeScenario(), candidate, $"Could not read {candidate}: {ex.Message}");
            }
        }

        return (new ProbeScenario(), "(none)", "No scenario file was found.");
    }
}

internal sealed class ProbeResult
{
    public string StartedUtc { get; set; } = DateTimeOffset.UtcNow.ToString("O");

    public string Mode { get; set; } = string.Empty;

    public string ScenarioSource { get; set; } = string.Empty;

    public string? ScenarioError { get; set; }

    public int ProcessId { get; set; }

    public string ProcessPath { get; set; } = string.Empty;

    public string BaseDirectory { get; set; } = string.Empty;

    /// <summary>True when the process has package identity (started through the app model).</summary>
    public bool IsPackaged { get; set; }

    public string PackageFullName { get; set; } = string.Empty;

    public string PackageFamilyName { get; set; } = string.Empty;

    public string PackageInstallLocation { get; set; } = string.Empty;

    public string LocalApplicationData { get; set; } = string.Empty;

    public string SettingsPath { get; set; } = string.Empty;

    public bool SettingsFileExists { get; set; }

    public List<ProbeDevice> Devices { get; set; } = new();

    public bool RoutingSupported { get; set; }

    public bool RoutingAvailable { get; set; }

    public string? RoutingUnavailableMessage { get; set; }

    public List<int> TargetProcessIds { get; set; } = new();

    public List<ProbeSession> SessionsBefore { get; set; } = new();

    public List<ProbeSession> SessionsAfter { get; set; } = new();

    public string? SetResultRecorded { get; set; }

    public string? SetResultAppliedToLiveSession { get; set; }

    public string? SetResultMessage { get; set; }

    public string? GetPreferredDevice { get; set; }

    public ProbeRegistry? DefaultEndpointRegistry { get; set; }

    public ProbeRegistry? RunKeyRegistry { get; set; }

    public string? StartupEnabledAfterWrite { get; set; }

    public string? StartupRawValue { get; set; }

    public string? SettingsWriteResult { get; set; }

    public List<string> Notes { get; set; } = new();

    public string? Error { get; set; }
}

internal sealed class ProbeDevice
{
    public string Id { get; set; } = string.Empty;

    public string Name { get; set; } = string.Empty;

    public string State { get; set; } = string.Empty;

    public bool IsDefault { get; set; }
}

internal sealed class ProbeSession
{
    public uint ProcessId { get; set; }

    public string? ProcessName { get; set; }

    public string DeviceId { get; set; } = string.Empty;

    public string? DeviceName { get; set; }

    public bool IsMuted { get; set; }
}

/// <summary>Flat copy of a registry key so the outside can compare it with the package's own view.</summary>
internal sealed class ProbeRegistry
{
    public string Path { get; set; } = string.Empty;

    public bool Exists { get; set; }

    public List<string> SubKeys { get; set; } = new();

    public Dictionary<string, string> Values { get; set; } = new(StringComparer.Ordinal);

    /// <summary>Sub key name -&gt; (value name -&gt; data), one level deep, for the per-app endpoint store.</summary>
    public Dictionary<string, Dictionary<string, string>> Children { get; set; } = new(StringComparer.Ordinal);

    [JsonIgnore]
    public string Display => $"{Path} (exists={Exists}, subKeys={SubKeys.Count}, values={Values.Count})";
}
