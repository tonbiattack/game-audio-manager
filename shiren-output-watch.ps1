function New-ShirenWatchState {
    return @{ Process = $null; DeviceAvailable = $false; Destination = $null; Applied = $false }
}

function Get-PreferredActiveDevice {
    param([string[]]$Candidates, [string[]]$ActiveDevices)

    foreach ($candidate in $Candidates) {
        if ($ActiveDevices -contains $candidate) {
            return $candidate
        }
    }
    return $null
}

function Split-ShirenOutputDevices {
    param([string[]]$Values)

    return @($Values | ForEach-Object { $_ -split '\|' } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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
    param($State, $ProcessIdentity, [string]$Destination, [scriptblock]$Apply)

    $deviceAvailable = -not [string]::IsNullOrEmpty($Destination)
    if ($State.Process -ne $ProcessIdentity -or -not $deviceAvailable -or -not $State.DeviceAvailable -or $State.Destination -ne $Destination) {
        $State.Applied = $false
    }
    $State.Process = $ProcessIdentity
    $State.DeviceAvailable = $deviceAvailable
    $State.Destination = $Destination
    if ($null -ne $ProcessIdentity -and $deviceAvailable -and -not $State.Applied) {
        $State.Applied = [bool](& $Apply $Destination)
    }
}
