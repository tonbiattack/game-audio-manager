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
if ([string]::IsNullOrWhiteSpace($SvclPath)) { $SvclPath = Join-Path $PSScriptRoot 'svcl.exe' }

if (-not (Test-Path -LiteralPath $SvclPath -PathType Leaf)) {
    throw "svcl.exe was not found: $SvclPath. Download SoundVolumeCommandLine from NirSoft and place svcl.exe next to this script, or specify -SvclPath."
}

function Get-GameWatchProcessIdentity {
    param($Process)

    if ($null -eq $Process) { return $null }
    return '{0}:{1}' -f $Process.Id, $Process.StartTime.ToUniversalTime().Ticks
}

function Get-GameWatchActiveDevices {
    $csv = @(& $SvclPath /Stdout /scomma '')
    if ($LASTEXITCODE -ne 0) { throw "Device enumeration failed (exit code $LASTEXITCODE)." }
    return @($csv | ConvertFrom-Csv | Where-Object {
        $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and $_.'Device State' -eq 'Active'
    } | ForEach-Object { $_.'Device Name' })
}

function Invoke-GameAudioWatchCycle {
    param(
        [AllowEmptyCollection()][object[]]$Games,
        [AllowEmptyCollection()][string[]]$ActiveDevices,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$States
    )

    $applicationStatuses = @()
    foreach ($game in @(@($Games) | Where-Object { $_.Enabled })) {
        $process = $null
        $state = $null
        try {
            $processName = ConvertTo-GameProcessName -ProcessName $game.ProcessName
            $process = Get-GameProcesses -ProcessName $processName | Select-Object -First 1
            $identity = Get-GameWatchProcessIdentity -Process $process
            $destination = Get-PreferredConfiguredDevice -Candidates @($game.OutputDevices) -ActiveDevices $ActiveDevices

            $key = $processName.ToLowerInvariant()
            if (-not $States.Contains($key)) { $States[$key] = New-GameAudioWatchState }
            $state = $States[$key]

            $exeName = "$processName.exe"
            $apply = {
                param($Device, $State)
                try {
                    & $SvclPath /SetAppDefault $Device all $exeName | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        $State.LastError = "svcl.exe exit code $LASTEXITCODE"
                        return $false
                    }
                    $State.LastError = $null
                    return $true
                }
                catch {
                    $State.LastError = $_.Exception.Message
                    return $false
                }
            }
            Update-GameAudioWatchState $state $identity $destination $apply
        }
        catch {
            # An incomplete observation must not be treated as a successful application.
            if ($null -ne $state) {
                $state.Applied = $false
                $state.LastError = $_.Exception.Message
            }
        }

        $appliedDevice = $null
        $appliedAt = $null
        $lastError = $null
        if ($null -ne $state) {
            if ($state.Applied) {
                $appliedDevice = $state.AppliedDevice
                $appliedAt = $state.AppliedAt
            }
            $lastError = $state.LastError
        }
        $applicationStatuses += [PSCustomObject]@{
            name = $game.Name
            processName = $game.ProcessName
            enabled = [bool]$game.Enabled
            running = ($null -ne $process)
            destinationDevice = $state.Destination
            appliedDevice = $appliedDevice
            appliedAt = $appliedAt
            error = $lastError
        }
    }
    return $applicationStatuses
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
            $apps = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices $activeDevices -States $watchStates)
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
