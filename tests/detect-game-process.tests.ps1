$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\detect-game-process.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) { throw 'Generic process-detection command is missing.' }

$output = @(& $scriptPath -ProcessName 'DefinitelyMissingGame' 2>&1)
$exitCode = $LASTEXITCODE
$text = $output -join [Environment]::NewLine

if ($exitCode -eq 0) {
    throw 'A missing game process must return a non-zero exit code.'
}
if ($text -notmatch [regex]::Escape('DefinitelyMissingGame')) {
    throw "The diagnostic must identify the requested process. Actual: $text"
}
if ($text -match 'Shiren|シレン') {
    throw "The generic diagnostic must not mention a specific game. Actual: $text"
}

Write-Host 'PASS: detect-game-process tests'
