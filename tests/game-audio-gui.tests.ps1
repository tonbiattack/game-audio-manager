$ErrorActionPreference = 'Stop'

$library = Join-Path $PSScriptRoot '..\lib\GameAudio.Gui.ps1'
$guiScript = Join-Path $PSScriptRoot '..\game-audio-manager.ps1'
if (-not (Test-Path -LiteralPath $library)) { throw 'Game-audio GUI library is missing.' }
if (-not (Test-Path -LiteralPath $guiScript)) { throw 'Game-audio GUI script is missing.' }
. $library

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$ExpectedText)
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch [regex]::Escape($ExpectedText)) { throw "Expected '$ExpectedText', got '$($_.Exception.Message)'" }
        return
    }
    throw "Expected an error containing '$ExpectedText'."
}

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}

$games = @(
    [PSCustomObject]@{ Name = 'Running'; ProcessName = 'RunningGame'; OutputDevices = @('First', 'Second'); Enabled = $true },
    [PSCustomObject]@{ Name = 'Stopped'; ProcessName = 'StoppedGame'; OutputDevices = @('Second'); Enabled = $true },
    [PSCustomObject]@{ Name = 'Disabled'; ProcessName = 'DisabledGame'; OutputDevices = @('First'); Enabled = $false }
)

$state = @(Get-GameAudioGuiState -Games $games -ActiveDevices @('Second', 'Other') -RunningProcessNames @('RunningGame'))
Assert-Equal ($state.Name -join ',') 'Running,Stopped' 'Disabled games must not be selectable.'
Assert-Equal $state[0].IsRunning $true 'The running game must be identified.'
Assert-Equal $state[0].PreferredDevice 'Second' 'The first active configured device must be selected.'
Assert-Equal $state[1].IsRunning $false 'A stopped game must be identified.'

$request = New-GameAudioApplyRequest -Game $state[0] -ActiveDevices @('Second', 'Other') -UsePreferred
Assert-Equal $request.Device 'Second' 'Preferred apply must select the active preferred device.'
$manual = New-GameAudioApplyRequest -Game $state[0] -ActiveDevices @('Second', 'Other') -SelectedDevice 'Other'
Assert-Equal $manual.Device 'Other' 'Manual apply must keep a selected active device.'
Assert-Throws { New-GameAudioApplyRequest -Game $state[1] -ActiveDevices @('Second') -UsePreferred } 'not running'
Assert-Throws { New-GameAudioApplyRequest -Game $state[0] -ActiveDevices @('Second') -SelectedDevice 'Missing' } 'not active'

$discovered = @(Get-DiscoveredGameAudioApplications -Processes @(
    [PSCustomObject]@{ ProcessName = 'RunningGame'; MainWindowHandle = [intptr]1 },
    [PSCustomObject]@{ ProcessName = 'DisabledGame'; MainWindowHandle = [intptr]1 },
    [PSCustomObject]@{ ProcessName = 'UnconfiguredApp'; MainWindowHandle = [intptr]1 },
    [PSCustomObject]@{ ProcessName = 'BackgroundApp'; MainWindowHandle = [intptr]0 }
) -ConfiguredGames $games)
Assert-Equal ($discovered.ProcessName -join ',') 'UnconfiguredApp' 'Configured processes, including disabled games, must not be rediscovered.'

$guiSource = Get-Content -LiteralPath $guiScript -Raw
if ($guiSource -match '(?s)\$selectedButton\.add_Click\(\{.*?Invoke-GameOutputChange -GameName') {
    throw 'Selected-device apply must route through ProcessName, not GameName.'
}
if ($guiSource -notmatch '(?s)\$selectedButton\.add_Click\(\{.*?Invoke-GameOutputChange -ProcessName \$request\.ProcessName') {
    throw 'Selected-device apply must pass the request ProcessName.'
}

$watchStatus = [PSCustomObject]@{
    watcher = [PSCustomObject]@{ pid = 1234; intervalSeconds = 5 }
    apps = @(
        [PSCustomObject]@{ name = 'Shiren 6'; processName = 'ShirenTheWanderer6'; enabled = $true; running = $true; destinationDevice = 'Device A'; appliedDevice = 'Device A'; appliedAt = '2026-11-07T00:00:00.0000000Z'; error = $null },
        [PSCustomObject]@{ name = 'Balatro'; processName = 'Balatro'; enabled = $true; running = $false; destinationDevice = $null; appliedDevice = $null; appliedAt = $null; error = 'svcl.exe exit code 1' }
    )
}
$watchText = Format-GameAudioWatchStatusText -Status $watchStatus -Running $true
Assert-True ($watchText.Contains('PID 1234, 5秒間隔')) 'Running text must show the watcher pid and interval.'
Assert-True ($watchText.Contains('Shiren 6: Device A に適用済み')) 'Running text must show the applied device.'
Assert-True ($watchText.Contains('Balatro: 未起動 (エラー: svcl.exe exit code 1)')) 'Running text must show per-app status and errors.'

