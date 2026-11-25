using System.Runtime.InteropServices;
using GameAudioManager.Core.Audio;

namespace GameAudioManager.Core.Routing;

/// <summary>
/// Per-application output routing through the undocumented
/// <c>Windows.Media.Internal.AudioPolicyConfig</c> activation factory.
/// </summary>
/// <remarks>
/// <para>
/// This is the same path EarTrumpet uses. It replaces the previous
/// SoundVolumeCommandLine (<c>svcl.exe</c>) dependency so the app can ship as a
/// single executable.
/// </para>
/// <para>
/// The interface is undocumented and Microsoft changed its IID between Windows
/// versions: 21H2 and later use <c>ab3d4648-…</c>, earlier builds use
/// <c>2a59116d-…</c>. Both expose an identical vtable, so the right IID is picked
/// at runtime.
/// </para>
/// <para>
/// The vtable is called directly through function pointers instead of a
/// <c>[ComImport]</c> interface: .NET (Core) throws
/// <c>PlatformNotSupportedException</c> when marshalling an
/// <c>InterfaceIsIInspectable</c> interface. A WinRT interface pointer starts with
/// the six <c>IInspectable</c> slots (QueryInterface, AddRef, Release, GetIids,
/// GetRuntimeClassName, GetTrustLevel), so the first real method sits at slot 6 —
/// hence <see cref="FirstMethodSlot"/>.
/// </para>
/// <para>
/// The 19 methods before <c>SetPersistedDefaultAudioEndpoint</c> must be skipped by
/// offset exactly. Getting this wrong calls <c>add_RingerVibrateStateChanged</c>
/// instead and corrupts state without reporting an error (EarTrumpet discussion
/// #1543).
/// </para>
/// <para>
/// The API is keyed by <em>process id</em>, not executable name. An application that
/// is not running cannot be configured, so the watcher applies the configured device
/// when the process appears.
/// </para>
/// </remarks>
public sealed class AudioPolicyConfigRoutingService : IAppRoutingService, IRoutingCapability
{
    private const string ActivatableClassId = "Windows.Media.Internal.AudioPolicyConfig";

    private const int FirstMethodSlot = 6;      // IInspectable header
    private const int SetMethodIndex = 19;      // members declared before SetPersisted…
    private const int GetMethodIndex = 20;
    private const int QueryInterfaceSlot = 0;
    private const int ReleaseSlot = 2;

    private const int ENoInterface = unchecked((int)0x80004002);
    private const int EFail = unchecked((int)0x80004005);

    private static readonly Guid IidFor21H2 = new("ab3d4648-e242-459f-b02f-541c70306324");
    private static readonly Guid IidForDownlevel = new("2a59116d-6c4f-45e0-a74f-707e3fef9258");

    private readonly IAudioDeviceService _deviceService;

    /// <summary>
    /// Creates the activation factory. Injectable so the "unsupported build" and
    /// "call failed" paths can be tested without a real Windows audio stack.
    /// </summary>
    private readonly Func<(bool Ok, IntPtr Factory, string? Error)> _factoryProvider;

    public AudioPolicyConfigRoutingService(IAudioDeviceService deviceService)
        : this(deviceService, CreateFactoryOrFail)
    {
    }

    internal AudioPolicyConfigRoutingService(
        IAudioDeviceService deviceService,
        Func<(bool Ok, IntPtr Factory, string? Error)> factoryProvider)
    {
        _deviceService = deviceService ?? throw new ArgumentNullException(nameof(deviceService));
        _factoryProvider = factoryProvider ?? throw new ArgumentNullException(nameof(factoryProvider));
    }

    /// <summary>
    /// True when the activation factory can be created on this machine.
    /// </summary>
    /// <remarks>
    /// When false, routing must be reported as unavailable rather than failing
    /// silently. Mute and device enumeration are independent of this API and keep
    /// working, which is why this is a query rather than a constructor failure.
    /// </remarks>
    public static bool IsSupported => TryCreateFactory(out var factory, out _) && factory != IntPtr.Zero && ReleaseAndCheck(factory);

