using System.Runtime.InteropServices;

namespace GameAudioManager.Core.Packaging;

/// <summary>
/// Where this process is running from: a plain executable or an MSIX package.
/// </summary>
/// <remarks>
/// <para>
/// The packaged build must not share user state with the portable build: MSIX
/// virtualizes <c>HKCU</c> and redirects writes into folders it does not already own,
/// so the same path silently means two different places depending on how the app was
/// started. Resolving both paths from one place keeps settings and the single-instance
/// mutex consistent per distribution channel.
/// </para>
/// <para>
/// Package identity comes from <c>GetCurrentPackageFamilyName</c> rather than from
/// WinRT so that this stays usable from the command-line probe and from unit tests.
/// </para>
/// </remarks>
public sealed record AppIdentity(string? PackageFamilyName, string LocalApplicationData)
{
    /// <summary>Folder name used under <c>%LOCALAPPDATA%</c> by the portable build.</summary>
    public const string SettingsFolderName = "GameAudioManager";

    /// <summary>Mutex name used by the portable build (without the <c>Local\</c> prefix).</summary>
    public const string SingleInstanceBaseName = "GameAudioManager.SingleInstance";

    /// <summary>True when the process has package identity (started through the app model).</summary>
    public bool IsPackaged => !string.IsNullOrWhiteSpace(PackageFamilyName);

    /// <summary>
    /// Settings directory for this process.
    /// </summary>
    /// <remarks>
    /// The packaged build uses the package's <c>LocalState</c>. It survives updates and
    /// is removed on uninstall, which is the behaviour the Store expects; the portable
    /// build keeps its historical folder so existing users are unaffected.
    /// </remarks>
    public string SettingsDirectory => IsPackaged
        ? Path.Combine(LocalApplicationData, "Packages", PackageFamilyName!, "LocalState", SettingsFolderName)
        : Path.Combine(LocalApplicationData, SettingsFolderName);

    /// <summary>Full path of <c>settings.json</c> for this process.</summary>
    public string SettingsPath => Path.Combine(SettingsDirectory, "settings.json");

    /// <summary>
    /// Settings path used by the portable build, kept so the packaged build can import
    /// it once when a user moves from GitHub Releases to the Store.
    /// </summary>
    public string PortableSettingsPath => Path.Combine(LocalApplicationData, SettingsFolderName, "settings.json");

    /// <summary>
    /// True when this process keeps its settings somewhere other than the portable
    /// location, so a one-time import is possible.
    /// </summary>
    public bool UsesSeparateSettingsPath => IsPackaged
        && !string.Equals(SettingsPath, PortableSettingsPath, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Single-instance mutex name for this process, without the <c>Local\</c> prefix.
    /// </summary>
    /// <remarks>
    /// Keeping the packaged and portable builds on different names lets both run at
    /// the same time during a migration instead of the second one silently exiting.
    /// Two copies still fight over routing, so the UI and docs say not to run both.
    /// </remarks>
    public string SingleInstanceName => IsPackaged
        ? SingleInstanceBaseName + "." + PackageFamilyName
        : SingleInstanceBaseName;

    /// <summary>Detects whether the current process runs with package identity.</summary>
    public static AppIdentity Detect()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return new AppIdentity(TryGetPackageFamilyName(), localAppData);
    }

    private const int NoPackage = 15700; // APPMODEL_ERROR_NO_PACKAGE

    private static string? TryGetPackageFamilyName()
    {
        var length = 0;
        var result = GetCurrentPackageFamilyName(ref length, null);
        if (result == NoPackage || length <= 0)
        {
            return null;
        }

        var buffer = new char[length];
        result = GetCurrentPackageFamilyName(ref length, buffer);
        if (result != 0)
        {
            return null;
        }

        var nameLength = Math.Max(0, length - 1);
        while (nameLength > 0 && buffer[nameLength - 1] == '\0')
        {
            nameLength--;
        }

        var name = new string(buffer, 0, nameLength);
        return string.IsNullOrWhiteSpace(name) ? null : name;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
    private static extern int GetCurrentPackageFamilyName(ref int packageFamilyNameLength, [Out] char[]? packageFamilyName);
}
