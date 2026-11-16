$ErrorActionPreference = 'Stop'

$library = Join-Path $PSScriptRoot '..\lib\GameAudio.Watch.ps1'
$configLibrary = Join-Path $PSScriptRoot '..\lib\GameAudio.Config.ps1'
$commonLibrary = Join-Path $PSScriptRoot '..\lib\GameAudio.Common.ps1'
if (-not (Test-Path -LiteralPath $library)) { throw 'Game audio watch library is missing.' }
. $commonLibrary
. $configLibrary
. $library

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$ExpectedText, [string]$Message)
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($ExpectedText)) {
            throw "$Message Actual: $($_.Exception.Message)"
        }
        return
    }
    throw "$Message No exception was raised."
}

function New-TestDirectory {
    return Join-Path ([System.IO.Path]::GetTempPath()) ("game-audio-watch-{0}" -f [guid]::NewGuid())
}

# --- per-app watch state machine (same semantics as the Shiren watch) ---
$state = New-GameAudioWatchState
Assert-Equal $state.Applied $false 'A new watch state must start unapplied.'
$attempts = 0
$apply = { $script:attempts++; $args[1].LastError = $null; return $true }
Update-GameAudioWatchState $state 10 'first device' $apply
Update-GameAudioWatchState $state 10 'first device' $apply
Assert-Equal $attempts 1 'A stable process and device must not be reapplied.'
Assert-Equal $state.AppliedDevice 'first device' 'A successful application must record the device.'
Assert-True (-not [string]::IsNullOrEmpty($state.AppliedAt)) 'A successful application must record a timestamp.'
Update-GameAudioWatchState $state 11 'first device' $apply
Assert-Equal $attempts 2 'A restarted game must be reapplied.'
Update-GameAudioWatchState $state 11 $null $apply
Update-GameAudioWatchState $state 11 'first device' $apply
Assert-Equal $attempts 3 'A reconnected device must be reapplied.'
Update-GameAudioWatchState $state $null 'first device' $apply
Update-GameAudioWatchState $state 11 'first device' $apply
Assert-Equal $attempts 4 'A stopped and restarted game must be reapplied.'
Update-GameAudioWatchState $state 11 'fallback device' $apply
Assert-Equal $attempts 5 'A newly selected fallback device must be applied.'

$state = New-GameAudioWatchState
$attempts = 0
$retry = {
    $script:attempts++
    if ($script:attempts -gt 1) { $args[1].LastError = $null; return $true }
    $args[1].LastError = 'apply failed'
    return $false
}
Update-GameAudioWatchState $state 12 'first device' $retry
Assert-Equal $state.LastError 'apply failed' 'A failed application must record an error.'
Update-GameAudioWatchState $state 12 'first device' $retry
Assert-Equal $attempts 2 'A failed application must be retried.'
Assert-Equal $state.LastError $null 'A successful application must clear the error.'

# --- singleton mutex ---
$firstMutex = Enter-GameAudioWatchMutex -Name 'game-audio-watch-test'
if ($null -eq $firstMutex) { throw 'The first watcher must acquire its mutex.' }
$secondMutex = Enter-GameAudioWatchMutex -Name 'game-audio-watch-test'
if ($null -ne $secondMutex) { throw 'A second watcher must not acquire the same mutex.' }
$firstMutex.ReleaseMutex()
$firstMutex.Dispose()

# --- stop event ---
$stopEvent = New-GameAudioWatchStopEvent
try {
    Assert-Equal $stopEvent.WaitOne(0) $false 'A new stop event must start unsignalled.'
    Assert-Equal $stopEvent.WaitOne(10) $false 'A new stop event must block with a timeout.'
}
finally {
    $stopEvent.Dispose()
}
$createdNew = $false
$signalEvent = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, ('Local\{0}' -f (Get-GameAudioWatchStopEventName)), [ref]$createdNew)
try {
    [void](Stop-GameAudioWatch)
    Assert-Equal $signalEvent.WaitOne(0) $true 'Stopping must signal the watched stop event.'
}
finally {
    $signalEvent.Dispose()
}
$freshStopEvent = New-GameAudioWatchStopEvent
try {
    Assert-Equal $freshStopEvent.WaitOne(0) $false 'A newly started watcher must consume a stale stop signal.'
}
finally {
    $freshStopEvent.Dispose()
}

