using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Packaging;

namespace GameAudioManager.Core.Tests;

public sealed class AppIdentityTests
{
    private const string PackageFamilyName = "tonbiattack.GameAudioManager_e28ksxe3fc9w4";
    private const string LocalAppData = @"C:\Users\test\AppData\Local";

    [Fact]
    public void Portable_UsesTheHistoricalFolder()
    {
        var identity = new AppIdentity(null, LocalAppData);

        Assert.False(identity.IsPackaged);
        Assert.False(identity.UsesSeparateSettingsPath);
        Assert.Equal(Path.Combine(LocalAppData, "GameAudioManager", "settings.json"), identity.SettingsPath);
        Assert.Equal(identity.PortableSettingsPath, identity.SettingsPath);
    }

    [Fact]
    public void Packaged_UsesPackageLocalState()
    {
        var identity = new AppIdentity(PackageFamilyName, LocalAppData);

        Assert.True(identity.IsPackaged);
        Assert.True(identity.UsesSeparateSettingsPath);
        Assert.Equal(
            Path.Combine(LocalAppData, "Packages", PackageFamilyName, "LocalState", "GameAudioManager", "settings.json"),
            identity.SettingsPath);
        Assert.Equal(
            Path.Combine(LocalAppData, "GameAudioManager", "settings.json"),
            identity.PortableSettingsPath);
    }

    [Fact]
    public void Packaged_KeepsThePortableFolderForImport()
    {
        var packaged = new AppIdentity(PackageFamilyName, LocalAppData);
        var portable = new AppIdentity(null, LocalAppData);

        // The importer reads this path, so it must stay the portable location.
        Assert.Equal(portable.SettingsPath, packaged.PortableSettingsPath);
        Assert.Equal(portable.SettingsDirectory, Path.GetDirectoryName(packaged.PortableSettingsPath));
    }

    [Fact]
    public void SingleInstanceName_IsSeparatePerChannel()
    {
        var portable = new AppIdentity(null, LocalAppData);
        var packaged = new AppIdentity(PackageFamilyName, LocalAppData);

        Assert.Equal(AppIdentity.SingleInstanceBaseName, portable.SingleInstanceName);
        Assert.NotEqual(portable.SingleInstanceName, packaged.SingleInstanceName);
        Assert.Contains(PackageFamilyName, packaged.SingleInstanceName, StringComparison.Ordinal);

        // Two packaged builds must not collide either, so the name has to carry the identity.
        var otherPackage = new AppIdentity("tonbiattack.GameAudioManager_otheros4h2abc", LocalAppData);
        Assert.NotEqual(packaged.SingleInstanceName, otherPackage.SingleInstanceName);
    }

    [Fact]
    public void SingleInstanceName_DoesNotContainAPathSeparator()
    {
        // A backslash would make the mutex a different namespace than the one the guard builds.
        var packaged = new AppIdentity(PackageFamilyName, LocalAppData);

        Assert.DoesNotContain('\\', packaged.SingleInstanceName);
    }

    [Fact]
    public void Detect_ReturnsAPathEvenWithoutPackageIdentity()
    {
        var identity = AppIdentity.Detect();

        Assert.False(string.IsNullOrWhiteSpace(identity.LocalApplicationData));
        Assert.Equal(identity.IsPackaged, identity.PackageFamilyName is not null);
    }
}
