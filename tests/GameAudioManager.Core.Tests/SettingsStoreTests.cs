using System.Text.Json;
using GameAudioManager.Core.Configuration;

namespace GameAudioManager.Core.Tests;

public sealed class SettingsStoreTests : IDisposable
{
    private readonly string _directory;

    public SettingsStoreTests()
    {
        _directory = Path.Combine(Path.GetTempPath(), "gam-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_directory);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private string PathFor(string name) => Path.Combine(_directory, name);

    [Fact]
    public void Load_MissingFileReturnsDefaults()
    {
        var store = new SettingsStore(PathFor("settings.json"));

        var settings = store.Load();

        Assert.Equal(5, settings.WatchIntervalSeconds);
        Assert.False(settings.AutoStartWatcher);
        Assert.Empty(settings.Rules);
    }

    [Fact]
    public void Save_RoundTripsAllFields()
    {
        var store = new SettingsStore(PathFor("settings.json"));
        var settings = new AppSettings
        {
            WatchIntervalSeconds = 12,
            AutoStartWatcher = true,
            AutoStartWithWindows = true,
            StartMinimized = true,
            Rules =
            {
                new AppRule
                {
                    Name = "Game",
                    ProcessName = "GameExecutable",
                    OutputDeviceIds = { "dev-1", "dev-2" },
                    Enabled = true,
                    AutoApply = false,
                },
            },
        };

        store.Save(settings);
        var loaded = store.Load();

        Assert.Equal(12, loaded.WatchIntervalSeconds);
        Assert.True(loaded.AutoStartWatcher);
        Assert.True(loaded.AutoStartWithWindows);
        Assert.True(loaded.StartMinimized);
        var rule = Assert.Single(loaded.Rules);
        Assert.Equal("GameExecutable", rule.ProcessName);
        Assert.Equal(new[] { "dev-1", "dev-2" }, rule.OutputDeviceIds);
        Assert.False(rule.AutoApply);
    }

    [Fact]
    public void Save_CreatesMissingDirectory()
    {
        var nested = Path.Combine(_directory, "a", "b", "settings.json");
        var store = new SettingsStore(nested);

        store.Save(new AppSettings());

        Assert.True(File.Exists(nested));
    }

    [Fact]
    public void Save_LeavesNoTemporaryFileBehind()
    {
        var path = PathFor("settings.json");
        var store = new SettingsStore(path);

        store.Save(new AppSettings());

        Assert.False(File.Exists(path + ".tmp"));
    }

    [Fact]
    public void Load_CorruptFileFallsBackToDefaultsAndPreservesCopy()
    {
        var path = PathFor("settings.json");
        File.WriteAllText(path, "{ this is not json ");
        var store = new SettingsStore(path);

        var settings = store.Load();

        Assert.Empty(settings.Rules);
        Assert.Equal(5, settings.WatchIntervalSeconds);
        Assert.NotEmpty(Directory.GetFiles(_directory, "settings.json.corrupt-*"));
    }

    [Fact]
    public void Save_SerializesWithCamelCasePropertyNames()
    {
        var path = PathFor("settings.json");
        var store = new SettingsStore(path);

        store.Save(new AppSettings { WatchIntervalSeconds = 7 });

        using var document = JsonDocument.Parse(File.ReadAllText(path));
        Assert.True(document.RootElement.TryGetProperty("watchIntervalSeconds", out var value));
        Assert.Equal(7, value.GetInt32());
    }
}
