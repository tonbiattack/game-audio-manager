Set-StrictMode -Version Latest

function Get-GameAudioGuiState {
    param(
        [Parameter(Mandatory = $true)][object[]]$Games,
        [Parameter(Mandatory = $true)][string[]]$ActiveDevices,
        [Parameter(Mandatory = $true)][string[]]$RunningProcessNames
    )

    foreach ($game in $Games | Where-Object { $_.Enabled }) {
        $isRunning = $RunningProcessNames -contains $game.ProcessName
        $preferredDevice = $null
        foreach ($candidate in $game.OutputDevices) {
            if ($ActiveDevices -contains $candidate) {
                $preferredDevice = $candidate
                break
            }
        }

        [PSCustomObject]@{
            Name = $game.Name
            ProcessName = $game.ProcessName
            OutputDevices = [string[]]$game.OutputDevices
            IsRunning = [bool]$isRunning
            PreferredDevice = $preferredDevice
        }
    }
}

function Get-DiscoveredGameAudioApplications {
    param(
        [Parameter(Mandatory = $true)][object[]]$Processes,
        [Parameter(Mandatory = $true)][object[]]$ConfiguredGames
    )

    $configuredProcessNames = @($ConfiguredGames | ForEach-Object { $_.ProcessName })
    return @($Processes |
        Where-Object { $_.MainWindowHandle -ne 0 -and $configuredProcessNames -notcontains $_.ProcessName } |
        Sort-Object ProcessName -Unique |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.ProcessName
                ProcessName = $_.ProcessName
                OutputDevices = [string[]]@()
                IsRunning = $true
                PreferredDevice = $null
            }
        })
}

function New-GameAudioApplyRequest {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][string[]]$ActiveDevices,
        [switch]$UsePreferred,
        [string]$SelectedDevice
    )

    if (-not $Game.IsRunning) {
        throw "Game '$($Game.Name)' is not running."
    }

    $device = if ($UsePreferred) { $Game.PreferredDevice } else { $SelectedDevice }
    if ([string]::IsNullOrWhiteSpace($device)) {
        throw "No active output device is available for '$($Game.Name)'."
    }
    if ($ActiveDevices -notcontains $device) {
        throw "Selected output device is not active: $device"
    }

    return [PSCustomObject]@{
        GameName = $Game.Name
        ProcessName = $Game.ProcessName
        Device = $device
    }
}

function Format-GameAudioWatchStatusText {
    param(
        [AllowNull()]$Status,
        [Parameter(Mandatory = $true)][bool]$Running
    )

    if (-not $Running -or $null -eq $Status) {
        # An absent status file means the watcher is not recording (not running or still starting).
        return '監視: 停止中 (GUI を閉じても監視は継続します)'
    }

    $watcher = $Status.watcher
    $lines = @('監視中: PID {0}, {1}秒間隔' -f $watcher.pid, $watcher.intervalSeconds)
    foreach ($app in @($Status.apps)) {
        if (-not $app.enabled) { continue }
        if ($app.appliedDevice) {
            $line = '{0}: {1} に適用済み' -f $app.name, $app.appliedDevice
        }
        elseif (-not $app.running) {
            $line = '{0}: 未起動' -f $app.name
        }
        elseif (-not $app.destinationDevice) {
            $line = '{0}: 優先デバイスが未接続' -f $app.name
        }
        else {
            $line = '{0}: 適用待ち' -f $app.name
        }
        if ($app.error) { $line = '{0} (エラー: {1})' -f $line, $app.error }
        $lines += $line
    }
    if (-not ($lines.Count -gt 1)) { $lines += '監視対象のゲームはありません。' }
    return ($lines -join [Environment]::NewLine)
}

function ConvertTo-GameAudioRuleRequest {
    param(
        [Parameter(Mandatory = $true)]$Game,
        [string]$SelectedDevice
    )

    $device = [string]$SelectedDevice
    $configuredDevices = @(@($Game.OutputDevices))
    if ([string]::IsNullOrWhiteSpace($device) -and $configuredDevices.Count -eq 0) {
        throw "Select an output device to register '$($Game.Name)'."
    }
    return [PSCustomObject]@{
        ProcessName = $Game.ProcessName
        Name = [string]$Game.Name
        Device = $device
        HasRule = ($configuredDevices.Count -gt 0)
    }
}

# Describes the mute state of an application for the GUI.
#
# A missing audio session is a normal state, not an error: an application that
# has not played audio yet has nothing to mute. The GUI disables the button and
# explains why instead of failing.
function Get-GameAudioMuteState {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Sessions
    )

    $all = @($Sessions)
    if ($all.Count -eq 0) {
        return [PSCustomObject]@{
            HasSession = $false
            IsMuted = $false
            IsMixed = $false
            SessionCount = 0
            EndpointCount = 0
            Text = 'ミュート: 音声セッションなし'
        }
    }

    $mutedCount = @($all | Where-Object { $_.Muted }).Count
    $isMuted = ($mutedCount -eq $all.Count)
    $isMixed = ($mutedCount -gt 0 -and $mutedCount -lt $all.Count)
    $endpointCount = @($all | ForEach-Object { $_.DeviceId } | Sort-Object -Unique).Count

    if ($isMixed) {
        $text = 'ミュート: 混在 ({0}/{1} セッション)' -f $mutedCount, $all.Count
    }
    elseif ($isMuted) {
        $text = 'ミュート: ミュート中'
    }
    else {
        $text = 'ミュート: 解除'
    }

    return [PSCustomObject]@{
        HasSession = $true
        IsMuted = $isMuted
        IsMixed = $isMixed
        SessionCount = $all.Count
        EndpointCount = $endpointCount
        Text = $text
    }
}

# The button label states what the next click will do.
function Format-GameAudioMuteButtonText {
    param(
        [Parameter(Mandatory = $true)]$State
    )

    if (-not $State.HasSession) { return 'ミュート切替' }
    if ($State.IsMuted) { return 'ミュートを解除' }
    return 'ミュートする'
}

# Describes the ordered candidate list for the priority editor.
#
# The GUI shows the list with its priority so the order is visible, not just the
# set of devices. A device that is currently disconnected is still a valid
# candidate: it is kept so the rule survives unplugging a headset.
function Format-GameAudioPriorityDeviceList {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Devices,
        [AllowEmptyCollection()][string[]]$ActiveDevices = @()
    )

    $current = @($Devices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $active = @($ActiveDevices)
    $rows = @()
    for ($i = 0; $i -lt $current.Count; $i++) {
        $device = $current[$i]
        $isActive = $false
        foreach ($candidate in $active) {
            if ([string]::Equals($candidate, $device, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isActive = $true
                break
            }
        }
        $rows += [PSCustomObject]@{
            Priority = $i + 1
            Device = $device
            IsActive = $isActive
            Display = '{0}. {1}{2}' -f ($i + 1), $device, $(if ($isActive) { '' } else { ' (未接続)' })
        }
    }
    return $rows
}

# Builds the device list to save from the editor state.
#
# The list is authoritative when it has entries. When it is empty, the selected
# device is used so the original "pick a device and register" flow still works.
function Resolve-GameAudioPrioritySaveList {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Devices,
        [string]$SelectedDevice
    )

    $current = @($Devices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($current.Count -gt 0) { return [string[]]$current }
    if (-not [string]::IsNullOrWhiteSpace($SelectedDevice)) { return [string[]]@($SelectedDevice.Trim()) }
    throw 'Add at least one output device before saving the rule.'
}