# --- watcher status persistence ---
$testDirectory = New-TestDirectory
try {
    $null = New-Item -ItemType Directory -Path $testDirectory -Force
    $statusPath = Join-Path $testDirectory 'watcher-status.json'
    $status = [PSCustomObject]@{
        watcher = [PSCustomObject]@{
            pid = $PID
            startedAt = [DateTime]::UtcNow.ToString('o')
            updatedAt = [DateTime]::UtcNow.ToString('o')
            intervalSeconds = 5
        }
        apps = @([PSCustomObject]@{ name = 'Shiren 6'; processName = 'ShirenTheWanderer6'; enabled = $true; running = $false; destinationDevice = $null; appliedDevice = $null; appliedAt = $null; error = $null })
    }
    Write-GameAudioWatchStatus -Path $statusPath -Status $status
    Assert-True (Test-Path -LiteralPath $statusPath -PathType Leaf) 'Writing a status must create the status file.'

    $loaded = Get-GameAudioWatchStatus -StatusPath $statusPath
    Assert-Equal $loaded.watcher.pid $PID 'Reading a status must expose the watcher pid.'
    Assert-Equal (@($loaded.apps))[0].processName 'ShirenTheWanderer6' 'Reading a status must expose per-app entries.'

    Assert-True (Test-GameAudioWatchRunning -StatusPath $statusPath) 'A fresh status from a living process must report running.'

    # ConvertFrom-Json yields a [DateTime] with Kind=Utc. Casting it to [string]
    # formats it in local time without the offset, so a string round-trip shifted
    # the value by the UTC offset and made a live watcher look stale.
    $timestamp = ConvertTo-GameAudioWatchTimestamp -Value ([DateTime]::UtcNow)
    Assert-True ($null -ne $timestamp) 'A DateTime must convert to a timestamp.'
    $age = ([DateTimeOffset]::UtcNow - $timestamp.ToUniversalTime()).TotalSeconds
    Assert-True ([Math]::Abs($age) -lt 60) "A current UTC DateTime must not shift by the UTC offset. Age was $age seconds."

    $offsetTimestamp = ConvertTo-GameAudioWatchTimestamp -Value ([DateTime]::UtcNow.AddHours(-1))
    $offsetAge = ([DateTimeOffset]::UtcNow - $offsetTimestamp.ToUniversalTime()).TotalSeconds
    Assert-True ($offsetAge -gt 3500 -and $offsetAge -lt 3700) "An hour-old UTC DateTime must read as about an hour old. Age was $offsetAge seconds."

    $stringTimestamp = ConvertTo-GameAudioWatchTimestamp -Value ([DateTime]::UtcNow.ToString('o'))
    $stringAge = ([DateTimeOffset]::UtcNow - $stringTimestamp.ToUniversalTime()).TotalSeconds
    Assert-True ([Math]::Abs($stringAge) -lt 60) "An ISO-8601 string must round-trip without shifting. Age was $stringAge seconds."

    Assert-True ($null -eq (ConvertTo-GameAudioWatchTimestamp -Value $null)) 'A null timestamp must stay null.'
    Assert-True ($null -eq (ConvertTo-GameAudioWatchTimestamp -Value '')) 'An empty timestamp must stay null.'
    Assert-True ((Get-GameAudioWatchStatusPath) -like '*config\watcher-status.json') 'The default status path must resolve into config\watcher-status.json.'

    $stalePath = Join-Path $testDirectory 'stale.json'
    $staleStatus = [PSCustomObject]@{
        watcher = [PSCustomObject]@{
            pid = $PID
            updatedAt = [DateTime]::UtcNow.AddDays(-1).ToString('o')
            intervalSeconds = 5
        }
        apps = @()
    }
    Write-GameAudioWatchStatus -Path $stalePath -Status $staleStatus
    Assert-True (-not (Test-GameAudioWatchRunning -StatusPath $stalePath)) 'A stale status must not report running.'

    $deadPath = Join-Path $testDirectory 'dead.json'
    $deadStatus = [PSCustomObject]@{
        watcher = [PSCustomObject]@{
            pid = -1
            updatedAt = [DateTime]::UtcNow.ToString('o')
            intervalSeconds = 5
        }
        apps = @()
    }
    Write-GameAudioWatchStatus -Path $deadPath -Status $deadStatus
    Assert-True (-not (Test-GameAudioWatchRunning -StatusPath $deadPath)) 'A dead watcher pid must not report running.'
    Assert-True (-not (Test-GameAudioWatchRunning -StatusPath (Join-Path $testDirectory 'missing.json'))) 'A missing status file must not report running.'

    # --- settings persistence ---
    $missingSettings = Get-GameAudioManagerSettings -Path (Join-Path $testDirectory 'settings.json')
    Assert-Equal $missingSettings.WatchIntervalSeconds 5 'Missing settings must default to a 5 second interval.'
    Assert-Equal $missingSettings.AutoStartWatcher $false 'Missing settings must default to manual watch start.'

    $null = Set-GameAudioManagerSettings -Path (Join-Path $testDirectory 'settings.json') -WatchIntervalSeconds 10 -AutoStartWatcher $true
    $savedSettings = Get-GameAudioManagerSettings -Path (Join-Path $testDirectory 'settings.json')
    Assert-Equal $savedSettings.WatchIntervalSeconds 10 'Saved settings must round-trip the interval.'
    Assert-Equal $savedSettings.AutoStartWatcher $true 'Saved settings must round-trip auto start.'
}
finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

