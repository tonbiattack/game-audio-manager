param(
    [string]$Device,
    [string]$ProcessName,
    [string]$SvclPath = "$PSScriptRoot\svcl.exe",
    [switch]$Reset,
    [switch]$List,
    [switch]$RawList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\GameAudio.Common.ps1"

if (-not (Test-Path -LiteralPath $SvclPath)) {
    throw "svcl.exe was not found: $SvclPath. Download SoundVolumeCommandLine from NirSoft and place svcl.exe next to this script, or specify -SvclPath."
}

if ($RawList) {
    & $SvclPath /Stdout /scomma ''
    exit $LASTEXITCODE
}

if ($List) {
    $valueLabel = -join @(0x6307, 0x5b9a, 0x5024 | ForEach-Object { [char]$_ })
    $displayLabel = -join @(0x8868, 0x793a, 0x540d | ForEach-Object { [char]$_ })
    $defaultLabel = -join @(0x65e2, 0x5b9a | ForEach-Object { [char]$_ })
    $devices = @(
        & $SvclPath /Stdout /scomma '' |
            ConvertFrom-Csv |
            Where-Object {
                $_.Type -eq 'Device' -and
                $_.Direction -eq 'Render' -and
                $_.'Device State' -eq 'Active'
            } |
            Sort-Object 'Device Name' |
            Select-Object @{ Name = $valueLabel; Expression = { $_.'Device Name' } }, @{ Name = $displayLabel; Expression = { $_.Name } }, @{ Name = $defaultLabel; Expression = { $_.Default } }
    )

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list audio devices. svcl.exe exit code: $LASTEXITCODE"
    }

    if ($devices.Count -eq 0) {
        Write-Warning 'No active render devices were found. Use -RawList to inspect all SoundVolumeCommandLine entries.'
        exit 0
    }

    Write-Output "Use the value in '$valueLabel' with -Device:"
    $devices | Format-Table -AutoSize | Out-String -Width 4096 | Write-Output
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ProcessName)) {
    throw 'Specify the game process with -ProcessName.'
}

$process = Resolve-GameProcess -ProcessName $ProcessName
$exeName = "$($process.ProcessName).exe"

Write-Host 'Detected game process:'
Write-Host "  Process: $exeName"
Write-Host "  PID:     $($process.Id)"

if ($Reset) {
    Write-Host 'Resetting game output device to Windows default...'
    & $SvclPath /SetAppDefault DefaultRenderDevice all $exeName

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to reset the output device. svcl.exe exit code: $LASTEXITCODE"
    }

    Write-Host 'Game output: Windows default'
    exit 0
}

if (-not $Device) {
    throw 'Specify the destination device with -Device. Use -List to inspect available audio devices.'
}

Write-Host "Routing game audio to: $Device"
& $SvclPath /SetAppDefault $Device all $exeName

if ($LASTEXITCODE -ne 0) {
    throw "Failed to set the output device. svcl.exe exit code: $LASTEXITCODE"
}

Write-Host "Game output: $Device"
