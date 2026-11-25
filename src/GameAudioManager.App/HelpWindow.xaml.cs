using System.Diagnostics;
using System.IO;
using System.Windows;

namespace GameAudioManager.App;

/// <summary>
/// In-app usage guide.
/// </summary>
/// <remarks>
/// The text is embedded in <see cref="Localization"/> rather than read from a file so
/// it always matches the installed build. The "open docs" button opens the repository
/// documentation for the full detail.
/// </remarks>
public partial class HelpWindow : Window
{
    public HelpWindow()
    {
        InitializeComponent();
    }

    private void OnClose(object sender, RoutedEventArgs e) => Close();

    private void OnOpenDocs(object sender, RoutedEventArgs e)
    {
        // The installed layout has no docs folder, so point at the published pages.
        const string url = "https://github.com/tonbiattack/game-audio-manager/blob/main/README.md";

        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
        {
            System.Windows.MessageBox.Show(
                this,
                Localization.Instance.Format("HelpOpenDocsFailed", url),
                Localization.Instance["HelpTitle"],
                System.Windows.MessageBoxButton.OK,
                System.Windows.MessageBoxImage.Information);
        }
    }
}