# --- multi-game cycle: per-game isolation ---
# Two games must be able to hold different destinations at the same time, and a
# failure or restart for one must not disturb the other.
function New-TestGame {
    param([string]$Name, [string]$ProcessName, [string[]]$OutputDevices, [bool]$Enabled = $true)
    return [PSCustomObject]@{
        Name = $Name
        ProcessName = $ProcessName
        OutputDevices = [string[]]$OutputDevices
        Enabled = $Enabled
    }
}

function New-TestProcess {
    param([int]$Id, [string]$ProcessName)
    return [PSCustomObject]@{
        Id = $Id
        ProcessName = $ProcessName
        StartTime = [DateTime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    }
}

$games = @(
    New-TestGame -Name 'Game A' -ProcessName 'GameA' -OutputDevices @('Device A', 'Device Shared')
    New-TestGame -Name 'Game B' -ProcessName 'GameB' -OutputDevices @('Device B', 'Device Shared')
    New-TestGame -Name 'Disabled' -ProcessName 'GameC' -OutputDevices @('Device A') -Enabled $false
)
$running = @{ GameA = New-TestProcess -Id 101 -ProcessName 'GameA'; GameB = New-TestProcess -Id 202 -ProcessName 'GameB' }
$applied = @{}
$states = @{}

$getProcess = { param($ProcessName) $running[$ProcessName] }
$applyDevice = {
    param($ProcessName, $Device)
    $script:applied[$ProcessName] = $Device
}

$statuses = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices @('Device A', 'Device B', 'Device Shared') -States $states -GetProcess $getProcess -ApplyDevice $applyDevice)
Assert-Equal $statuses.Count 2 'Disabled games must not be monitored.'
Assert-Equal ($statuses.name -join ',') 'Game A,Game B' 'Every enabled game must be reported.'
Assert-Equal $applied['GameA'] 'Device A' 'Game A must receive its own preferred device.'
Assert-Equal $applied['GameB'] 'Device B' 'Game B must receive its own preferred device.'
Assert-Equal $statuses[0].appliedDevice 'Device A' 'Game A status must report its applied device.'
Assert-Equal $statuses[1].appliedDevice 'Device B' 'Game B status must report its applied device.'

