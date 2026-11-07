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

$guiSource = Get-Content -LiteralPath $guiScript -Raw
if ($guiSource -match '(?s)\$selectedButton\.add_Click\(\{.*?Invoke-GameOutputChange -GameName') {
    throw 'Selected-device apply must route through ProcessName, not GameName.'
}
if ($guiSource -notmatch '(?s)\$selectedButton\.add_Click\(\{.*?Invoke-GameOutputChange -ProcessName \$request\.ProcessName') {
    throw 'Selected-device apply must pass the request ProcessName.'
}

Write-Host 'PASS: game-audio-gui tests'