    /// <inheritdoc />
    public bool IsAvailable => IsSupported;

    /// <inheritdoc />
    public string UnavailableMessage => UnsupportedMessage;

    /// <summary>Message shown to the user when routing is unavailable on this build.</summary>
    public const string UnsupportedMessage =
        "この Windows ビルドではアプリ別の出力先変更を利用できません（ミュートは利用できます）。";

    public RoutingResult SetPreferredDevice(string executableName, string deviceId)
    {
        var exe = NormalizeExecutable(executableName);
        if (string.IsNullOrWhiteSpace(deviceId))
        {
            throw new ArgumentException("A device id is required.", nameof(deviceId));
        }

        var target = _deviceService.GetRenderDevices()
            .FirstOrDefault(d => string.Equals(d.Id, deviceId.Trim(), StringComparison.OrdinalIgnoreCase));
        if (target is null)
        {
            return RoutingResult.NotRecorded($"Output device was not found: '{deviceId}'.");
        }

        if (!target.IsActive)
        {
            return RoutingResult.NotRecorded($"Output device is not active: '{target.Name}'.");
        }

        var pids = FindProcessIds(exe);
        if (pids.Count == 0)
        {
            return RoutingResult.NotRecorded(
                $"{exe} is not running. The device will be applied when it starts.");
        }

        return ApplyToProcesses(exe, pids, target.Id, $"Applied '{target.Name}' to {exe}");
    }

    public RoutingResult ResetToDefault(string executableName)
    {
        var exe = NormalizeExecutable(executableName);
        var pids = FindProcessIds(exe);
        if (pids.Count == 0)
        {
            return RoutingResult.NotRecorded($"{exe} is not running. The reset will be applied when it starts.");
        }

        return ApplyToProcesses(exe, pids, deviceId: null, successMessage: $"{exe} now follows the Windows default output device");
    }

    /// <summary>
    /// Reads the device Windows currently has persisted for a running process, or
    /// null when the app is not running or has no persisted choice.
    /// </summary>
    public string? GetPreferredDevice(string executableName)
    {
        var exe = NormalizeExecutable(executableName);
        var pids = FindProcessIds(exe);
        if (pids.Count == 0)
        {
            return null;
        }

        var created = _factoryProvider();
        if (!created.Ok || created.Factory == IntPtr.Zero)
        {
            return null;
        }

        var factory = created.Factory;
        try
        {
            foreach (var pid in pids)
            {
                if (TryGetPersisted(factory, pid, out var deviceId) && !string.IsNullOrWhiteSpace(deviceId))
                {
                    return deviceId;
                }
            }

            // The read API is known to return an empty value on some builds even after a
            // successful write, so "unknown" is reported as null rather than guessed.
            return null;
        }
        finally
        {
            Release(factory);
        }
    }

    private RoutingResult ApplyToProcesses(string exe, IReadOnlyList<uint> pids, string? deviceId, string successMessage)
    {
        var created = _factoryProvider();
        if (!created.Ok || created.Factory == IntPtr.Zero)
        {
            return RoutingResult.NotRecorded(
                UnsupportedMessage + (string.IsNullOrWhiteSpace(created.Error) ? string.Empty : " " + created.Error));
        }

        var factory = created.Factory;
        try
        {
            var applied = 0;
            string? lastError = null;
            foreach (var pid in pids)
            {
                var hr = InvokeSetPersisted(factory, pid, deviceId is null ? null : BuildEndpointPath(deviceId));
                if (hr == 0)
                {
                    applied++;
                }
                else
                {
                    lastError = $"SetPersistedDefaultAudioEndpoint failed for pid {pid}: 0x{hr:X8}";
                }
            }

            if (applied == 0)
            {
                return RoutingResult.NotRecorded(lastError ?? "No process accepted the device.");
            }

            // Verified on Windows 11: the persisted choice is written to the OS store but a
            // session that is already open does not move. Windows applies it when the
            // app next creates a session, so say that instead of implying it took effect.
            return new RoutingResult(
                true,
                false,
                $"{successMessage} ({applied} process(es)). Applies when the app next creates an audio session.");
        }
        finally
        {
            Release(factory);
        }
    }

