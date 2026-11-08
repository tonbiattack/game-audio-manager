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
