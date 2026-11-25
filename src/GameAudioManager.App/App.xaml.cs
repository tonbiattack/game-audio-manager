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
    private Microsoft.Win32.PowerModeChangedEventHandler? _powerModeHandler;
    private Microsoft.Win32.UserPreferenceChangedEventHandler? _userPreferenceHandler;
    private string _lastTheme = GameAudioManager.Core.Configuration.ThemeNames.System;

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

        // Apply the saved language and theme before the first frame so there is no
        // flash of the wrong palette or the wrong language.
        var initialSettings = store.Load();
        Localization.Instance.Language = string.IsNullOrWhiteSpace(initialSettings.Language)
            ? Localization.DetectSystemLanguage()
            : Localization.Instance.Resolve(initialSettings.Language);
        ThemeManager.Apply(initialSettings.Theme);

        _lastTheme = initialSettings.Theme;
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

        // Keep the delegate so it can be removed on exit; a leaked subscription keeps
        // the view model alive and fires into a disposed watcher.
        _powerModeHandler = (_, e) =>
        {
            if (e.Mode == Microsoft.Win32.PowerModes.Resume)
            {
                viewModel.OnExternalChange();
            }
        };
        Microsoft.Win32.SystemEvents.PowerModeChanged += _powerModeHandler;

        // Re-apply the palette when Windows switches between light and dark, but only
        // when the user asked to follow the system theme.
        _userPreferenceHandler = (_, e) =>
        {
            if (e.Category == Microsoft.Win32.UserPreferenceCategory.General
                && string.Equals(
                    GameAudioManager.Core.Configuration.ThemeNames.Normalize(_lastTheme),
                    GameAudioManager.Core.Configuration.ThemeNames.System,
                    StringComparison.OrdinalIgnoreCase))
            {
                ThemeManager.Apply(_lastTheme);
            }
        };
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += _userPreferenceHandler;
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
            Icon = LoadTrayIcon(),
            Visible = true,
            Text = Localization.Instance["TrayTooltip"],
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

    /// <summary>Loads the app icon from the executable for the tray.</summary>
    private static System.Drawing.Icon LoadTrayIcon()
    {
        try
        {
            var exe = Environment.ProcessPath;
            if (!string.IsNullOrEmpty(exe))
            {
                var extracted = System.Drawing.Icon.ExtractAssociatedIcon(exe);
                if (extracted is not null)
                {
                    return extracted;
                }
            }
        }
        catch (ArgumentException)
        {
            // Fall back to the system icon.
        }

        return System.Drawing.SystemIcons.Application;
    }

    private void Quit()
    {
        IsExiting = true;
        _trayIcon?.Dispose();
        _trayIcon = null;
        Shutdown();
    }
}






