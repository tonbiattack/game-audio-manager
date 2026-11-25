using System.Collections.Concurrent;
using System.Drawing;
using System.IO;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace GameAudioManager.App;

/// <summary>
/// Extracts and caches each application's icon for the list.
/// </summary>
/// <remarks>
/// Icons come from the executable on disk, so they are stable across refreshes. Lookups
/// are cached by process name and failures are remembered too: a process whose
/// executable is not readable (elevated app, protected path) must not be retried on
/// every refresh, and the row simply shows no icon.
/// </remarks>
public static class AppIconCache
{
    private static readonly ConcurrentDictionary<string, BitmapSource?> Cache =
        new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Returns the icon for a process, or null when it cannot be read.</summary>
    public static BitmapSource? GetIcon(string processName)
    {
        if (string.IsNullOrWhiteSpace(processName))
        {
            return null;
        }

        return Cache.GetOrAdd(processName, Load);
    }

    private static BitmapSource? Load(string processName)
    {
        try
        {
            using var process = System.Diagnostics.Process.GetProcessesByName(processName)
                .FirstOrDefault();
            if (process is null)
            {
                // Not running now: do not cache a null, so a later start can still load it.
                return null;
            }

            var path = process.MainModule?.FileName;
            if (string.IsNullOrEmpty(path) || !File.Exists(path))
            {
                return null;
            }

            using var icon = Icon.ExtractAssociatedIcon(path);
            if (icon is null)
            {
                return null;
            }

            var source = Imaging.CreateBitmapSourceFromHIcon(
                icon.Handle,
                Int32Rect.Empty,
                BitmapSizeOptions.FromWidthAndHeight(16, 16));

            source.Freeze();
            return source;
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
        {
            // Unreadable executable or a protected process: show the row without an icon.
            return null;
        }
    }

    /// <summary>Drops cached entries for processes that are no longer running.</summary>
    public static void Prune()
    {
        foreach (var name in Cache.Keys)
        {
            if (System.Diagnostics.Process.GetProcessesByName(name).Length == 0)
            {
                Cache.TryRemove(name, out _);
            }
        }
    }
}
