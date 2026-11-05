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

Write-Host 'PASS: game-audio-config tests'
