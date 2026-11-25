using System.Diagnostics;
using System.Runtime.InteropServices;
using GameAudioManager.Core.Audio.Interop;

namespace GameAudioManager.Core.Audio;

/// <summary>
/// Reads and changes application mute state across every active render endpoint.
/// </summary>
/// <remarks>
/// Sessions are matched by process *name* rather than pid. A game can own its audio
/// session from a child process, so picking the first pid for a name misses it
/// (this was the defect fixed in the PowerShell version, issue #9).
/// </remarks>
public sealed class CoreAudioSessionService : IAudioSessionService
{
    /// <summary>Endpoint failures collected during the last operation, for diagnostics.</summary>
    public IReadOnlyList<string> LastErrors { get; private set; } = Array.Empty<string>();

    public IReadOnlyList<AudioSessionInfo> GetSessions(string processName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(processName);
        return Walk(processName, null);
    }

    public int SetMute(string processName, bool muted)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(processName);
        return Walk(processName, muted).Count(s => s.IsMuted == muted);
    }

    private List<AudioSessionInfo> Walk(string processName, bool? setMute)
    {
        var results = new List<AudioSessionInfo>();
        var errors = new List<string>();
        var target = NormalizeProcessName(processName);

        var enumerator = CoreAudioDeviceService.CreateEnumerator();
        try
        {
            if (enumerator.EnumAudioEndpoints(AudioInterop.EDataFlow.Render, AudioInterop.DeviceStateMask.Active, out var collection) != 0)
            {
                throw new InvalidOperationException("Failed to enumerate audio endpoints.");
            }

            try
            {
                if (collection.GetCount(out var deviceCount) != 0)
                {
                    throw new InvalidOperationException("Failed to count audio endpoints.");
                }

                for (var i = 0; i < deviceCount; i++)
                {
                    AudioInterop.IMMDevice? device = null;
                    try
                    {
                        if (collection.Item(i, out device) != 0 || device is null)
                        {
                            errors.Add($"Could not open render endpoint at index {i}.");
                            continue;
                        }

                        WalkDevice(device, target, setMute, results, errors);
                    }
                    catch (Exception ex) when (ex is COMException or InvalidOperationException)
                    {
                        errors.Add(ex.Message);
                    }
                    finally
                    {
                        if (device is not null)
                        {
                            _ = Marshal.ReleaseComObject(device);
                        }
                    }
                }
            }
            finally
            {
                _ = Marshal.ReleaseComObject(collection);
            }
        }
        finally
        {
            _ = Marshal.ReleaseComObject(enumerator);
            LastErrors = errors;
        }

        return results;
    }

    private static void WalkDevice(
        AudioInterop.IMMDevice device,
        string targetProcessName,
        bool? setMute,
        List<AudioSessionInfo> results,
        List<string> errors)
    {
        var deviceId = CoreAudioDeviceService.ReadId(device);
        if (string.IsNullOrEmpty(deviceId))
        {
            return;
        }

        var deviceName = CoreAudioDeviceService.ReadName(device);

        var managerId = typeof(AudioInterop.IAudioSessionManager2).GUID;
        if (device.Activate(ref managerId, AudioInterop.ClsCtxAll, IntPtr.Zero, out var managerObject) != 0
            || managerObject is not AudioInterop.IAudioSessionManager2 manager)
        {
            errors.Add($"Could not activate the session manager for device '{deviceName ?? deviceId}'.");
            return;
        }

        try
        {
            if (manager.GetSessionEnumerator(out var sessionEnum) != 0 || sessionEnum is null)
            {
                errors.Add($"Could not enumerate sessions on device '{deviceName ?? deviceId}'.");
                return;
            }

            try
            {
                if (sessionEnum.GetCount(out var count) != 0)
                {
                    return;
                }

                for (var i = 0; i < count; i++)
                {
                    if (sessionEnum.GetSession(i, out var control) != 0 || control is null)
                    {
                        continue;
                    }

                    try
                    {
                        var info = TryReadSession(control, deviceId, deviceName, targetProcessName, setMute);
                        if (info is not null)
                        {
                            results.Add(info);
                        }
                    }
                    finally
                    {
                        _ = Marshal.ReleaseComObject(control);
                    }
                }
            }
            finally
            {
                _ = Marshal.ReleaseComObject(sessionEnum);
            }
        }
        finally
        {
            _ = Marshal.ReleaseComObject(manager);
        }
    }

    private static AudioSessionInfo? TryReadSession(
        AudioInterop.IAudioSessionControl control,
        string deviceId,
        string? deviceName,
        string targetProcessName,
        bool? setMute)
    {
        if (control is not AudioInterop.IAudioSessionControl2 control2)
        {
            return null;
        }

        if (control2.GetProcessId(out var pid) != 0)
        {
            return null;
        }

        var processName = TryGetProcessName(pid);
        if (!string.Equals(processName, targetProcessName, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (control is not AudioInterop.ISimpleAudioVolume volume)
        {
            return null;
        }

        if (volume.GetMute(out var muted) != 0)
        {
            return null;
        }

        if (setMute is { } desired)
        {
            var context = Guid.Empty;
            if (volume.SetMute(desired, ref context) != 0)
            {
                return null;
            }

            muted = desired;
        }

        return new AudioSessionInfo(
            pid,
            processName,
            deviceId,
            deviceName,
            muted,
            control2.IsSystemSoundsSession() == 0);
    }

    private static string NormalizeProcessName(string processName)
    {
        return Path.GetFileNameWithoutExtension(processName.Trim());
    }

    private static string? TryGetProcessName(uint pid)
    {
        try
        {
            using var process = Process.GetProcessById((int)pid);
            return process.ProcessName;
        }
        catch (ArgumentException)
        {
            // The process ended between enumeration and lookup.
            return null;
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }
}
