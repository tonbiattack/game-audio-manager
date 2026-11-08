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

Write-Host 'PASS: game-audio-gui tests'