$emptyWatchText = Format-GameAudioWatchStatusText -Status ([PSCustomObject]@{ watcher = [PSCustomObject]@{ pid = 1; intervalSeconds = 5 }; apps = @() }) -Running $true
Assert-True ($emptyWatchText.Contains('監視対象のゲームはありません')) 'Running text must explain an empty rule set.'
Assert-Equal (Format-GameAudioWatchStatusText -Status $null -Running $false) '監視: 停止中 (GUI を閉じても監視は継続します)' 'Stopped text must reassure that the watcher outlives the GUI.'
Assert-Equal (Format-GameAudioWatchStatusText -Status $null -Running $true) '監視: 停止中 (GUI を閉じても監視は継続します)' 'A missing status file must fall back to the stopped text instead of erroring.'

$request = ConvertTo-GameAudioRuleRequest -Game ([PSCustomObject]@{ Name = 'New App'; ProcessName = 'NewApp'; OutputDevices = @() }) -SelectedDevice 'Device A'
Assert-Equal $request.ProcessName 'NewApp' 'A rule request must carry the process name.'
Assert-Equal $request.Device 'Device A' 'A rule request must carry the selected device.'
Assert-Equal $request.HasRule $false 'An app without devices must be reported as unregistered.'
Assert-Throws { ConvertTo-GameAudioRuleRequest -Game ([PSCustomObject]@{ Name = 'New App'; ProcessName = 'NewApp'; OutputDevices = @() }) } 'Select an output device' 'Registering a new app without a device must be rejected.'
$existing = ConvertTo-GameAudioRuleRequest -Game ([PSCustomObject]@{ Name = 'Shiren 6'; ProcessName = 'ShirenTheWanderer6'; OutputDevices = @('Device A') })
Assert-Equal $existing.HasRule $true 'An app with devices must be reported as registered.'

# --- mute state for the GUI ---
function New-MuteSession {
    param([int]$ProcessId, [string]$DeviceId, [bool]$Muted)
    return [PSCustomObject]@{
        ProcessId = $ProcessId
        ProcessName = 'ExampleGame'
        DeviceId = $DeviceId
        DeviceName = $DeviceId
        Muted = $Muted
        IsSystemSounds = $false
    }
}

# An application that has not played audio yet has no session. That is a normal
# state: the GUI disables the button and explains it instead of failing.
$noSession = Get-GameAudioMuteState -Sessions @()
Assert-Equal $noSession.HasSession $false 'An empty session set must report no session.'
Assert-Equal $noSession.SessionCount 0 'An empty session set must report zero sessions.'
Assert-True ($noSession.Text -match '音声セッションなし') 'A missing session must be explained in the status text.'
Assert-Equal (Format-GameAudioMuteButtonText -State $noSession) 'ミュート切替' 'A missing session must keep the neutral button label.'

$unmuted = Get-GameAudioMuteState -Sessions @(
    New-MuteSession -ProcessId 1 -DeviceId 'Device A' -Muted $false
    New-MuteSession -ProcessId 1 -DeviceId 'Device B' -Muted $false
)
Assert-Equal $unmuted.HasSession $true 'Sessions must be reported as present.'
Assert-Equal $unmuted.IsMuted $false 'All-unmuted sessions must report unmuted.'
Assert-Equal $unmuted.IsMixed $false 'All-unmuted sessions must not report mixed.'
Assert-Equal $unmuted.SessionCount 2 'The session count must be reported.'
Assert-Equal $unmuted.EndpointCount 2 'The endpoint count must be reported.'
Assert-True ($unmuted.Text -match '解除') 'Unmuted sessions must be described as unmuted.'
Assert-Equal (Format-GameAudioMuteButtonText -State $unmuted) 'ミュートする' 'The button must offer to mute when unmuted.'

$muted = Get-GameAudioMuteState -Sessions @(
    New-MuteSession -ProcessId 1 -DeviceId 'Device A' -Muted $true
    New-MuteSession -ProcessId 1 -DeviceId 'Device B' -Muted $true
)
Assert-Equal $muted.IsMuted $true 'All-muted sessions must report muted.'
Assert-Equal $muted.IsMixed $false 'All-muted sessions must not report mixed.'
Assert-True ($muted.Text -match 'ミュート中') 'Muted sessions must be described as muted.'
Assert-Equal (Format-GameAudioMuteButtonText -State $muted) 'ミュートを解除' 'The button must offer to unmute when muted.'

