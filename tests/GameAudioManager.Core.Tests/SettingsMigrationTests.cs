using GameAudioManager.Core.Configuration;

namespace GameAudioManager.Core.Tests;

public sealed class SettingsMigrationTests : IDisposable
{
    private readonly string _directory;

    public SettingsMigrationTests()
    {
        _directory = Path.Combine(Path.GetTempPath(), "gam-migration-" + Guid.NewGuid().ToString("N"));
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

    private string WritePortableSettings(string name = "portable.json", string processName = "ShirenTheWanderer6.exe")
    {
        var path = PathFor(name);
        var store = new SettingsStore(path);
        store.Save(new AppSettings
        {
            Theme = ThemeNames.Dark,
            Language = "ja",
            Rules =
            {
                new AppRule { Name = "Shiren 6", ProcessName = processName, OutputDeviceIds = { "device-a" } },
            },
        });
        return path;
    }

    [Fact]
    public void Import_CopiesRulesFromThePortableBuild()
    {
        var source = WritePortableSettings();
        var target = new SettingsStore(PathFor("packaged.json"));

        var outcome = SettingsMigration.ImportIfMissing(target, source);

        Assert.Equal(SettingsMigration.Outcome.Imported, outcome);
        var imported = target.Load();
        Assert.Equal(ThemeNames.Dark, imported.Theme);
        Assert.Single(imported.Rules);
        Assert.Equal("ShirenTheWanderer6.exe", imported.Rules[0].ProcessName);
    }

    [Fact]
    public void Import_DoesNotOverwriteExistingSettings()
    {
        var source = WritePortableSettings();
        var targetPath = PathFor("packaged.json");
        var target = new SettingsStore(targetPath);
        target.Save(new AppSettings { Theme = ThemeNames.Light });

        var outcome = SettingsMigration.ImportIfMissing(target, source);

        Assert.Equal(SettingsMigration.Outcome.AlreadyPresent, outcome);
        var kept = target.Load();
        Assert.Equal(ThemeNames.Light, kept.Theme);
        Assert.Empty(kept.Rules);
    }

    [Fact]
    public void Import_WithoutPortableSettingsIsANoOp()
    {
        var target = new SettingsStore(PathFor("packaged.json"));

        var outcome = SettingsMigration.ImportIfMissing(target, PathFor("missing.json"));

        Assert.Equal(SettingsMigration.Outcome.NoSource, outcome);
        Assert.False(File.Exists(target.Path));
    }

    [Fact]
    public void Import_LeavesAnUnreadableFileAlone()
    {
        var source = PathFor("broken.json");
        File.WriteAllText(source, "{ this is not json");
        var target = new SettingsStore(PathFor("packaged.json"));

        var outcome = SettingsMigration.ImportIfMissing(target, source);

        Assert.Equal(SettingsMigration.Outcome.SourceUnreadable, outcome);
        Assert.False(File.Exists(target.Path));
        // The original must survive so the user can repair it.
        Assert.True(File.Exists(source));
    }

    [Fact]
    public void Import_SamePathIsANoOp()
    {
        var source = WritePortableSettings();
        var store = new SettingsStore(source);

        var outcome = SettingsMigration.ImportIfMissing(store, source);

        // The target already exists, so this is reported as present rather than copied onto itself.
        Assert.Equal(SettingsMigration.Outcome.AlreadyPresent, outcome);
    }
}
