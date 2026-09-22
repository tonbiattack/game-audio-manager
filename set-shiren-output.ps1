param(
    [string]$Device,
    [string]$ProcessName = "ShirenTheWanderer6",
    [string]$SvclPath = "$PSScriptRoot\svcl.exe",
    [switch]$Reset,
    [switch]$List,
    [switch]$RawList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ShirenProcess {
    param([string]$ExplicitProcessName)

    $name = [System.IO.Path]::GetFileNameWithoutExtension($ExplicitProcessName)
    $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)

    if ($processes.Count -eq 0) {
        throw "Shiren 6 process was not found. Expected process: $name (ShirenTheWanderer6.exe). Run .\detect-shiren-process.ps1 to diagnose."
    }

    return $processes | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $SvclPath)) {
    throw "svcl.exe was not found: $SvclPath. Download SoundVolumeCommandLine from NirSoft and place svcl.exe next to this script, or specify -SvclPath."
}

if ($RawList) {
    & $SvclPath /Stdout /scomma ""
    exit $LASTEXITCODE
}

if ($List) {
    $devices = @(
        & $SvclPath /Stdout /scomma "" |
            ConvertFrom-Csv |
            Where-Object {
                $_.Type -eq "Device" -and
                $_.Direction -eq "Render" -and
                $_.'Device State' -eq "Active"
            } |
            Sort-Object 'Device Name' |
            Select-Object @{ Name = "指定値"; Expression = { $_.'Device Name' } }, @{ Name = "表示名"; Expression = { $_.Name } }, @{ Name = "既定"; Expression = { $_.Default } }
    )

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list audio devices. svcl.exe exit code: $LASTEXITCODE"
    }

    if ($devices.Count -eq 0) {
        Write-Warning "No active render devices were found. Use -RawList to inspect all SoundVolumeCommandLine entries."
        exit 0
    }

    Write-Output "Use the value in '指定値' with -Device:"
    $devices | Format-Table -AutoSize | Out-String -Width 4096 | Write-Output
    exit 0
}

$process = Resolve-ShirenProcess -ExplicitProcessName $ProcessName
$exeName = "$($process.ProcessName).exe"

Write-Host "Detected Shiren 6:"
Write-Host "  Process: $exeName"
Write-Host "  PID:     $($process.Id)"

if ($Reset) {
    Write-Host "Resetting Shiren output device to Windows default..."
    & $SvclPath /SetAppDefault DefaultRenderDevice all $exeName

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to reset the output device. svcl.exe exit code: $LASTEXITCODE"
    }

    Write-Host "Shiren output: Windows default"
    exit 0
}

if (-not $Device) {
    throw "Specify the destination device with -Device. Use -List to inspect available audio devices."
}

Write-Host "Routing Shiren audio to: $Device"
& $SvclPath /SetAppDefault $Device all $exeName

if ($LASTEXITCODE -ne 0) {
    throw "Failed to set the output device. svcl.exe exit code: $LASTEXITCODE"
}

Write-Host "Shiren output: $Device"
