param(
    [string]$Device,
    [string]$ProcessName,
    [string]$Game,
    [string]$ConfigPath,
    [string]$SvclPath,
    [switch]$Reset,
    [switch]$List,
    [switch]$RawList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\GameAudio.Common.ps1"

if ([string]::IsNullOrWhiteSpace($SvclPath)) {
    $SvclPath = Get-GameAudioSvclPath -RepositoryPath $PSScriptRoot
}

Assert-GameAudioSvclPath -SvclPath $SvclPath

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

if (-not [string]::IsNullOrWhiteSpace($Game) -and -not [string]::IsNullOrWhiteSpace($ProcessName)) {
    throw 'Specify either -Game or -ProcessName, not both.'
}

if (-not [string]::IsNullOrWhiteSpace($Game)) {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $PSScriptRoot 'config\games.json'
    }
    . "$PSScriptRoot\lib\GameAudio.Config.ps1"
    $configuredGame = Resolve-ConfiguredGame -Games @(Get-GameConfiguration -Path $ConfigPath) -GameName $Game
    $ProcessName = $configuredGame.ProcessName
}

if ([string]::IsNullOrWhiteSpace($ProcessName)) {
    throw 'Specify the game with -Game or -ProcessName.'
}

$processes = @(Get-GameProcesses -ProcessName $ProcessName)
if ($processes.Count -eq 0) {
    $name = ConvertTo-GameProcessName -ProcessName $ProcessName
    throw "Game process '$name' was not found. Start the game first, then run .\detect-game-process.ps1 -ProcessName '$name' to diagnose."
}
$exeName = "$($processes[0].ProcessName).exe"

Write-Host 'Detected game process:'
Write-Host "  Process: $exeName"
$pidList = @($processes | ForEach-Object { $_.Id })
if ($pidList.Count -le 5) {
    Write-Host "  PID:     $($pidList -join ', ')"
}
else {
    Write-Host "  PID:     $($pidList[0..4] -join ', '), ... ($($pidList.Count) total)"
}
# svcl.exe routes per executable name, so every PID under that name is covered.
if ($processes.Count -gt 1) {
    Write-Host "  Note:    $($processes.Count) processes share this name; the output device applies to all of them."
}

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

# svcl.exe exits 0 for an unknown device name, so validate before invoking it.
$Device = Assert-GameAudioDeviceName -Device $Device -AvailableDevices @(Get-GameAudioActiveDeviceName -SvclPath $SvclPath)

Write-Host "Routing game audio to: $Device"
& $SvclPath /SetAppDefault $Device all $exeName

if ($LASTEXITCODE -ne 0) {
    throw "Failed to set the output device. svcl.exe exit code: $LASTEXITCODE"
}

Write-Host "Game output: $Device"
