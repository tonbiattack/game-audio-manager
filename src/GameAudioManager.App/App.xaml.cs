using System.Windows;
using System.Windows.Forms;
using NotifyIcon = System.Windows.Forms.NotifyIcon;
using ContextMenuStrip = System.Windows.Forms.ContextMenuStrip;
using ToolStripSeparator = System.Windows.Forms.ToolStripSeparator;
using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;
using GameAudioManager.Core.Startup;

namespace GameAudioManager.App;

/// <summary>
/// Composition root and lifetime owner.
/// </summary>
/// <remarks>
/// The app is tray-resident: closing the window only hides it, and automation keeps
/// running. Quitting is an explicit tray-menu action, which is what makes "close the
/// window" and "stop managing my audio" two different decisions.
/// </remarks>
public partial class App : System.Windows.Application
{
    private SingleInstanceGuard? _singleInstance;
    private NotifyIcon? _trayIcon;
    private MainWindow? _window;
    private DeviceChangeWatcher? _deviceWatcher;

    /// <summary>True once the user chose to quit, so the window may really close.</summary>
    public static bool IsExiting { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _singleInstance = SingleInstanceGuard.Acquire();
        if (!_singleInstance.IsFirstInstance)
        {
            // A second copy would fight over the same rules; just exit.
            Shutdown();
            return;
        }

        var devices = new CoreAudioDeviceService();
        var sessions = new CoreAudioSessionService();

        // Per-app routing goes through Windows.Media.Internal.AudioPolicyConfig, the
        // same path EarTrumpet uses. No external helper executable is needed.
        var routing = new AudioPolicyConfigRoutingService(devices);
        var store = new SettingsStore(SettingsStore.GetDefaultPath());

        // Apply the saved theme before the first frame so there is no flash of the
        // wrong palette.
        ThemeManager.Apply(store.Load().Theme);

        var viewModel = new MainViewModel(devices, sessions, routing, store);
        _window = new MainWindow(viewModel);
        MainWindow = _window;

        CreateTrayIcon(viewModel);
        SubscribeSystemEvents(viewModel);

        if (!e.Args.Contains("--minimized", StringComparer.OrdinalIgnoreCase))
        {
            _window.Show();
        }
    }

    /// <summary>
    /// Re-runs the watcher when the machine's audio situation changes.
    /// </summary>
    /// <remarks>
    /// Device arrivals/removals come through <see cref="DeviceChangeWatcher"/> because
    /// .NET does not expose <c>SystemEvents.DeviceChange</c>. Resume-from-sleep is
    /// handled separately: the audio service can rebuild endpoints while the app is
    /// suspended, so the rules must be re-applied even though no device message arrives.
    /// </remarks>
    private void SubscribeSystemEvents(MainViewModel viewModel)
    {
        _deviceWatcher = new DeviceChangeWatcher(viewModel.OnExternalChange);

        Microsoft.Win32.SystemEvents.PowerModeChanged += (_, e) =>
        {
            if (e.Mode == Microsoft.Win32.PowerModes.Resume)
            {
                viewModel.OnExternalChange();
            }
        };
    }

    /// <summary>Brings the window back from the tray.</summary>
    public static void ShowMainWindow()
    {
        if (Current is App app && app._window is { } window)
        {
            window.Show();
            if (window.WindowState == WindowState.Minimized)
            {
                window.WindowState = WindowState.Normal;
            }

            window.Activate();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayIcon?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }

    private void CreateTrayIcon(MainViewModel viewModel)
    {
        _trayIcon = new NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            Text = "Game Audio Manager",
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add("開く", null, (_, _) => ShowMainWindow());
        menu.Items.Add("ミュートを解除して終了", null, (_, _) =>
        {
            viewModel.SaveSettings();
            Quit();
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("終了", null, (_, _) => Quit());

        _trayIcon.ContextMenuStrip = menu;
        _trayIcon.DoubleClick += (_, _) => ShowMainWindow();
    }

    private void Quit()
    {
        IsExiting = true;
        _trayIcon?.Dispose();
        _trayIcon = null;
        Shutdown();
    }
}


