using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;

namespace GameAudioManager.App;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;

    public MainWindow(MainViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();

        DataContext = _viewModel;
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;

        Loaded += (_, _) =>
        {
            _viewModel.Initialize();
            UpdateControls();
        };
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
        WatcherButton.Content = _viewModel.WatcherRunning ? "自動適用を停止" : "自動適用を開始";

        MuteButton.Content = row?.Status.Mute switch
        {
            { HasSession: false } => "ミュート切替",
            { IsMuted: true } => "ミュートを解除",
            { HasSession: true } => "ミュートする",
            _ => "ミュート切替",
        };
    }


    private async void OnRefresh(object sender, RoutedEventArgs e) => await _viewModel.RefreshAsync();

    private void OnToggleWatcher(object sender, RoutedEventArgs e) => _viewModel.ToggleWatcher();

    private async void OnApply(object sender, RoutedEventArgs e) => await _viewModel.ApplySelectedDeviceAsync();

    private async void OnReset(object sender, RoutedEventArgs e) => await _viewModel.ResetSelectedAsync();

    private async void OnToggleMute(object sender, RoutedEventArgs e) => await _viewModel.ToggleMuteAsync();

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
}


