using System.Windows.Forms;

namespace GameAudioManager.App;

/// <summary>
/// Signals when the device tree changes (a headset plugged in, a dock connected).
/// </summary>
/// <remarks>
/// <c>Microsoft.Win32.SystemEvents.DeviceChange</c> exists in .NET Framework but was
/// not carried over to .NET, so <c>WM_DEVICECHANGE</c> is observed directly on a
/// message-only window. This is the same message the shell broadcasts, so it fires for
/// audio endpoints as well as anything else.
/// </remarks>
internal sealed class DeviceChangeWatcher : NativeWindow, IDisposable
{
    private const int WmDeviceChange = 0x0219;
    private readonly Action _onChange;
    private bool _disposed;

    public DeviceChangeWatcher(Action onChange)
    {
        _onChange = onChange ?? throw new ArgumentNullException(nameof(onChange));

        CreateHandle(new CreateParams
        {
            Caption = "GameAudioManagerDeviceWatcher",
            Parent = new IntPtr(-3), // HWND_MESSAGE: receive broadcasts, never shown
        });
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmDeviceChange)
        {
            try
            {
                _onChange();
            }
            catch (Exception)
            {
                // A failing handler must not kill the message loop.
            }
        }

        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        DestroyHandle();
    }
}
