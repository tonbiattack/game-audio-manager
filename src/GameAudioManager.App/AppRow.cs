using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using GameAudioManager.Core.Audio;
using GameAudioManager.Core.Configuration;
using GameAudioManager.Core.Routing;
using GameAudioManager.Core.Watching;

namespace GameAudioManager.App;

/// <summary>One row in the application list.</summary>
public sealed class AppRow : INotifyPropertyChanged
{
    private RoutingStatus _status;
    private bool _isChecked;
    private int _autoApply;

    public AppRow(RoutingStatus status, AppRule? rule)
    {
        _status = status;
        Rule = rule;
        _isChecked = true;
        _autoApply = rule is { AutoApply: true, Enabled: true } ? 1 : 0;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public AppRule? Rule { get; }

    public string ProcessName => _status.ProcessName;

    public string DisplayName => _status.DisplayName;

    public RoutingStatus Status => _status;

    /// <summary>Filter helper: matches the name or the process name.</summary>
    public bool Matches(string filter)
    {
        if (string.IsNullOrWhiteSpace(filter))
        {
            return true;
        }

        return DisplayName.Contains(filter, StringComparison.CurrentCultureIgnoreCase)
            || ProcessName.Contains(filter, StringComparison.CurrentCultureIgnoreCase);
    }

    /// <summary>True while the row passes the current filter; bound to ListViewItem.Visibility.</summary>
    public bool IsChecked
    {
        get => _isChecked;
        set => Set(ref _isChecked, value);
    }

    /// <summary>Localized state label. Maps the enum rather than the Core-supplied text.</summary>
    public string StateText => Localization.Instance[StateKey(_status.State)];

    private static string StateKey(RoutingState state) => state switch
    {
        RoutingState.Applied => "StateApplied",
        RoutingState.Pending => "StatePending",
        RoutingState.NoActiveCandidate => "StateNoDevice",
        RoutingState.Failed => "StateFailed",
        RoutingState.NotRunning => "StateNotRunning",
        _ => "StateNoRule",
    };

    public string MuteText => _status.Mute switch
    {
        { HasSession: false } => Localization.Instance["MuteNone"],
        { IsMixed: true } => $"{Localization.Instance["MuteMixed"]} ({_status.Mute.SessionCount})",
        { IsMuted: true } => Localization.Instance["MuteOn"],
        _ => Localization.Instance["MuteOff"],
    };

    public string DeviceText => _status.AppliedDeviceName
        ?? _status.DestinationDeviceId
        ?? Localization.Instance["DefaultOutput"];

    /// <summary>Re-reads every localized label after a language change.</summary>
    public void RefreshLocalization()
    {
        Raise(nameof(StateText));
        Raise(nameof(MuteText));
        Raise(nameof(DeviceText));
        Raise(nameof(AutoApplyText));
    }

    /// <summary>1 = auto apply on, 0 = off. Bound to the row toggle for simplicity.</summary>
    public int AutoApply
    {
        get => _autoApply;
        set
        {
            if (Set(ref _autoApply, value))
            {
                Raise(nameof(AutoApplyText));
                Raise(nameof(IsAutoApplyEnabled));
            }
        }
    }

    public string AutoApplyText => _autoApply == 1 ? "自動" : "手動";

    /// <summary>Boolean view of <see cref="AutoApply"/> for the row checkbox.</summary>
    public bool IsAutoApplyEnabled
    {
        get => _autoApply == 1;
        set => AutoApply = value ? 1 : 0;
    }

    public void Update(RoutingStatus status, AppRule? rule)
    {
        _status = status;
        Raise(nameof(DisplayName));
        Raise(nameof(StateText));
        Raise(nameof(MuteText));
        Raise(nameof(DeviceText));
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        Raise(name);
        return true;
    }

    private void Raise(string? name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}



