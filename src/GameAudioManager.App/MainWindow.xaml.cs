using System.ComponentModel;
using System.Windows;
using GameAudioManager.Core.Configuration;

namespace GameAudioManager.App;

public partial class MainWindow : Window
{
    /// <summary>Theme options shown in the combo: setting value, then the label key.</summary>
    private static readonly (string Value, string LabelKey)[] ThemeOptions =
    {
        (ThemeNames.System, "ThemeSystem"),
        (ThemeNames.Light, "ThemeLight"),
        (ThemeNames.Dark, "ThemeDark"),
    };

    private readonly MainViewModel _viewModel;
    private bool _suppressLanguageChange;
    private bool _suppressThemeChange;

    public MainWindow(MainViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();

        DataContext = _viewModel;
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;

        BuildThemeCombo();
        BuildLanguageCombo();

        Loaded += (_, _) =>
        {
            _viewModel.Initialize();
            RefreshLocalizedChrome();
            UpdateControls();
        };

        // Keyboard shortcuts for the actions used most often.
        PreviewKeyDown += OnPreviewKeyDown;
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        // Closing the window must not stop automation: the app lives in the tray.
        if (!App.IsExiting)
        {
            e.Cancel = true;
            Hide();
            return;
        }

        _viewModel.Dispose();
        base.OnClosing(e);
    }

    private void BuildThemeCombo()
    {
        UpdateThemeComboItems();

        var current = ThemeNames.Normalize(_viewModel.Settings.Theme);
        ThemeCombo.SelectedIndex = Array.FindIndex(ThemeOptions, o =>
            string.Equals(o.Value, current, StringComparison.OrdinalIgnoreCase));
        if (ThemeCombo.SelectedIndex < 0)
        {
            ThemeCombo.SelectedIndex = 0;
        }
    }

    private void UpdateThemeComboItems()
    {
        // Rebuilding the items raises SelectionChanged; without this guard that
        // re-enters here and recurses until the stack overflows.
        var wasSuppressed = _suppressThemeChange;
        _suppressThemeChange = true;
        try
        {
            var selected = ThemeCombo.SelectedIndex;
            ThemeCombo.Items.Clear();
            foreach (var option in ThemeOptions)
            {
                ThemeCombo.Items.Add(Localization.Instance[option.LabelKey]);
            }

            ThemeCombo.SelectedIndex = selected >= 0 && selected < ThemeCombo.Items.Count ? selected : 0;
        }
        finally
        {
            _suppressThemeChange = wasSuppressed;
        }
    }

    private void BuildLanguageCombo()
    {
        _suppressLanguageChange = true;
        LanguageCombo.Items.Clear();
        LanguageCombo.Items.Add("日本語");
        LanguageCombo.Items.Add("English");
        LanguageCombo.SelectedIndex = Localization.Instance.Language == Localization.Japanese ? 0 : 1;
        _suppressLanguageChange = false;
    }

    /// <summary>Re-reads strings that are not bound through the indexer.</summary>
    private void RefreshLocalizedChrome()
    {
        UpdateThemeComboItems();
        WatcherButton.Content = Localization.Instance[
            _viewModel.WatcherRunning ? "WatcherStop" : "WatcherStart"];
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        UpdateControls();
    }

    private void UpdateControls()
    {
        var row = _viewModel.SelectedApp;
        var running = row is { Status.IsRunning: true };

        ApplyButton.IsEnabled = running && _viewModel.SelectedDevice is not null && !_viewModel.IsBusy;
        ResetButton.IsEnabled = running && !_viewModel.IsBusy;
        MuteButton.IsEnabled = running && !_viewModel.IsBusy;
        WatcherButton.Content = Localization.Instance[
            _viewModel.WatcherRunning ? "WatcherStop" : "WatcherStart"];

        MuteButton.Content = Localization.Instance[row?.Status.Mute switch
        {
            { HasSession: false } => "MuteToggle",
            { IsMuted: true } => "MuteOffButton",
            { HasSession: true } => "MuteOnButton",
            _ => "MuteToggle",
        }];
    }

    private async void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var ctrl = (System.Windows.Input.Keyboard.Modifiers & System.Windows.Input.ModifierKeys.Control) != 0;
        switch (e.Key)
        {
            case System.Windows.Input.Key.F5:
                await _viewModel.RefreshAsync();
                e.Handled = true;
                break;
            case System.Windows.Input.Key.F when ctrl:
                FilterBox.Focus();
                FilterBox.SelectAll();
                e.Handled = true;
                break;
            case System.Windows.Input.Key.M when ctrl:
                await _viewModel.ToggleMuteAsync();
                e.Handled = true;
                break;
            case System.Windows.Input.Key.OemComma when ctrl:
                _viewModel.ToggleWatcher();
                e.Handled = true;
                break;
            case System.Windows.Input.Key.Escape when FilterBox.IsKeyboardFocusWithin:
                _viewModel.FilterText = string.Empty;
                AppList.Focus();
                e.Handled = true;
                break;
        }
    }

    private async void OnRefresh(object sender, RoutedEventArgs e) => await _viewModel.RefreshAsync();

    private void OnToggleWatcher(object sender, RoutedEventArgs e) => _viewModel.ToggleWatcher();

    private async void OnApply(object sender, RoutedEventArgs e) => await _viewModel.ApplySelectedDeviceAsync();

    private async void OnReset(object sender, RoutedEventArgs e) => await _viewModel.ResetSelectedAsync();

    private async void OnToggleMute(object sender, RoutedEventArgs e) => await _viewModel.ToggleMuteAsync();

    private void OnThemeChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (_suppressThemeChange
            || ThemeCombo.SelectedIndex < 0
            || ThemeCombo.SelectedIndex >= ThemeOptions.Length)
        {
            return;
        }

        _viewModel.SetTheme(ThemeOptions[ThemeCombo.SelectedIndex].Value);
        UpdateControls();
    }

    private void OnLanguageChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (_suppressLanguageChange || LanguageCombo.SelectedIndex < 0)
        {
            return;
        }

        _viewModel.SetLanguage(LanguageCombo.SelectedIndex == 0
            ? Localization.Japanese
            : Localization.English);

        RefreshLocalizedChrome();
        UpdateControls();
    }

    private void OnAutoApplyToggled(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.CheckBox { Tag: AppRow row } box)
        {
            _viewModel.SetAutoApply(row, box.IsChecked == true);
        }
    }

    private void OnAddPriority(object sender, RoutedEventArgs e) => _viewModel.AddPriorityDevice();

    private void OnRemovePriority(object sender, RoutedEventArgs e) =>
        _viewModel.RemovePriorityDeviceAt(PriorityList.SelectedIndex);

    private void OnMovePriorityUp(object sender, RoutedEventArgs e) =>
        _viewModel.MovePriorityDeviceAt(PriorityList.SelectedIndex, -1);

    private void OnMovePriorityDown(object sender, RoutedEventArgs e) =>
        _viewModel.MovePriorityDeviceAt(PriorityList.SelectedIndex, 1);

    private async void OnImportLegacy(object sender, RoutedEventArgs e)
    {
        var loc = Localization.Instance;
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = loc["ImportDialogTitle"],
            Filter = loc["ImportDialogFilter"],
            CheckFileExists = true,
        };

        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        var result = await _viewModel.ImportLegacyAsync(dialog.FileName);
        System.Windows.MessageBox.Show(
            this,
            loc.Format("ImportResultBody", result.Added, result.Merged, result.Unresolved.Count),
            loc["ImportResultTitle"],
            System.Windows.MessageBoxButton.OK,
            System.Windows.MessageBoxImage.Information);
    }
}

