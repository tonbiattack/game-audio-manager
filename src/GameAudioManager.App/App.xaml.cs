using System.Windows;
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

        // Per-app routing goes through Windows.Media.Internal.AudioPolicyConfig, the
        // same path EarTrumpet uses. No external helper executable is needed, so the
        // app can ship as a single binary.
        var routing = new AudioPolicyConfigRoutingService(devices);
        var store = new SettingsStore(SettingsStore.GetDefaultPath());

        var viewModel = new MainViewModel(devices, sessions, routing, store);
        var window = new MainWindow(viewModel);
        MainWindow = window;
        window.Show();
    }
}
