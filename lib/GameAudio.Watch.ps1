Set-StrictMode -Version Latest

function New-GameAudioWatchState {
    return @{
        Process = $null
        DeviceAvailable = $false
        Destination = $null
        Applied = $false
        AppliedDevice = $null
        AppliedAt = $null
        LastError = $null
    }
}

function Update-GameAudioWatchState {
    param($State, $ProcessIdentity, [string]$Destination, [scriptblock]$Apply)

    $deviceAvailable = -not [string]::IsNullOrEmpty($Destination)
    if ($State.Process -ne $ProcessIdentity -or -not $deviceAvailable -or -not $State.DeviceAvailable -or $State.Destination -ne $Destination) {
        $State.Applied = $false
    }
    $State.Process = $ProcessIdentity
    $State.DeviceAvailable = $deviceAvailable
    $State.Destination = $Destination
    if ($null -ne $ProcessIdentity -and $deviceAvailable -and -not $State.Applied) {
        if (& $Apply $Destination $State) {
            $State.Applied = $true
            $State.AppliedDevice = $Destination
            $State.AppliedAt = [DateTime]::UtcNow.ToString('o')
        }
    }
}

function Enter-GameAudioWatchMutex {
    param([Parameter(Mandatory = $true)][string]$Name)

    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new($false, "Local\$Name", [ref]$createdNew)
    if (-not $createdNew -or -not $mutex.WaitOne(0)) {
        $mutex.Dispose()
        return $null
    }
    return $mutex
}

function Get-GameAudioWatchStopEventName {
    return 'game-audio-output-watch-stop'
}

function New-GameAudioWatchStopEvent {
    $createdNew = $false
    $name = Get-GameAudioWatchStopEventName
    $stopEvent = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, "Local\$name", [ref]$createdNew)
    # A stale signal left by a previous stop must not end the new watcher immediately.
    $null = $stopEvent.Reset()
    return $stopEvent
}

function Stop-GameAudioWatch {
    $createdNew = $false
    $name = Get-GameAudioWatchStopEventName
    $stopEvent = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, "Local\$name", [ref]$createdNew)
    try {
        return [bool]$stopEvent.Set()
    }
    finally {
        $stopEvent.Dispose()
    }
}

function Get-GameAudioWatchStatusPath {
    param([string]$StatusPath)

    if ([string]::IsNullOrWhiteSpace($StatusPath)) {
        return (Join-Path $PSScriptRoot '..\config\watcher-status.json')
    }
    return $StatusPath
}

function Write-GameAudioWatchStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Status
    )

    $json = $Status | ConvertTo-Json -Depth 6
    $temporaryPath = "$Path.tmp"
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-GameAudioWatchStatus {
    param([string]$StatusPath)

    $path = Get-GameAudioWatchStatusPath -StatusPath $StatusPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Test-GameAudioWatchRunning {
    param([string]$StatusPath)

    $status = Get-GameAudioWatchStatus -StatusPath $StatusPath
    if ($null -eq $status -or $null -eq $status.watcher) { return $false }
    try {
        $interval = [int]$status.watcher.intervalSeconds
        if ($interval -lt 1) { $interval = 5 }
        $updatedAt = [DateTimeOffset]::Parse([string]$status.watcher.updatedAt, [System.Globalization.CultureInfo]::InvariantCulture)
        $age = [DateTimeOffset]::UtcNow - $updatedAt.ToUniversalTime()
        if ($age.TotalSeconds -gt (($interval * 2) + 15)) { return $false }
        $watcherPid = [int]$status.watcher.pid
        if ($null -eq (Get-Process -Id $watcherPid -ErrorAction SilentlyContinue)) { return $false }
        return $true
    }
    catch {
        return $false
    }
}

function Start-GameAudioWatchProcess {
    param(
        [Parameter(Mandatory = $true)][string]$WatcherScriptPath,
        [string]$ConfigPath,
        [int]$IntervalSeconds = 5
    )

    if (-not (Test-Path -LiteralPath $WatcherScriptPath -PathType Leaf)) {
        throw "Watcher script was not found: $WatcherScriptPath"
    }
    $interval = [Math]::Max(1, [Math]::Min(3600, $IntervalSeconds))
    $hostExecutablePath = (Get-Process -Id $PID).Path
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -IntervalSeconds {1}' -f $WatcherScriptPath, $interval
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $arguments += (' -ConfigPath "{0}"' -f $ConfigPath) }
    Start-Process -FilePath $hostExecutablePath -ArgumentList $arguments -WindowStyle Hidden | Out-Null
    return $true
}

function Get-GameAudioManagerSettingsPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Join-Path $PSScriptRoot '..\config\settings.json')
    }
    return $Path
}

function Get-GameAudioManagerSettings {
    param([string]$Path)

    $path = Get-GameAudioManagerSettingsPath -Path $Path
    $settings = [PSCustomObject]@{
        WatchIntervalSeconds = 5
        AutoStartWatcher = $false
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $settings }
    try {
        $loaded = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $loaded) {
            if ($null -ne $loaded.watchIntervalSeconds) {
                $settings.WatchIntervalSeconds = [Math]::Max(1, [Math]::Min(3600, [int]$loaded.watchIntervalSeconds))
            }
            if ($null -ne $loaded.autoStartWatcher) {
                $settings.AutoStartWatcher = [bool]$loaded.autoStartWatcher
            }
        }
    }
    catch {
        # Unusable settings fall back to defaults; the GUI can recover by saving new values.
    }
    return $settings
}

function Set-GameAudioManagerSettings {
    param(
        [string]$Path,
        [Parameter(Mandatory = $true)][ValidateRange(1, 3600)][int]$WatchIntervalSeconds,
        [Parameter(Mandatory = $true)][bool]$AutoStartWatcher
    )

    $path = Get-GameAudioManagerSettingsPath -Path $Path
    $settings = [PSCustomObject]@{
        watchIntervalSeconds = [Math]::Max(1, [Math]::Min(3600, $WatchIntervalSeconds))
        autoStartWatcher = $AutoStartWatcher
    }
    $json = $settings | ConvertTo-Json
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    return $settings
}
