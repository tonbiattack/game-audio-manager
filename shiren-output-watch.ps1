function New-ShirenWatchState {
    return @{ Process = $null; DeviceAvailable = $false; Applied = $false }
}

function Update-ShirenWatchState {
    param($State, $ProcessIdentity, [bool]$DeviceAvailable, [scriptblock]$Apply)

    if ($State.Process -ne $ProcessIdentity -or -not $DeviceAvailable -or -not $State.DeviceAvailable) {
        $State.Applied = $false
    }
    $State.Process = $ProcessIdentity
    $State.DeviceAvailable = $DeviceAvailable
    if ($null -ne $ProcessIdentity -and $DeviceAvailable -and -not $State.Applied) {
        $State.Applied = [bool](& $Apply)
    }
}
