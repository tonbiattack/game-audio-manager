using System.Windows;
using System.IO;
using GameAudioManager.App;
using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;

namespace GameAudioManager.App;

/// <summary>
/// Composition root. Kept explicit (no container) because the object graph is small
/// and this makes the dependencies of each screen obvious.
/// </summary>
public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var devices = new CoreAudioDeviceService();
        var sessions = new CoreAudioSessionService();
        var svclPath = FindSvcl();
        var routing = new AppRoutingService(svclPath, devices);
        var store = new SettingsStore(SettingsStore.GetDefaultPath());

        var viewModel = new MainViewModel(devices, sessions, routing, store);
        var window = new MainWindow(viewModel);
        MainWindow = window;
        window.Show();
    }

    /// <summary>
    /// Locates the bundled SoundVolumeCommandLine.
    /// </summary>
    /// <remarks>
    /// The helper is still required for writing per-app routing (see
    /// <see cref="AppRoutingService"/>). Shipping it is what blocks the Store
    /// packaging task, so this lookup is intentionally explicit about failing.
    /// </remarks>
    private static string FindSvcl()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "vendor", "svcl", "svcl.exe"),
            Path.Combine(AppContext.BaseDirectory, "svcl.exe"),
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "vendor", "svcl", "svcl.exe"),
        };

        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(full))
            {
                return full;
            }
        }

        return Path.Combine(AppContext.BaseDirectory, "vendor", "svcl", "svcl.exe");
    }
}