# A second cycle with nothing changed must not reapply either game.
$applied = @{}
$null = Invoke-GameAudioWatchCycle -Games $games -ActiveDevices @('Device A', 'Device B', 'Device Shared') -States $states -GetProcess $getProcess -ApplyDevice $applyDevice
Assert-Equal $applied.Count 0 'A stable cycle must not reapply any game.'

# Restarting Game A must reapply only Game A.
$applied = @{}
$running['GameA'] = New-TestProcess -Id 303 -ProcessName 'GameA'
$statuses = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices @('Device A', 'Device B', 'Device Shared') -States $states -GetProcess $getProcess -ApplyDevice $applyDevice)
Assert-Equal $applied.Count 1 'A restart for one game must not reapply the other.'
Assert-Equal $applied['GameA'] 'Device A' 'The restarted game must be reapplied.'
Assert-Equal $statuses[1].appliedDevice 'Device B' 'The untouched game must keep its applied device.'

# A failure for Game B must not clear Game A's applied state.
$applied = @{}
$failingApply = {
    param($ProcessName, $Device)
    if ($ProcessName -eq 'GameB') { throw 'apply failed for GameB' }
    $script:applied[$ProcessName] = $Device
}
$running['GameB'] = New-TestProcess -Id 404 -ProcessName 'GameB'
$statuses = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices @('Device A', 'Device B', 'Device Shared') -States $states -GetProcess $getProcess -ApplyDevice $failingApply)
Assert-Equal $statuses[0].appliedDevice 'Device A' 'A failure in one game must not clear another game''s applied state.'
Assert-True ($statuses[1].error -match 'apply failed for GameB') 'The failing game must report its error.'
Assert-Equal $statuses[1].appliedDevice $null 'The failing game must not report an applied device.'

# A game that is not running must be reported as stopped without failing the cycle.
$running.Remove('GameB')
$statuses = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices @('Device A', 'Device B', 'Device Shared') -States $states -GetProcess $getProcess -ApplyDevice $applyDevice)
Assert-Equal $statuses[0].running $true 'The running game must still be reported as running.'
Assert-Equal $statuses[1].running $false 'The stopped game must be reported as stopped.'
Assert-Equal $statuses[0].appliedDevice 'Device A' 'A stopped game must not disturb the running game.'

# A device disconnect must fall back to the next active candidate per game.
$applied = @{}
$running['GameB'] = New-TestProcess -Id 505 -ProcessName 'GameB'
$statuses = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices @('Device Shared') -States $states -GetProcess $getProcess -ApplyDevice $applyDevice)
Assert-Equal $applied['GameA'] 'Device Shared' 'Game A must fall back to the shared candidate.'
Assert-Equal $applied['GameB'] 'Device Shared' 'Game B must fall back to the shared candidate.'

# A process lookup that throws for one game must not abort the cycle.
$throwingGetProcess = {
    param($ProcessName)
    if ($ProcessName -eq 'GameA') { throw 'lookup failed for GameA' }
    $running[$ProcessName]
}
$statuses = @(Invoke-GameAudioWatchCycle -Games $games -ActiveDevices @('Device A', 'Device B', 'Device Shared') -States $states -GetProcess $throwingGetProcess -ApplyDevice $applyDevice)
Assert-Equal $statuses.Count 2 'A lookup failure for one game must not abort the cycle.'
Assert-True ($statuses[0].error -match 'lookup failed for GameA') 'The failing lookup must be reported.'
Assert-Equal $statuses[1].running $true 'The other game must still be evaluated.'

# --- watchers launched for the GUI ---
$watcherScript = (Resolve-Path (Join-Path $PSScriptRoot '..\watch-game-output.ps1')).Path
Assert-Throws { Start-GameAudioWatchProcess -WatcherScriptPath (Join-Path ([System.IO.Path]::GetTempPath()) 'missing-watcher.ps1') } 'was not found' 'Starting must reject a missing watcher script.'

Write-Host 'PASS: game-audio-watch tests'