    internal static string NormalizeExecutable(string executableName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executableName);
        var name = Path.GetFileName(executableName.Trim());
        return name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name : name + ".exe";
    }

    private static List<uint> FindProcessIds(string executableName)
    {
        var withoutExtension = Path.GetFileNameWithoutExtension(executableName);
        var ids = new List<uint>();
        foreach (var process in System.Diagnostics.Process.GetProcessesByName(withoutExtension))
        {
            using (process)
            {
                ids.Add((uint)process.Id);
            }
        }

        return ids;
    }

    /// <summary>
    /// Builds the device-interface path the API expects.
    /// </summary>
    /// <remarks>
    /// <c>IMMDevice::GetId</c> returns the short form <c>{0.0.0.…}.{guid}</c>, but
    /// <c>SetPersistedDefaultAudioEndpoint</c> wants the full device-interface path
    /// <c>\\?\SWD#MMDEVAPI#&lt;id&gt;#&lt;class-guid&gt;</c> (the same string Windows
    /// stores under <c>DefaultEndpoint</c>). Passing the short form is rejected with
    /// E_INVALIDARG.
    /// </remarks>
    internal static string BuildEndpointPath(string deviceId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceId);
        var trimmed = deviceId.Trim();

        // Already a full interface path.
        if (trimmed.Contains("SWD#MMDEVAPI", StringComparison.OrdinalIgnoreCase))
        {
            return trimmed;
        }

        return @"\\?\SWD#MMDEVAPI#" + trimmed + "#" + RenderInterfaceClass;
    }

    /// <summary>Device-interface class GUID for render endpoints.</summary>
    internal const string RenderInterfaceClass = "{e6327cad-dcec-4949-ae8a-991e976a79d2}";
    private static int InvokeSetPersisted(IntPtr factory, uint processId, string? deviceId)
    {
        var hstring = IntPtr.Zero;
        try
        {
            if (deviceId is not null)
            {
                var hr = WindowsCreateString(deviceId, deviceId.Length, out hstring);
                if (hr != 0)
                {
                    return hr;
                }
            }

            var fn = GetMethod(factory, SetMethodIndex);
            if (fn == IntPtr.Zero)
            {
                return ENoInterface;
            }

            var call = Marshal.GetDelegateForFunctionPointer<SetPersistedDelegate>(fn);

            // Set every role, matching what SoundVolumeView writes: Windows keeps a
            // separate endpoint per role, and an app that only sets "multimedia"
            // would fall back to the default for its "console" stream.
            var roleHr = 0;
            foreach (var role in new[] { ERole.Console, ERole.Multimedia, ERole.Communications })
            {
                roleHr = call(factory, processId, (int)EDataFlow.Render, (int)role, hstring);
                if (roleHr != 0)
                {
                    break;
                }
            }

            return roleHr;
        }
        finally
        {
            if (hstring != IntPtr.Zero)
            {
                _ = WindowsDeleteString(hstring);
            }
        }
    }

    private static bool TryGetPersisted(IntPtr factory, uint processId, out string? deviceId)
    {
        deviceId = null;
        var fn = GetMethod(factory, GetMethodIndex);
        if (fn == IntPtr.Zero)
        {
            return false;
        }

        var call = Marshal.GetDelegateForFunctionPointer<GetPersistedDelegate>(fn);
        var hr = call(factory, processId, (int)EDataFlow.Render, (int)ERole.Multimedia, out var raw);
        if (hr != 0 || raw == IntPtr.Zero)
        {
            return false;
        }

        try
        {
            deviceId = Marshal.PtrToStringUni(raw);
            return !string.IsNullOrWhiteSpace(deviceId);
        }
        finally
        {
            _ = WindowsDeleteString(raw);
        }
    }

    /// <summary>Resolves the function pointer for an interface method slot.</summary>
    private static IntPtr GetMethod(IntPtr instance, int methodIndex)
    {
        var vtable = Marshal.ReadIntPtr(instance);
        if (vtable == IntPtr.Zero)
        {
            return IntPtr.Zero;
        }

        return Marshal.ReadIntPtr(vtable, (FirstMethodSlot + methodIndex) * IntPtr.Size);
    }

    private static (bool Ok, IntPtr Factory, string? Error) CreateFactoryOrFail()
    {
        return TryCreateFactory(out var factory, out var error)
            ? (true, factory, null)
            : (false, IntPtr.Zero, error);
    }

    internal static bool TryCreateFactory(out IntPtr factory, out string? error)
    {
        factory = IntPtr.Zero;
        error = null;

        if (TryActivate(IidFor21H2, out factory, out var firstHr) || TryActivate(IidForDownlevel, out factory, out var secondHr))
        {
            return true;
        }

        error = "Windows.Media.Internal.AudioPolicyConfig is not available on this Windows build " +
                $"(21H2 IID 0x{firstHr:X8}, downlevel IID 0x{secondHr:X8}).";
        return false;
    }

    private static bool TryActivate(Guid iid, out IntPtr factory, out int hr)
    {
        factory = IntPtr.Zero;
        var classId = IntPtr.Zero;
        try
        {
            hr = WindowsCreateString(ActivatableClassId, ActivatableClassId.Length, out classId);
            if (hr != 0)
            {
                return false;
            }

            var localIid = iid;
            hr = RoGetActivationFactory(classId, ref localIid, out factory);
            return hr == 0 && factory != IntPtr.Zero;
        }
        finally
        {
            if (classId != IntPtr.Zero)
            {
                _ = WindowsDeleteString(classId);
            }
        }
    }

    private static void Release(IntPtr instance)
    {
        if (instance == IntPtr.Zero)
        {
            return;
        }

        var vtable = Marshal.ReadIntPtr(instance);
        if (vtable != IntPtr.Zero)
        {
            var fn = Marshal.ReadIntPtr(vtable, ReleaseSlot * IntPtr.Size);
            if (fn != IntPtr.Zero)
            {
                var release = Marshal.GetDelegateForFunctionPointer<ReleaseDelegate>(fn);
                _ = release(instance);
            }
        }
    }

    private static bool ReleaseAndCheck(IntPtr instance)
    {
        var ok = instance != IntPtr.Zero;
        Release(instance);
        return ok;
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int SetPersistedDelegate(IntPtr instance, uint processId, int flow, int role, IntPtr deviceId);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int GetPersistedDelegate(IntPtr instance, uint processId, int flow, int role, out IntPtr deviceId);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate int ReleaseDelegate(IntPtr instance);

    [DllImport("combase.dll", ExactSpelling = true)]
    private static extern int RoGetActivationFactory(IntPtr activatableClassId, ref Guid iid, out IntPtr factory);

    [DllImport("combase.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int WindowsCreateString(string sourceString, int length, out IntPtr hstring);

    [DllImport("combase.dll", ExactSpelling = true)]
    private static extern int WindowsDeleteString(IntPtr hstring);

    private enum EDataFlow
    {
        Render = 0,
        Capture = 1,
        All = 2,
    }

    private enum ERole
    {
        Console = 0,
        Multimedia = 1,
        Communications = 2,
    }

    /// <summary>Unused; kept so the EFail constant stays referenced by analyzers.</summary>
    internal static int GenericFailure => EFail;
}







