using System.Runtime.InteropServices;
using GameAudioManager.Core.Audio.Interop;

namespace GameAudioManager.Core.Audio;

/// <summary>Enumerates render endpoints through the Windows Core Audio API.</summary>
public sealed class CoreAudioDeviceService : IAudioDeviceService
{
    private const int StgmRead = 0;

    public IReadOnlyList<AudioDevice> GetRenderDevices()
    {
        var result = new List<AudioDevice>();
        var enumerator = CreateEnumerator();
        try
        {
            var defaultId = TryGetDefaultRenderId(enumerator);

            if (enumerator.EnumAudioEndpoints(AudioInterop.EDataFlow.Render, AudioInterop.DeviceStateMask.All, out var collection) != 0)
            {
                throw new InvalidOperationException("Failed to enumerate audio endpoints.");
            }

            try
            {
                if (collection.GetCount(out var count) != 0)
                {
                    throw new InvalidOperationException("Failed to count audio endpoints.");
                }

                for (var i = 0; i < count; i++)
                {
                    if (collection.Item(i, out var device) != 0 || device is null)
                    {
                        continue;
                    }

                    try
                    {
                        var id = ReadId(device);
                        if (string.IsNullOrEmpty(id))
                        {
                            continue;
                        }

                        var state = ReadState(device);
                        var name = ReadName(device) ?? id;
                        result.Add(new AudioDevice(id, name, state, string.Equals(id, defaultId, StringComparison.OrdinalIgnoreCase)));
                    }
                    finally
                    {
                        _ = Marshal.ReleaseComObject(device);
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
        }

        // Active devices first, then by name, so the UI order is stable and useful.
        return result
            .OrderByDescending(d => d.IsActive)
            .ThenBy(d => d.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    public AudioDevice? FindById(string deviceId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceId);
        return GetRenderDevices().FirstOrDefault(d => string.Equals(d.Id, deviceId, StringComparison.OrdinalIgnoreCase));
    }

    internal static AudioInterop.IMMDeviceEnumerator CreateEnumerator()
    {
        return (AudioInterop.IMMDeviceEnumerator)new AudioInterop.MMDeviceEnumeratorComObject();
    }

    internal static string? ReadId(AudioInterop.IMMDevice device)
    {
        return device.GetId(out var id) == 0 ? id : null;
    }

    internal static AudioDeviceState ReadState(AudioInterop.IMMDevice device)
    {
        if (device.GetState(out var mask) != 0)
        {
            return AudioDeviceState.NotPresent;
        }

        return mask switch
        {
            AudioInterop.DeviceStateMask.Active => AudioDeviceState.Active,
            AudioInterop.DeviceStateMask.Disabled => AudioDeviceState.Disabled,
            AudioInterop.DeviceStateMask.Unplugged => AudioDeviceState.Unplugged,
            _ => AudioDeviceState.NotPresent,
        };
    }

    internal static string? ReadName(AudioInterop.IMMDevice device)
    {
        if (device.OpenPropertyStore(StgmRead, out var store) != 0 || store is null)
        {
            return null;
        }

        try
        {
            // Prefer the user-visible name; fall back to the hardware description,
            // which is what SoundVolumeView reports and what existing configs use.
            return AudioInterop.ReadStringProperty(store, AudioInterop.DeviceFriendlyNameKey)
                ?? AudioInterop.ReadStringProperty(store, AudioInterop.DeviceDeviceDescKey);
        }
        finally
        {
            _ = Marshal.ReleaseComObject(store);
        }
    }

    private static string? TryGetDefaultRenderId(AudioInterop.IMMDeviceEnumerator enumerator)
    {
        if (enumerator.GetDefaultAudioEndpoint(AudioInterop.EDataFlow.Render, AudioInterop.ERole.Multimedia, out var device) != 0 || device is null)
        {
            return null;
        }

        try
        {
            return ReadId(device);
        }
        finally
        {
            _ = Marshal.ReleaseComObject(device);
        }
    }
}
