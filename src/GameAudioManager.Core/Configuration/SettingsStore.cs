using System.Text.Json;
using System.Text.Json.Serialization;

namespace GameAudioManager.Core.Configuration;

/// <summary>Loads and saves <see cref="AppSettings"/> in a user-writable location.</summary>
public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    private readonly string _path;

    public SettingsStore(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        _path = path;
    }

    public string Path => _path;

    /// <summary>
    /// Default location: %LOCALAPPDATA%\GameAudioManager\settings.json.
    /// Never the installation directory, which may be read-only (and is not writable
    /// at all inside an MSIX package).
    /// </summary>
    public static string GetDefaultPath()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return System.IO.Path.Combine(root, "GameAudioManager", "settings.json");
    }

    public AppSettings Load()
    {
        if (!File.Exists(_path))
        {
            return new AppSettings();
        }

        try
        {
            var json = File.ReadAllText(_path);
            return JsonSerializer.Deserialize<AppSettings>(json, SerializerOptions) ?? new AppSettings();
        }
        catch (JsonException)
        {
            // A corrupt file must not prevent the app from starting; keep a copy so
            // the user can recover it, then fall back to defaults.
            TryPreserveCorruptFile();
            return new AppSettings();
        }
    }

    /// <summary>
    /// Copies the current settings file next to itself with a timestamp suffix.
    /// </summary>
    /// <returns>The backup path, or null when there was nothing to back up.</returns>
    /// <remarks>
    /// Used before importing another configuration so a bad import cannot destroy the
    /// user's existing rules.
    /// </remarks>
    public string? Backup()
    {
        if (!File.Exists(_path))
        {
            return null;
        }

        var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture);
        var backupPath = _path + "." + stamp + ".bak";
        File.Copy(_path, backupPath, overwrite: true);
        return backupPath;
    }

    public void Save(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        var directory = System.IO.Path.GetDirectoryName(_path);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        // Write then move so a crash cannot leave a half-written settings file.
        var temporaryPath = _path + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(settings, SerializerOptions));
        File.Move(temporaryPath, _path, overwrite: true);
    }

    private void TryPreserveCorruptFile()
    {
        try
        {
            var backup = _path + ".corrupt-" + DateTime.UtcNow.ToString("yyyyMMddHHmmss", System.Globalization.CultureInfo.InvariantCulture);
            File.Copy(_path, backup, overwrite: true);
        }
        catch (IOException)
        {
            // Best effort only.
        }
        catch (UnauthorizedAccessException)
        {
            // Best effort only.
        }
    }
}

