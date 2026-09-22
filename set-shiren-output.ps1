param(
    [string]$Device,
    [string]$ProcessName = "ShirenTheWanderer6",
    [string]$SvclPath = "$PSScriptRoot\svcl.exe",
    [switch]$Reset,
    [switch]$List
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

if ($List) {
    & $SvclPath /Stdout /scomma ""
    exit $LASTEXITCODE
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
