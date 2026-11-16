param(
    [ValidateRange(1, 3600)][int]$IntervalSeconds = 5,
    [string]$ConfigPath,
    [string]$StatusPath,
    [string]$SvclPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\GameAudio.Common.ps1"
. "$PSScriptRoot\lib\GameAudio.Config.ps1"
. "$PSScriptRoot\lib\GameAudio.Watch.ps1"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot 'config\games.json' }
if ([string]::IsNullOrWhiteSpace($StatusPath)) { $StatusPath = Join-Path $PSScriptRoot 'config\watcher-status.json' }
if ([string]::IsNullOrWhiteSpace($SvclPath)) { $SvclPath = Get-GameAudioSvclPath -RepositoryPath $PSScriptRoot }

Assert-GameAudioSvclPath -SvclPath $SvclPath

function Get-GameWatchActiveDevices {
    $csv = @(& $SvclPath /Stdout /scomma '')
    if ($LASTEXITCODE -ne 0) { throw "Device enumeration failed (exit code $LASTEXITCODE)." }
    return @($csv | ConvertFrom-Csv | Where-Object {
        $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and $_.'Device State' -eq 'Active'
    } | ForEach-Object { $_.'Device Name' })
}

$getProcess = {
    param($ProcessName)
    Get-GameProcesses -ProcessName $ProcessName | Select-Object -First 1
}

$applyDevice = {
    param($ProcessName, $Device)
    & $SvclPath /SetAppDefault $Device all "$ProcessName.exe" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "svcl.exe exit code $LASTEXITCODE"
    }
}

$mutex = Enter-GameAudioWatchMutex -Name 'game-audio-output-watch'
if ($null -eq $mutex) {
    Write-Host 'The game output watcher is already running.'
    exit 0
}

$stopEvent = New-GameAudioWatchStopEvent
Write-Host "Monitoring enabled games in $ConfigPath every $IntervalSeconds seconds. Stop from the GUI or kill process $PID."

$watchStates = @{}
$startedAt = [DateTime]::UtcNow

try {
    while (-not $stopEvent.WaitOne($IntervalSeconds * 1000)) {
        try {
            if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
                $games = @(Get-GameConfiguration -Path $ConfigPath)
            }
            else {
                # A missing configuration idles; the GUI can create it at any time.
                $games = @()
            }
            $activeDevices = Get-GameWatchActiveDevices
            $apps = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices $activeDevices -States $watchStates -GetProcess $getProcess -ApplyDevice $applyDevice)
            Write-GameAudioWatchStatus -Path $StatusPath -Status ([PSCustomObject]@{
                watcher = [PSCustomObject]@{
                    pid = $PID
                    startedAt = $startedAt.ToString('o')
                    updatedAt = [DateTime]::UtcNow.ToString('o')
                    intervalSeconds = $IntervalSeconds
                    configPath = $ConfigPath
                }
                apps = $apps
            })
        }
        catch {
            # An incomplete cycle must not leave stale 'applied' state behind.
            foreach ($state in $watchStates.Values) { $state.Applied = $false }
            Write-Warning "Watch cycle failed; will retry: $($_.Exception.Message)"
        }
    }
}
finally {
    Remove-Item -LiteralPath $StatusPath -Force -ErrorAction SilentlyContinue
    $stopEvent.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
