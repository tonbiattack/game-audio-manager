$ErrorActionPreference = 'Stop'

$library = Join-Path $PSScriptRoot '..\lib\GameAudio.Mute.ps1'
$script = Join-Path $PSScriptRoot '..\toggle-game-mute.ps1'
if (-not (Test-Path -LiteralPath $library)) { throw 'Game audio mute library is missing.' }
if (-not (Test-Path -LiteralPath $script)) { throw 'Generic mute command is missing.' }
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
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($ExpectedText)) {
            throw "$Message Actual: $($_.Exception.Message)"
        }
        return
    }
    throw "$Message No exception was raised."
}

function New-Session {
    param([int]$ProcessId, [string]$DeviceId, [string]$DeviceName, [bool]$Muted)
    return [PSCustomObject]@{
        ProcessId = $ProcessId
        ProcessName = 'ExampleGame'
        DeviceId = $DeviceId
        DeviceName = $DeviceName
        Muted = $Muted
        IsSystemSounds = $false
    }
}

# --- mixed-state rule ---
# A toggle unmutes only when every session is already muted. Any unmuted session
# (including a mixed set) means the toggle mutes them all, so the target always
# ends in one consistent state.
$allUnmuted = @(
    New-Session -ProcessId 1 -DeviceId 'dev-a' -DeviceName 'Device A' -Muted $false
    New-Session -ProcessId 2 -DeviceId 'dev-b' -DeviceName 'Device B' -Muted $false
)
Assert-Equal (Get-GameAudioMuteTargetState -Sessions $allUnmuted) $true 'All-unmuted sessions must be muted.'

$allMuted = @(
    New-Session -ProcessId 1 -DeviceId 'dev-a' -DeviceName 'Device A' -Muted $true
    New-Session -ProcessId 2 -DeviceId 'dev-b' -DeviceName 'Device B' -Muted $true
)
Assert-Equal (Get-GameAudioMuteTargetState -Sessions $allMuted) $false 'All-muted sessions must be unmuted.'

$mixed = @(
    New-Session -ProcessId 1 -DeviceId 'dev-a' -DeviceName 'Device A' -Muted $true
    New-Session -ProcessId 2 -DeviceId 'dev-b' -DeviceName 'Device B' -Muted $false
)
Assert-Equal (Get-GameAudioMuteTargetState -Sessions $mixed) $true 'A mixed set must be normalized to muted.'

$single = @(New-Session -ProcessId 1 -DeviceId 'dev-a' -DeviceName 'Device A' -Muted $false)
Assert-Equal (Get-GameAudioMuteTargetState -Sessions $single) $true 'A single unmuted session must be muted.'

Assert-Throws { Get-GameAudioMuteTargetState -Sessions @() } 'No audio sessions' 'An empty session set must be rejected.'

# --- summary formatting ---
$summary = @(Format-GameAudioSessionSummary -Sessions @(
    New-Session -ProcessId 7 -DeviceId 'dev-a' -DeviceName 'Device A' -Muted $true
    New-Session -ProcessId 8 -DeviceId 'dev-b' -DeviceName '' -Muted $false
))
Assert-Equal $summary.Count 2 'Every session must appear in the summary.'
Assert-Equal $summary[0].ProcessId 7 'The summary must carry the session PID.'
Assert-Equal $summary[0].Device 'Device A' 'The summary must prefer the friendly device name.'
Assert-Equal $summary[1].Device 'dev-b' 'The summary must fall back to the device id when no name is available.'
Assert-Equal $summary[0].Muted $true 'The summary must carry the mute state.'

# --- the command must consider every PID, not just the first ---
$source = Get-Content -Raw -LiteralPath $script
if ($source -match [regex]::Escape('Resolve-GameProcess')) {
    throw 'The mute command must not resolve a single PID; a game can own its session from another PID.'
}
if ($source -notmatch [regex]::Escape('Get-GameAudioSessionInfo')) {
    throw 'The mute command must enumerate audio sessions across endpoints.'
}
if ($source -notmatch [regex]::Escape('Get-GameProcesses')) {
    throw 'The mute command must still require the process to be running.'
}

# --- the interop must enumerate all render endpoints, not only the default ---
$interopSource = Get-Content -Raw -LiteralPath $library
if ($interopSource -notmatch [regex]::Escape('EnumAudioEndpoints')) {
    throw 'The interop must enumerate render endpoints.'
}
if ($interopSource -match [regex]::Escape('GetDefaultAudioEndpoint(EDataFlow.eRender')) {
    throw 'The interop must not restrict itself to the default render endpoint.'
}
if ($interopSource -notmatch [regex]::Escape('GetProcessId')) {
    throw 'The interop must read each session process id.'
}
# IAudioSessionControl2 inherits IAudioSessionControl, so the inherited slots must
# be declared before GetProcessId or the vtable offset is wrong.
$control2 = [regex]::Match($interopSource, '(?s)interface IAudioSessionControl2\s*\{(.*?)\n    \}')
if (-not $control2.Success) { throw 'IAudioSessionControl2 must be declared.' }
$control2Body = $control2.Groups[1].Value
$getProcessIdIndex = $control2Body.IndexOf('GetProcessId')
$getStateIndex = $control2Body.IndexOf('GetState')
if ($getStateIndex -lt 0 -or $getProcessIdIndex -lt 0 -or $getStateIndex -gt $getProcessIdIndex) {
    throw 'IAudioSessionControl2 must declare the inherited IAudioSessionControl methods before GetProcessId.'
}

Write-Host 'PASS: toggle-game-mute tests'
