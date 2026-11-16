param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName,
    [switch]$Status
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\GameAudio.Common.ps1"
. "$PSScriptRoot\lib\GameAudio.Mute.ps1"

$name = ConvertTo-GameProcessName -ProcessName $ProcessName

# The process must exist, but every PID under that name is considered: a game
# can own its audio session from a child process rather than the first PID.
$processes = @(Get-GameProcesses -ProcessName $name)
if ($processes.Count -eq 0) {
    throw "Game process '$name' was not found. Start the game first, then run .\detect-game-process.ps1 -ProcessName '$name' to diagnose."
}

$sessions = @(Get-GameAudioSessionInfo -ProcessName $name)
foreach ($errorMessage in @(Get-GameAudioMuteInteropErrors)) {
    Write-Warning "Could not inspect an audio endpoint: $errorMessage"
}

if ($sessions.Count -eq 0) {
    throw "No audio session was found for '$name'. The application may not be playing audio yet, or it may render through a process with a different name."
}

if ($Status) {
    Format-GameAudioSessionSummary -Sessions $sessions | Format-Table -AutoSize | Out-String -Width 4096 | Write-Output
    exit 0
}

$targetMute = Get-GameAudioMuteTargetState -Sessions $sessions
$changed = Set-GameAudioSessionMute -ProcessName $name -Mute $targetMute

if ($changed -eq 0) {
    throw "Audio sessions for '$name' were found but none could be changed."
}

$state = if ($targetMute) { 'MUTE' } else { 'UNMUTE' }
Write-Host "${name}: $state ($changed session(s) across $(@($sessions | ForEach-Object { $_.DeviceId } | Sort-Object -Unique).Count) endpoint(s))"
