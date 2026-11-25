using System.Text.Json;
using GameAudioManager.Core.Audio;

namespace GameAudioManager.Core.Configuration;

/// <summary>
/// Imports the PowerShell version's <c>games.json</c> / <c>settings.json</c>.
/// </summary>
/// <remarks>
/// The old format stores device *names* (SoundVolumeView "Device Name" strings).
/// Names are not stable, so each name is resolved to a device id when the device is
/// currently present. Names that cannot be resolved are kept verbatim and reported,
/// never silently dropped: the user may simply have the headset unplugged.
/// </remarks>
public static class LegacyImporter
{
    public sealed record ImportResult(
        AppSettings Settings,
        IReadOnlyList<string> ResolvedDevices,
        IReadOnlyList<string> UnresolvedDevices);

    public static ImportResult Import(string gamesJsonPath, string? settingsJsonPath, IAudioDeviceService devices)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(gamesJsonPath);
        ArgumentNullException.ThrowIfNull(devices);

        var settings = new AppSettings();
        var resolved = new List<string>();
        var unresolved = new List<string>();

        if (File.Exists(settingsJsonPath))
        {
            TryReadSettings(settingsJsonPath!, settings);
        }

        if (!File.Exists(gamesJsonPath))
        {
            return new ImportResult(settings, resolved, unresolved);
        }

        using var document = JsonDocument.Parse(File.ReadAllText(gamesJsonPath));
        if (!document.RootElement.TryGetProperty("games", out var games) || games.ValueKind != JsonValueKind.Array)
        {
            return new ImportResult(settings, resolved, unresolved);
        }

        var available = devices.GetRenderDevices();

        foreach (var game in games.EnumerateArray())
        {
            var processName = ReadString(game, "processName");
            if (string.IsNullOrWhiteSpace(processName))
            {
                continue;
            }

            var rule = new AppRule
            {
                ProcessName = processName!,
                Name = ReadString(game, "name") ?? processName!,
                Enabled = ReadBool(game, "enabled") ?? true,
            };

            if (game.TryGetProperty("outputDevices", out var outputDevices) && outputDevices.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in outputDevices.EnumerateArray())
                {
                    if (entry.ValueKind != JsonValueKind.String)
                    {
                        continue;
                    }

                    var name = entry.GetString();
                    if (string.IsNullOrWhiteSpace(name))
                    {
                        continue;
                    }

                    var match = available.FirstOrDefault(d =>
                        string.Equals(d.Name, name, StringComparison.OrdinalIgnoreCase));

                    if (match is not null)
                    {
                        rule.OutputDeviceIds.Add(match.Id);
                        resolved.Add(name!);
                    }
                    else
                    {
                        // Keep the original text so the rule survives an unplugged device.
                        rule.OutputDeviceIds.Add(name!);
                        unresolved.Add(name!);
                    }
                }
            }

            settings.Rules.Add(rule);
        }

        return new ImportResult(settings, resolved, unresolved);
    }

    private static void TryReadSettings(string path, AppSettings settings)
    {
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;

            if (root.TryGetProperty("watchIntervalSeconds", out var interval) && interval.TryGetInt32(out var seconds))
            {
                settings.WatchIntervalSeconds = Math.Clamp(seconds, 1, 3600);
            }

            if (root.TryGetProperty("autoStartWatcher", out var autoStart) && autoStart.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                settings.AutoStartWatcher = autoStart.GetBoolean();
            }
        }
        catch (JsonException)
        {
            // Ignore a corrupt legacy settings file; the games file is the valuable part.
        }
    }

    private static string? ReadString(JsonElement element, string name)
    {
        return element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
    }

    private static bool? ReadBool(JsonElement element, string name)
    {
        return element.TryGetProperty(name, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : null;
    }
}
