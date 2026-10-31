$ErrorActionPreference = 'Stop'

$genericScript = Join-Path $PSScriptRoot '..\set-game-output.ps1'
$shirenWrapper = Join-Path $PSScriptRoot '..\set-shiren-output.ps1'
if (-not (Test-Path -LiteralPath $genericScript)) { throw 'Generic output command is missing.' }

$genericSource = Get-Content -Raw -LiteralPath $genericScript
$wrapperSource = Get-Content -Raw -LiteralPath $shirenWrapper

if ($genericSource -match 'Shiren|シレン') {
    throw 'The generic output command must not contain Shiren-specific text.'
}
if ($genericSource -notmatch [regex]::Escape('$exeName')) {
    throw 'The generic output command must derive the executable name from the resolved game process.'
}
if ($wrapperSource -notmatch [regex]::Escape('ShirenTheWanderer6')) {
    throw 'The Shiren wrapper must retain its default process name.'
}
if ($wrapperSource -notmatch [regex]::Escape('set-game-output.ps1')) {
    throw 'The Shiren wrapper must delegate to the generic output command.'
}

$output = @()
$exitCode = 0
try {
    $output = @(& $genericScript -ProcessName 'DefinitelyMissingGame' -Device 'Example device' 2>&1)
    $exitCode = $LASTEXITCODE
}
catch {
    $output += $_
    $exitCode = 1
}
$text = $output -join [Environment]::NewLine
if ($exitCode -eq 0 -or $text -notmatch [regex]::Escape('DefinitelyMissingGame')) {
    throw "A missing generic process must produce an identifying error. Actual: $text"
}
if ($text -match 'Shiren|シレン') {
    throw "The generic missing-process error must be game-neutral. Actual: $text"
}

Write-Host 'PASS: set-game-output tests'
