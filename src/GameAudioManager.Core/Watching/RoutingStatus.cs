using GameAudioManager.Core.Audio;

namespace GameAudioManager.Core.Watching;

/// <summary>
/// How the app currently stands relative to its rule.
/// </summary>
/// <remarks>
/// These are deliberately distinct because they need different user actions:
/// <see cref="Pending"/> means "restart the app", <see cref="NoActiveCandidate"/>
/// means "plug the device in", <see cref="Failed"/> means "read the error".
/// Collapsing them into one "not applied" state is what made the old UI confusing.
/// </remarks>
public enum RoutingState
{
    /// <summary>No rule, or the rule is disabled.</summary>
    NotConfigured,

    /// <summary>The application is not running.</summary>
    NotRunning,

    /// <summary>A device was chosen and handed to Windows in this run.</summary>
    Applied,

    /// <summary>The setting is recorded but the running session has not moved yet.</summary>
    Pending,

    /// <summary>None of the candidate devices is currently connected.</summary>
    NoActiveCandidate,

    /// <summary>The apply call failed.</summary>
    Failed,
}

/// <summary>Result of evaluating one app during a watch cycle.</summary>
public sealed record RoutingStatus(
    string ProcessName,
    string DisplayName,
    bool IsRunning,
    RoutingState State,
    string? AppliedDeviceId,
    string? AppliedDeviceName,
    string? DestinationDeviceId,
    MuteState Mute,
    string? Error)
{
    public string StateText => State switch
    {
        RoutingState.Applied => "適用済み",
        RoutingState.Pending => "反映待ち",
        RoutingState.NoActiveCandidate => "デバイス未接続",
        RoutingState.Failed => "失敗",
        RoutingState.NotRunning => "未起動",
        _ => "ルールなし",
    };
}
