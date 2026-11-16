Set-StrictMode -Version Latest

# Core Audio interop for per-application mute control.
#
# The previous implementation only looked at the default render endpoint and only
# at the first PID returned for a process name. Games that route audio to a
# non-default device, or that run several processes under one name, were missed.
# This version enumerates every active render endpoint and every session on it.
$script:GameAudioMuteInteropSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public sealed class GameAudioSessionInfo
{
    public uint ProcessId { get; set; }
    public string ProcessName { get; set; }
    public string DeviceId { get; set; }
    public string DeviceName { get; set; }
    public bool Muted { get; set; }
    public bool IsSystemSounds { get; set; }
}

public static class GameAudioSessions
{
    private const int CLSCTX_ALL = 23;
    private const int STGM_READ = 0;
    private const short VT_LPWSTR = 31;

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator { }

    private enum EDataFlow { eRender = 0, eCapture = 1, eAll = 2 }

    [Flags]
    private enum DeviceState { ACTIVE = 0x1, DISABLED = 0x2, NOTPRESENT = 0x4, UNPLUGGED = 0x8, ALL = 0xF }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPERTYKEY
    {
        public Guid fmtid;
        public int pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct PROPVARIANT
    {
        [FieldOffset(0)] public short vt;
        [FieldOffset(8)] public IntPtr pointerValue;
    }

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PROPVARIANT pvar);

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(EDataFlow dataFlow, DeviceState stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, int role, out IMMDevice device);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport]
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceCollection
    {
        int GetCount(out int count);
        int Item(int index, out IMMDevice device);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        int OpenPropertyStore(int access, out IPropertyStore properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out DeviceState state);
    }

    [ComImport]
    [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        int GetCount(out int count);
        int GetAt(int index, out PROPERTYKEY key);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
        int Commit();
    }

    [ComImport]
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionManager2
    {
        int GetAudioSessionControl(IntPtr audioSessionGuid, int streamFlags, out IntPtr sessionControl);
        int GetSimpleAudioVolume(IntPtr audioSessionGuid, int streamFlags, out IntPtr audioVolume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
        int RegisterSessionNotification(IntPtr sessionNotification);
        int UnregisterSessionNotification(IntPtr sessionNotification);
        int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr duckNotification);
        int UnregisterDuckNotification(IntPtr duckNotification);
    }

    [ComImport]
    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionEnumerator
    {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl session);
    }

    [ComImport]
    [Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl
    {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid eventContext);
        int GetGroupingParam(out Guid groupingParam);
        int SetGroupingParam(ref Guid groupingParam, ref Guid eventContext);
        int RegisterAudioSessionNotification(IntPtr newNotifications);
        int UnregisterAudioSessionNotification(IntPtr newNotifications);
    }

    // IAudioSessionControl2 inherits every IAudioSessionControl method, so the
    // inherited slots must be declared first. Declaring only the extra methods
    // shifts the vtable and GetProcessId reads the wrong slot.
    [ComImport]
    [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl2
    {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid eventContext);
        int GetGroupingParam(out Guid groupingParam);
        int SetGroupingParam(ref Guid groupingParam, ref Guid eventContext);
        int RegisterAudioSessionNotification(IntPtr newNotifications);
        int UnregisterAudioSessionNotification(IntPtr newNotifications);
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string retVal);
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string retVal);
        int GetProcessId(out uint retVal);
        int IsSystemSoundsSession();
        int SetDuckingPreference(bool optOut);
    }

    [ComImport]
    [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISimpleAudioVolume
    {
        int SetMasterVolume(float level, ref Guid eventContext);
        int GetMasterVolume(out float level);
        int SetMute(bool mute, ref Guid eventContext);
        int GetMute(out bool mute);
    }

    // Endpoints that could not be inspected. Callers surface these as warnings
    // instead of failing the whole operation.
    public static string[] LastErrors = new string[0];

    public static GameAudioSessionInfo[] GetSessions(string processName)
    {
        int changed;
        return Walk(processName, null, out changed);
    }

    public static int SetMute(string processName, bool mute)
    {
        int changed;
        Walk(processName, mute, out changed);
        return changed;
    }

    private static GameAudioSessionInfo[] Walk(string processName, bool? setMute, out int changed)
    {
        changed = 0;
        var results = new List<GameAudioSessionInfo>();
        var errors = new List<string>();
        IMMDeviceEnumerator enumerator = null;
        try
        {
            enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
            IMMDeviceCollection devices;
            int hr = enumerator.EnumAudioEndpoints(EDataFlow.eRender, DeviceState.ACTIVE, out devices);
            if (hr != 0) throw new COMException("EnumAudioEndpoints failed.", hr);
            try
            {
                int deviceCount;
                hr = devices.GetCount(out deviceCount);
                if (hr != 0) throw new COMException("IMMDeviceCollection.GetCount failed.", hr);
                for (int i = 0; i < deviceCount; i++)
                {
                    IMMDevice device = null;
                    try
                    {
                        hr = devices.Item(i, out device);
                        if (hr != 0) { errors.Add("IMMDeviceCollection.Item failed for index " + i + "."); continue; }
                        WalkDevice(device, processName, setMute, results, ref changed);
                    }
                    catch (Exception ex)
                    {
                        errors.Add(ex.Message);
                    }
                    finally
                    {
                        if (device != null) Marshal.ReleaseComObject(device);
                    }
                }
            }
            finally
            {
                Marshal.ReleaseComObject(devices);
            }
        }
        finally
        {
            if (enumerator != null) Marshal.ReleaseComObject(enumerator);
            LastErrors = errors.ToArray();
        }
        return results.ToArray();
    }

    private static void WalkDevice(IMMDevice device, string processName, bool? setMute, List<GameAudioSessionInfo> results, ref int changed)
    {
        string deviceId = null;
        try { device.GetId(out deviceId); }
        catch { }
        string deviceName = GetDeviceFriendlyName(device);

        Guid iid = typeof(IAudioSessionManager2).GUID;
        object managerObject;
        int hr = device.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out managerObject);
        if (hr != 0) throw new COMException("Activating IAudioSessionManager2 failed.", hr);
        var manager = (IAudioSessionManager2)managerObject;
        try
        {
            IAudioSessionEnumerator sessionEnum;
            hr = manager.GetSessionEnumerator(out sessionEnum);
            if (hr != 0) throw new COMException("GetSessionEnumerator failed.", hr);
            try
            {
                int sessionCount;
                hr = sessionEnum.GetCount(out sessionCount);
                if (hr != 0) throw new COMException("IAudioSessionEnumerator.GetCount failed.", hr);
                for (int i = 0; i < sessionCount; i++)
                {
                    IAudioSessionControl control;
                    hr = sessionEnum.GetSession(i, out control);
                    if (hr != 0 || control == null) continue;
                    try
                    {
                        var control2 = (IAudioSessionControl2)control;
                        uint pid;
                        hr = control2.GetProcessId(out pid);
                        if (hr != 0) continue;

                        string sessionProcessName = null;
                        try { sessionProcessName = Process.GetProcessById((int)pid).ProcessName; }
                        catch { }
                        if (!string.Equals(sessionProcessName, processName, StringComparison.OrdinalIgnoreCase)) continue;

                        var volume = (ISimpleAudioVolume)control;
                        bool muted;
                        hr = volume.GetMute(out muted);
                        if (hr != 0) continue;

                        if (setMute.HasValue)
                        {
                            Guid context = Guid.Empty;
                            hr = volume.SetMute(setMute.Value, ref context);
                            if (hr != 0) continue;
                            muted = setMute.Value;
                            changed++;
                        }

                        results.Add(new GameAudioSessionInfo
                        {
                            ProcessId = pid,
                            ProcessName = sessionProcessName,
                            DeviceId = deviceId,
                            DeviceName = deviceName,
                            Muted = muted,
                            IsSystemSounds = control2.IsSystemSoundsSession() == 0
                        });
                    }
                    finally
                    {
                        Marshal.ReleaseComObject(control);
                    }
                }
            }
            finally
            {
                Marshal.ReleaseComObject(sessionEnum);
            }
        }
        finally
        {
            Marshal.ReleaseComObject(manager);
        }
    }

    private static string GetDeviceFriendlyName(IMMDevice device)
    {
        IPropertyStore store = null;
        try
        {
            if (device.OpenPropertyStore(STGM_READ, out store) != 0 || store == null) return null;
            var key = new PROPERTYKEY
            {
                fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),
                pid = 14
            };
            PROPVARIANT value;
            if (store.GetValue(ref key, out value) != 0) return null;
            try
            {
                if (value.vt == VT_LPWSTR && value.pointerValue != IntPtr.Zero)
                {
                    return Marshal.PtrToStringUni(value.pointerValue);
                }
                return null;
            }
            finally
            {
                PropVariantClear(ref value);
            }
        }
        catch
        {
            return null;
        }
        finally
        {
            if (store != null) Marshal.ReleaseComObject(store);
        }
    }
}
'@

