$ProcessName = "ShirenTheWanderer6"

$code = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

public static class AppVolume
{
    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumerator { }

    private enum EDataFlow
    {
        eRender,
        eCapture,
        eAll
    }

    private enum ERole
    {
        eConsole,
        eMultimedia,
        eCommunications
    }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        int NotImpl1();
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice device);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    }

    [ComImport]
    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionManager2
    {
        int NotImpl1();
        int NotImpl2();
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
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
    }

    [ComImport]
    [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl2
    {
        int NotImpl1();
        int NotImpl2();
        int GetProcessId(out uint processId);
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

    public static bool ToggleMute(int pid)
    {
        var deviceEnumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDevice device;
        deviceEnumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device);

        Guid iid = typeof(IAudioSessionManager2).GUID;
        object managerObject;
        device.Activate(ref iid, 23, IntPtr.Zero, out managerObject);

        var manager = (IAudioSessionManager2)managerObject;
        IAudioSessionEnumerator sessionEnumerator;
        manager.GetSessionEnumerator(out sessionEnumerator);

        int count;
        sessionEnumerator.GetCount(out count);

        for (int i = 0; i < count; i++)
        {
            IAudioSessionControl session;
            sessionEnumerator.GetSession(i, out session);

            var session2 = (IAudioSessionControl2)session;
            uint sessionPid;
            session2.GetProcessId(out sessionPid);

            if (sessionPid != pid)
            {
                continue;
            }

            var volume = (ISimpleAudioVolume)session;
            bool muted;
            volume.GetMute(out muted);

            Guid context = Guid.Empty;
            volume.SetMute(!muted, ref context);
            return !muted;
        }

        throw new InvalidOperationException("Audio session not found for process ID " + pid + ".");
    }
}
'@

if (-not ("AppVolume" -as [type])) {
    Add-Type -TypeDefinition $code
}

if ($ProcessName) {
    $process = Get-Process -Name $ProcessName -ErrorAction Stop | Select-Object -First 1
}
else {
    $process = Get-Process | Where-Object {
        $_.MainWindowTitle -match "Shiren|シレン"
    } | Select-Object -First 1
}

if (-not $process) {
    throw "Shiren process was not found. Start the game first, or set `$ProcessName in the script."
}

$muted = [AppVolume]::ToggleMute($process.Id)

if ($muted) {
    Write-Host "Shiren: MUTE"
}
else {
    Write-Host "Shiren: UNMUTE"
}
