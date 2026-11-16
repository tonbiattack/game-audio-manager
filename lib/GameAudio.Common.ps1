Set-StrictMode -Version Latest

function ConvertTo-GameProcessName {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    return [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
}

function Get-GameProcesses {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    $name = ConvertTo-GameProcessName -ProcessName $ProcessName
    return @(Get-Process -Name $name -ErrorAction SilentlyContinue)
}

function Resolve-GameProcess {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    $name = ConvertTo-GameProcessName -ProcessName $ProcessName
    $processes = @(Get-GameProcesses -ProcessName $name)

    if ($processes.Count -eq 0) {
        throw "Game process '$name' was not found. Start the game first, then run .\detect-game-process.ps1 -ProcessName '$name' to diagnose."
    }

    return $processes[0]
}

function Get-GameAudioSvclPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath
    )

    return (Join-Path $RepositoryPath 'vendor\svcl\svcl.exe')
}

function Assert-GameAudioSvclPath {
    param(
        [Parameter(Mandatory = $true)][string]$SvclPath
    )

    if (-not (Test-Path -LiteralPath $SvclPath -PathType Leaf)) {
        throw "svcl.exe was not found: $SvclPath. Restore the bundled vendor\svcl\ files, download SoundVolumeCommandLine from NirSoft, or specify -SvclPath."
    }
}

# Reads the active render device names from svcl.exe.
function Get-GameAudioActiveDeviceName {
    param(
        [Parameter(Mandatory = $true)][string]$SvclPath
    )

    $csv = @(& $SvclPath /Stdout /scomma '')
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list audio devices. svcl.exe exit code: $LASTEXITCODE"
    }
    return @($csv | ConvertFrom-Csv | Where-Object {
        $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and $_.'Device State' -eq 'Active'
    } | ForEach-Object { $_.'Device Name' })
}

# svcl.exe accepts an unknown device name and still exits 0, so a typo silently
# leaves the routing unchanged. Validate the name against the active render
# devices before invoking it.
#
# The comparison is an exact, case-insensitive match. svcl.exe also accepts
# partial names, but matching loosely here would let a short name select an
# unintended device.
function Assert-GameAudioDeviceName {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Device,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$AvailableDevices
    )

    if ([string]::IsNullOrWhiteSpace($Device)) {
        throw 'Specify the destination device with -Device. Use -List to inspect available audio devices.'
    }

    # Device names are copied from -List output, which can pick up stray spaces.
    $trimmed = $Device.Trim()
    $available = @($AvailableDevices)
    foreach ($candidate in $available) {
        if ([string]::Equals($candidate, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $candidate
        }
    }

    if ($available.Count -eq 0) {
        throw "No active render device was found, so '$trimmed' cannot be selected. Connect an output device, then run .\set-game-output.ps1 -List."
    }

    $list = ($available | Sort-Object | ForEach-Object { "  $_" }) -join [Environment]::NewLine
    throw "Output device was not found: '$trimmed'. Run .\set-game-output.ps1 -List and use one of these values with -Device:$([Environment]::NewLine)$list"
}
