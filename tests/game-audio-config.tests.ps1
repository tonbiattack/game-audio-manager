$ErrorActionPreference = 'Stop'

$library = Join-Path $PSScriptRoot '..\lib\GameAudio.Config.ps1'
$example = Join-Path $PSScriptRoot '..\config\games.example.json'
if (-not (Test-Path -LiteralPath $library)) { throw 'Game configuration library is missing.' }
if (-not (Test-Path -LiteralPath $example)) { throw 'Example game configuration is missing.' }
. $library

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
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

function New-TestConfigFile {
    param([string]$Json)
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("game-audio-config-{0}.json" -f [guid]::NewGuid())
    [System.IO.File]::WriteAllText($path, $Json, [System.Text.Encoding]::UTF8)
    return $path
}

$games = @(Get-GameConfiguration -Path $example)
Assert-Equal ($games.Name -join ',') 'Shiren 6,Slay the Spire 2,Balatro' 'The example must define the supported games.'
Assert-Equal (Resolve-ConfiguredGame -Games $games -GameName 'Balatro').ProcessName 'Balatro' 'Games must resolve by display name.'
Assert-Equal (Get-PreferredConfiguredDevice -Candidates @('A', 'B', 'C') -ActiveDevices @('C', 'B')) 'B' 'The first active configured candidate must win.'

$duplicateName = New-TestConfigFile '{"games":[{"name":"Same","processName":"One","outputDevices":["Device"],"enabled":true},{"name":"Same","processName":"Two","outputDevices":["Device"],"enabled":true}]}'
$emptyCandidates = New-TestConfigFile '{"games":[{"name":"Game","processName":"Game","outputDevices":[],"enabled":true}]}'
$stringCandidates = New-TestConfigFile '{"games":[{"name":"Game","processName":"Game","outputDevices":"Device","enabled":true}]}'
$invalidEnabled = New-TestConfigFile '{"games":[{"name":"Game","processName":"Game","outputDevices":["Device"],"enabled":"true"}]}'

try {
    Assert-Throws { Get-GameConfiguration -Path $duplicateName } 'duplicate game name' 'Duplicate names must be rejected.'
    Assert-Throws { Get-GameConfiguration -Path $emptyCandidates } 'outputDevices' 'Empty device candidates must be rejected.'
    Assert-Throws { Get-GameConfiguration -Path $stringCandidates } 'array' 'A single device string must be rejected.'
    Assert-Throws { Get-GameConfiguration -Path $invalidEnabled } 'enabled' 'A non-boolean enabled value must be rejected.'
}
finally {
    Remove-Item -LiteralPath $duplicateName,$emptyCandidates,$stringCandidates,$invalidEnabled -Force -ErrorAction SilentlyContinue
}

# --- GUI rule persistence ---
$rulesDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("game-audio-rules-{0}" -f [guid]::NewGuid())
try {
    $null = New-Item -ItemType Directory -Path $rulesDirectory -Force
    $rulesPath = Join-Path $rulesDirectory 'games.json'

    $rule = Set-GameAudioRule -Path $rulesPath -ProcessName 'ShirenTheWanderer6.exe' -OutputDevices @('4- HD Audio Driver for Display Audio')
    Assert-Equal $rule.processName 'ShirenTheWanderer6' 'Registering must strip the exe extension from the process name.'
    Assert-Equal $rule.name 'ShirenTheWanderer6' 'A new rule without a display name must use the process name.'
    Assert-Equal (@($rule.outputDevices))[0] '4- HD Audio Driver for Display Audio' 'A new rule must store the selected device.'

    $stored = @(Get-GameConfiguration -Path $rulesPath)
    Assert-Equal $stored.Count 1 'Registering into a missing file must create the configuration.'
    Assert-Equal $stored[0].ProcessName 'ShirenTheWanderer6' 'The created configuration must be readable by Get-GameConfiguration.'

    $updated = Set-GameAudioRule -Path $rulesPath -ProcessName 'ShirenTheWanderer6.exe' -Name 'Shiren 6' -OutputDevices @('4- USB Audio Device')
    Assert-Equal $updated.name 'Shiren 6' 'Registering with a display name must rename the rule.'
    Assert-Equal (@($updated.outputDevices) -join ',') '4- USB Audio Device,4- HD Audio Driver for Display Audio' 'An update must move the selected device first and keep existing devices.'
    Assert-Equal @(Get-GameConfiguration -Path $rulesPath).Count 1 'An update must not duplicate the rule.'

    Set-GameAudioRule -Path $rulesPath -ProcessName 'Balatro' -OutputDevices @('Speakers') -Enabled $false | Out-Null
    $disabled = @(Get-GameConfiguration -Path $rulesPath | Where-Object { $_.ProcessName -eq 'Balatro' })
    Assert-Equal $disabled.Count 1 'A second rule must be appended to the configuration.'
    Assert-Equal $disabled[0].Enabled $false 'Registering must persist the enabled value.'

    Assert-Throws { Set-GameAudioRule -Path $rulesPath -ProcessName 'NoDeviceApp' } 'at least one output device' 'A new rule without devices must be rejected.'

    $remaining = @(Remove-GameAudioRule -Path $rulesPath -ProcessName 'ShirenTheWanderer6')
    Assert-Equal $remaining.Count 1 'Removing a rule must keep the other rules.'
    Assert-Throws { Remove-GameAudioRule -Path $rulesPath -ProcessName 'MissingGame' } 'was not found' 'Removing an unknown rule must be rejected.'

    $last = @(Remove-GameAudioRule -Path $rulesPath -ProcessName 'Balatro')
    Assert-Equal $last.Count 0 'Removing the last rule must leave an empty configuration.'
    Assert-Equal @(Get-GameConfiguration -Path $rulesPath).Count 0 'An empty configuration must stay readable.'
}
finally {
    Remove-Item -LiteralPath $rulesDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: game-audio-config tests'
