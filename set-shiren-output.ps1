param(
    [string]$Device,
    [string]$ProcessName = "",
    [string]$SvclPath = "$PSScriptRoot\svcl.exe",
    [switch]$Reset,
    [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ShirenProcess {
    param([string]$ExplicitProcessName)

    if ($ExplicitProcessName) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($ExplicitProcessName)
        return Get-Process -Name $name -ErrorAction Stop | Select-Object -First 1
    }

    return Get-Process | Where-Object {
        $_.MainWindowTitle -match "Shiren|シレン"
    } | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $SvclPath)) {
    throw "svcl.exe was not found: $SvclPath. Download SoundVolumeCommandLine from NirSoft and place svcl.exe next to this script, or specify -SvclPath."
}

if ($List) {
    & $SvclPath /Stdout /scomma ""
    exit $LASTEXITCODE
}

$process = Resolve-ShirenProcess -ExplicitProcessName $ProcessName

if (-not $process) {
    throw "Shiren process was not found. Start the game first, or specify -ProcessName."
}

$exeName = "$($process.ProcessName).exe"

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
