namespace GameAudioManager.Core.Configuration;

/// <summary>
/// Copies settings from the portable build into the packaged build once.
/// </summary>
/// <remarks>
/// The two builds keep their settings in different places (see
/// <see cref="Packaging.AppIdentity"/>), so an upgrade from GitHub Releases to the
/// Store would otherwise present an empty rule list. The import only runs when the
/// target file does not exist yet; it never overwrites and never deletes the source.
/// </remarks>
public static class SettingsMigration
{
    /// <summary>Outcome of <see cref="ImportIfMissing"/>.</summary>
    public enum Outcome
    {
        /// <summary>Target settings already existed; nothing was copied.</summary>
        AlreadyPresent,

        /// <summary>There was no portable settings file to import.</summary>
        NoSource,

        /// <summary>The portable file exists but could not be parsed, so it was left alone.</summary>
        SourceUnreadable,

        /// <summary>The portable settings were copied.</summary>
        Imported,
    }

    /// <summary>
    /// Imports <paramref name="sourcePath"/> into <paramref name="target"/> when the target
    /// has no settings yet.
    /// </summary>
    public static Outcome ImportIfMissing(SettingsStore target, string sourcePath)
    {
        ArgumentNullException.ThrowIfNull(target);
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);

        if (File.Exists(target.Path))
        {
            return Outcome.AlreadyPresent;
        }

        if (!File.Exists(sourcePath)
            || string.Equals(Path.GetFullPath(target.Path), Path.GetFullPath(sourcePath), StringComparison.OrdinalIgnoreCase))
        {
            return Outcome.NoSource;
        }

        var source = new SettingsStore(sourcePath);
        if (!source.TryLoad(out var settings))
        {
            return Outcome.SourceUnreadable;
        }

        target.Save(settings);
        return Outcome.Imported;
    }
}
