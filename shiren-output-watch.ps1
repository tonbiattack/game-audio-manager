function New-ShirenWatchState {
    return @{ Process = $null; DeviceAvailable = $false; Applied = $false }
}

function Enter-ShirenWatchMutex {
    param([Parameter(Mandatory = $true)][string]$Name)

    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new($false, "Local\$Name", [ref]$createdNew)
    if (-not $createdNew -or -not $mutex.WaitOne(0)) {
        $mutex.Dispose()
        return $null
    }
    return $mutex
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