$mixed = Get-GameAudioMuteState -Sessions @(
    New-MuteSession -ProcessId 1 -DeviceId 'Device A' -Muted $true
    New-MuteSession -ProcessId 1 -DeviceId 'Device B' -Muted $false
)
Assert-Equal $mixed.IsMuted $false 'A mixed set must not report fully muted.'
Assert-Equal $mixed.IsMixed $true 'A mixed set must report mixed.'
Assert-True ($mixed.Text -match '混在') 'A mixed set must be described as mixed.'
Assert-Equal (Format-GameAudioMuteButtonText -State $mixed) 'ミュートする' 'A mixed set must offer to mute, matching the CLI rule.'

# The GUI must reuse the CLI mute rules rather than reimplementing them.
$guiSource = Get-Content -LiteralPath $guiScript -Raw
if ($guiSource -notmatch [regex]::Escape('lib\GameAudio.Mute.ps1')) {
    throw 'The GUI must load the mute library.'
}
if ($guiSource -notmatch [regex]::Escape('Get-GameAudioMuteTargetState')) {
    throw 'The GUI must reuse the CLI mixed-state rule.'
}
if ($guiSource -notmatch [regex]::Escape('Set-GameAudioSessionMute')) {
    throw 'The GUI must apply mute through the shared mute library.'
}
if ($guiSource -notmatch [regex]::Escape('$muteButton.add_Click')) {
    throw 'The GUI must wire a mute button click handler.'
}
if ($guiSource -notmatch [regex]::Escape('$muteButton.Enabled = $script:muteState.HasSession')) {
    throw 'The GUI must disable the mute button when no audio session exists.'
}

# --- priority device editor ---
$rows = @(Format-GameAudioPriorityDeviceList -Devices @('Device A', 'Device B') -ActiveDevices @('Device A'))
Assert-Equal $rows.Count 2 'Every candidate must be listed.'
Assert-Equal $rows[0].Priority 1 'The first candidate must be priority 1.'
Assert-Equal $rows[1].Priority 2 'The second candidate must be priority 2.'
Assert-Equal $rows[0].Device 'Device A' 'The row must carry the device name.'
Assert-Equal $rows[0].IsActive $true 'A connected device must be marked active.'
Assert-Equal $rows[1].IsActive $false 'A disconnected device must not be marked active.'
Assert-True ($rows[0].Display -match '^1\. Device A') 'The display text must show the priority.'
Assert-True ($rows[1].Display -match '未接続') 'A disconnected candidate must be labelled so the order is still editable.'

$emptyRows = @(Format-GameAudioPriorityDeviceList -Devices @() -ActiveDevices @('Device A'))
Assert-Equal $emptyRows.Count 0 'An empty candidate list must produce no rows.'

# The editor list is authoritative when it has entries; otherwise the selected
# device is used so the original "pick a device and register" flow still works.
Assert-Equal ((Resolve-GameAudioPrioritySaveList -Devices @('X', 'Y') -SelectedDevice 'Z') -join ',') 'X,Y' 'The edited list must win over the selected device.'
Assert-Equal ((Resolve-GameAudioPrioritySaveList -Devices @() -SelectedDevice 'Z') -join ',') 'Z' 'An empty list must fall back to the selected device.'
Assert-Equal ((Resolve-GameAudioPrioritySaveList -Devices @() -SelectedDevice '  Z  ') -join ',') 'Z' 'The fallback must trim whitespace.'
Assert-Throws { Resolve-GameAudioPrioritySaveList -Devices @() -SelectedDevice '' } 'Add at least one output device' 'Saving with no devices must be rejected.'

# The GUI must wire the editor controls and save through -ReplaceDevices.
$guiSource = Get-Content -LiteralPath $guiScript -Raw
foreach ($control in @('$priorityList', '$priorityAddButton', '$priorityRemoveButton', '$priorityUpButton', '$priorityDownButton')) {
    if ($guiSource -notmatch [regex]::Escape($control)) {
        throw "The GUI must define the priority editor control $control."
    }
}
if ($guiSource -notmatch [regex]::Escape('-ReplaceDevices')) {
    throw 'The GUI must save the edited order with -ReplaceDevices.'
}
if ($guiSource -notmatch [regex]::Escape('Resolve-GameAudioPrioritySaveList')) {
    throw 'The GUI must resolve the save list through the shared helper.'
}

Write-Host 'PASS: game-audio-gui tests'
