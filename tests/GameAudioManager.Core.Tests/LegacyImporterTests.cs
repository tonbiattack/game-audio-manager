using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;

namespace GameAudioManager.Core.Tests;

public sealed class LegacyImporterTests : IDisposable
{
    private readonly string _directory;

    public LegacyImporterTests()
    {
        _directory = Path.Combine(Path.GetTempPath(), "gam-import-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_directory);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private sealed class FakeDeviceService : IAudioDeviceService
    {
        public List<AudioDevice> Devices { get; } = new();

        public IReadOnlyList<AudioDevice> GetRenderDevices() => Devices;

        public AudioDevice? FindById(string deviceId)
            => Devices.FirstOrDefault(d => string.Equals(d.Id, deviceId, StringComparison.OrdinalIgnoreCase));
    }

    private string WriteFile(string name, string content)
    {
        var path = Path.Combine(_directory, name);
        File.WriteAllText(path, content);
        return path;
    }

    [Fact]
    public void Import_ResolvesDeviceNamesToIds()
    {
        var devices = new FakeDeviceService();
        devices.Devices.Add(new AudioDevice("id-usb", "4- USB Audio Device", AudioDeviceState.Active, false));

        var games = WriteFile("games.json", """
            {
              "games": [
                {
                  "name": "Chrome",
                  "processName": "chrome",
                  "outputDevices": ["4- USB Audio Device"],
                  "enabled": true
                }
              ]
            }
            """);

        var result = LegacyImporter.Import(games, settingsJsonPath: null, devices);

        var rule = Assert.Single(result.Settings.Rules);
        Assert.Equal("chrome", rule.ProcessName);
        Assert.Equal("Chrome", rule.Name);
        Assert.Equal(new[] { "id-usb" }, rule.OutputDeviceIds);
        Assert.Equal(new[] { "4- USB Audio Device" }, result.ResolvedDevices);
        Assert.Empty(result.UnresolvedDevices);
    }

    [Fact]
    public void Import_KeepsUnresolvedNamesVerbatim()
    {
        var devices = new FakeDeviceService();

        var games = WriteFile("games.json", """
            {
              "games": [
                {
                  "name": "Game",
                  "processName": "game",
                  "outputDevices": ["Disconnected Headset"],
                  "enabled": true
                }
              ]
            }
            """);

        var result = LegacyImporter.Import(games, null, devices);

        var rule = Assert.Single(result.Settings.Rules);
        Assert.Equal(new[] { "Disconnected Headset" }, rule.OutputDeviceIds);
        Assert.Empty(result.ResolvedDevices);
        Assert.Equal(new[] { "Disconnected Headset" }, result.UnresolvedDevices);
    }

    [Fact]
    public void Import_PreservesCandidateOrder()
    {
        var devices = new FakeDeviceService();
        devices.Devices.Add(new AudioDevice("id-a", "A", AudioDeviceState.Active, false));
        devices.Devices.Add(new AudioDevice("id-b", "B", AudioDeviceState.Active, false));

        var games = WriteFile("games.json", """
            { "games": [ { "name": "G", "processName": "g", "outputDevices": ["B", "A"] } ] }
            """);

        var result = LegacyImporter.Import(games, null, devices);

        Assert.Equal(new[] { "id-b", "id-a" }, result.Settings.Rules[0].OutputDeviceIds);
    }

    [Fact]
    public void Import_MatchesDeviceNamesCaseInsensitively()
    {
        var devices = new FakeDeviceService();
        devices.Devices.Add(new AudioDevice("id-a", "Speakers", AudioDeviceState.Active, false));

        var games = WriteFile("games.json", """
            { "games": [ { "name": "G", "processName": "g", "outputDevices": ["speakers"] } ] }
            """);

        var result = LegacyImporter.Import(games, null, devices);

        Assert.Equal(new[] { "id-a" }, result.Settings.Rules[0].OutputDeviceIds);
    }

    [Fact]
    public void Import_ReadsLegacySettings()
    {
        var devices = new FakeDeviceService();
        var games = WriteFile("games.json", """{ "games": [] }""");
        var settings = WriteFile("settings.json", """{ "watchIntervalSeconds": 9, "autoStartWatcher": true }""");

        var result = LegacyImporter.Import(games, settings, devices);

        Assert.Equal(9, result.Settings.WatchIntervalSeconds);
        Assert.True(result.Settings.AutoStartWatcher);
    }

    [Fact]
    public void Import_SkipsRulesWithoutProcessName()
    {
        var devices = new FakeDeviceService();
        var games = WriteFile("games.json", """
            { "games": [ { "name": "NoProcess", "outputDevices": ["A"] } ] }
            """);

        var result = LegacyImporter.Import(games, null, devices);

        Assert.Empty(result.Settings.Rules);
    }

    [Fact]
    public void Import_MissingGamesFileReturnsEmptySettings()
    {
        var devices = new FakeDeviceService();

        var result = LegacyImporter.Import(Path.Combine(_directory, "missing.json"), null, devices);

        Assert.Empty(result.Settings.Rules);
    }

    [Fact]
    public void Import_ToleratesCorruptLegacySettingsFile()
    {
        var devices = new FakeDeviceService();
        var games = WriteFile("games.json", """{ "games": [] }""");
        var settings = WriteFile("settings.json", "not json at all");

        var result = LegacyImporter.Import(games, settings, devices);

        Assert.Equal(5, result.Settings.WatchIntervalSeconds);
    }
}
