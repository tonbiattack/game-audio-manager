using System.ComponentModel;
using System.Windows;

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
            _viewModel.Start();
            UpdateControls();
        };
    }

    protected override void OnClosed(EventArgs e)
    {
        _viewModel.Dispose();
        base.OnClosed(e);
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        UpdateControls();
    }

    private void UpdateControls()
    {
        var row = _viewModel.SelectedApp;
        var hasRunningSelection = row is { IsRunning: true };
        BusyText.Text = _viewModel.IsBusy ? "処理中…" : string.Empty;

        ApplyButton.IsEnabled = hasRunningSelection && _viewModel.SelectedDevice is not null && !_viewModel.IsBusy;
        ResetButton.IsEnabled = hasRunningSelection && !_viewModel.IsBusy;
        MuteButton.IsEnabled = hasRunningSelection && !_viewModel.IsBusy;
        MuteButton.Content = row?.MuteState switch
        {
            { HasSession: false } => "ミュート切替",
            { IsMuted: true } => "ミュートを解除",
            { HasSession: true } => "ミュートする",
            _ => "ミュート切替",
        };
    }

    private async void OnRefresh(object sender, RoutedEventArgs e)
    {
        await _viewModel.RefreshAsync();
    }

    private async void OnApply(object sender, RoutedEventArgs e)
    {
        await _viewModel.ApplySelectedDeviceAsync();
    }

    private async void OnReset(object sender, RoutedEventArgs e)
    {
        await _viewModel.ResetSelectedAsync();
    }

    private async void OnToggleMute(object sender, RoutedEventArgs e)
    {
        await _viewModel.ToggleMuteAsync();
    }
}
