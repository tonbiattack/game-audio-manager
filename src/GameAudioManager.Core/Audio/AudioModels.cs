namespace GameAudioManager.Core.Audio;

/// <summary>Device state as exposed by the Windows Core Audio API.</summary>
public enum AudioDeviceState
{
    Active = 1,
    Disabled = 2,
    NotPresent = 4,
    Unplugged = 8,
}

/// <summary>
/// A render endpoint (a place audio can go, e.g. a headset or speakers).
/// </summary>
/// <remarks>
/// <see cref="Id"/> is the stable MMDevice interface id and is the canonical key
/// for configuration. <see cref="Name"/> is user-facing and may change when the
/// user renames a device, so it must not be used as an identity.
/// </remarks>
public sealed record AudioDevice(string Id, string Name, AudioDeviceState State, bool IsDefault)
{
    public bool IsActive => State == AudioDeviceState.Active;
}

/// <summary>One application audio session on one render endpoint.</summary>
public sealed record AudioSessionInfo(
    uint ProcessId,
    string? ProcessName,
    string DeviceId,
    string? DeviceName,
    bool IsMuted,
    bool IsSystemSounds);

/// <summary>Describes the mute state across every session of one application.</summary>
public sealed record MuteState(bool HasSession, bool IsMuted, bool IsMixed, int SessionCount, int EndpointCount)
{
    public static MuteState None { get; } = new(false, false, false, 0, 0);
}

public interface IAudioDeviceService
{
    /// <summary>Lists render endpoints. Inactive endpoints are included so rules survive unplugging.</summary>
    IReadOnlyList<AudioDevice> GetRenderDevices();

    /// <summary>Returns the device with the given id, or null when it is not present.</summary>
    AudioDevice? FindById(string deviceId);
}

public interface IAudioSessionService
{
    /// <summary>
    /// Lists every session whose process name matches, across all active render
    /// endpoints. Matching by name (not pid) is what makes multi-process apps work.
    /// </summary>
    IReadOnlyList<AudioSessionInfo> GetSessions(string processName);

    /// <summary>Sets the mute state on every matching session. Returns how many were changed.</summary>
    int SetMute(string processName, bool muted);
}

public interface IAppRoutingService
{
    /// <summary>
    /// Records the preferred output device for an executable. Returns a result that
    /// distinguishes "recorded" from "already applied to a live session", because
    /// Windows only picks the preference up when the next session is created.
    /// </summary>
    RoutingResult SetPreferredDevice(string executableName, string deviceId);

    /// <summary>Clears the preference so the app follows the Windows default.</summary>
    RoutingResult ResetToDefault(string executableName);

    /// <summary>Reports the currently recorded preference, or null when none is stored.</summary>
    string? GetPreferredDevice(string executableName);
}

/// <summary>
/// Outcome of a routing change.
/// </summary>
/// <param name="Recorded">The preference was written to the OS store.</param>
/// <param name="AppliedToLiveSession">
/// A live session was already moved. Windows does not do this, so this is normally
/// false and the UI must explain that a restart or a new audio session is needed.
/// </param>
public sealed record RoutingResult(bool Recorded, bool AppliedToLiveSession, string Message)
{
    public static RoutingResult NotRecorded(string message) => new(false, false, message);

    public static RoutingResult RecordedPendingSession(string message) => new(true, false, message);
}
