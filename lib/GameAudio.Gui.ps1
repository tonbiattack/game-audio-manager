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