function Initialize-GameAudioMuteInterop {
    if (-not ('GameAudioSessions' -as [type])) {
        Add-Type -TypeDefinition $script:GameAudioMuteInteropSource
    }
}

function Get-GameAudioSessionInfo {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    Initialize-GameAudioMuteInterop
    $name = ConvertTo-GameProcessName -ProcessName $ProcessName
    return @([GameAudioSessions]::GetSessions($name))
}

function Set-GameAudioSessionMute {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName,
        [Parameter(Mandatory = $true)][bool]$Mute
    )

    Initialize-GameAudioMuteInterop
    $name = ConvertTo-GameProcessName -ProcessName $ProcessName
    return [GameAudioSessions]::SetMute($name, $Mute)
}

function Get-GameAudioMuteInteropErrors {
    Initialize-GameAudioMuteInterop
    return @([GameAudioSessions]::LastErrors)
}

# Mixed-state rule: a toggle only unmutes when *every* matching session is
# already muted. If any session is unmuted (including a mixed set), the toggle
# mutes them all, so the target is always a single consistent state.
function Get-GameAudioMuteTargetState {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Sessions
    )

    $all = @($Sessions)
    if ($all.Count -eq 0) {
        throw 'No audio sessions were found to toggle.'
    }
    $unmuted = @($all | Where-Object { -not $_.Muted })
    return ($unmuted.Count -gt 0)
}

function Format-GameAudioSessionSummary {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Sessions
    )

    return @($Sessions | ForEach-Object {
        $device = if ([string]::IsNullOrWhiteSpace($_.DeviceName)) { $_.DeviceId } else { $_.DeviceName }
        [PSCustomObject]@{
            ProcessId = $_.ProcessId
            Device = $device
            Muted = [bool]$_.Muted
        }
    })
}
