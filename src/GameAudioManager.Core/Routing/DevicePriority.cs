using GameAudioManager.Core.Audio;

namespace GameAudioManager.Core.Routing;

/// <summary>
/// The outcome of choosing a device for an application.
/// </summary>
/// <param name="DeviceId">The device to apply, or null when nothing can be applied.</param>
/// <param name="Reason">Explains why, for the UI to show instead of guessing.</param>
public sealed record RoutingDecision(string? DeviceId, RoutingDecisionKind Kind, string Reason)
{
    public bool ShouldApply => Kind == RoutingDecisionKind.Apply;
}

public enum RoutingDecisionKind
{
    /// <summary>A candidate is connected and became the target.</summary>
    Apply,

    /// <summary>No candidate device is connected right now.</summary>
    NoActiveCandidate,

    /// <summary>The application is not running.</summary>
    NotRunning,

    /// <summary>The rule is disabled.</summary>
    RuleDisabled,

    /// <summary>The rule has no candidates.</summary>
    NoCandidates,

    /// <summary>Manual mode: the watcher must not override the user's choice.</summary>
    AutoApplyDisabled,
}

/// <summary>
/// Chooses which device an application should use, honouring the ordered candidate
/// list and the current device state.
/// </summary>
public static class DevicePriority
{
    /// <summary>
    /// Returns the first candidate id that is present and active, in priority order.
    /// </summary>
    public static string? SelectPreferred(IEnumerable<string> candidateIds, IEnumerable<AudioDevice> devices)
    {
        ArgumentNullException.ThrowIfNull(candidateIds);
        ArgumentNullException.ThrowIfNull(devices);

        var activeById = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var device in devices.Where(d => d.IsActive))
        {
            activeById[device.Id] = device.Id;
        }

        foreach (var candidate in candidateIds)
        {
            if (!string.IsNullOrWhiteSpace(candidate) && activeById.TryGetValue(candidate, out var canonical))
            {
                // Return the canonical id, not the caller's spelling, so the
                // configured list never drifts in casing.
                return canonical;
            }
        }

        return null;
    }

    /// <summary>Decides what to do for one rule, without touching the OS.</summary>
    public static RoutingDecision Decide(
        Configuration.AppRule? rule,
        bool isRunning,
        IEnumerable<string> candidateIds,
        IEnumerable<AudioDevice> devices)
    {
        if (rule is null)
        {
            return new RoutingDecision(null, RoutingDecisionKind.NoCandidates, "このアプリにはルールがありません。");
        }

        if (!rule.Enabled)
        {
            return new RoutingDecision(null, RoutingDecisionKind.RuleDisabled, "ルールが無効です。");
        }

        if (!rule.AutoApply)
        {
            return new RoutingDecision(null, RoutingDecisionKind.AutoApplyDisabled, "自動適用がオフです。");
        }

        var candidates = candidateIds as IReadOnlyList<string> ?? candidateIds.ToList();
        if (candidates.Count == 0)
        {
            return new RoutingDecision(null, RoutingDecisionKind.NoCandidates, "出力先の候補がありません。");
        }

        if (!isRunning)
        {
            return new RoutingDecision(null, RoutingDecisionKind.NotRunning, "アプリは起動していません。");
        }

        var selected = SelectPreferred(candidates, devices);
        if (selected is null)
        {
            return new RoutingDecision(null, RoutingDecisionKind.NoActiveCandidate, "候補の出力先がどれも接続されていません。");
        }

        return new RoutingDecision(selected, RoutingDecisionKind.Apply, "候補から選択しました。");
    }

    /// <summary>
    /// Moves an item within an ordered list. Out-of-range moves are no-ops rather
    /// than errors, so the UI can bind buttons without guarding every click.
    /// </summary>
    public static IReadOnlyList<string> Move(IReadOnlyList<string> items, int index, int offset)
    {
        ArgumentNullException.ThrowIfNull(items);
        if (index < 0 || index >= items.Count)
        {
            return items;
        }

        var target = index + offset;
        if (target < 0 || target >= items.Count)
        {
            return items;
        }

        var copy = items.ToList();
        (copy[index], copy[target]) = (copy[target], copy[index]);
        return copy;
    }

    /// <summary>Adds a device id if absent, keeping the existing order.</summary>
    public static IReadOnlyList<string> Add(IReadOnlyList<string> items, string deviceId)
    {
        ArgumentNullException.ThrowIfNull(items);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceId);

        if (items.Any(i => string.Equals(i, deviceId, StringComparison.OrdinalIgnoreCase)))
        {
            return items;
        }

        var copy = items.ToList();
        copy.Add(deviceId);
        return copy;
    }

    /// <summary>Removes a device id if present.</summary>
    public static IReadOnlyList<string> Remove(IReadOnlyList<string> items, string deviceId)
    {
        ArgumentNullException.ThrowIfNull(items);
        ArgumentException.ThrowIfNullOrWhiteSpace(deviceId);

        return items
            .Where(i => !string.Equals(i, deviceId, StringComparison.OrdinalIgnoreCase))
            .ToList();
    }
}
