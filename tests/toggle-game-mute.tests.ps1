$ErrorActionPreference = 'Stop'

$genericScript = Join-Path $PSScriptRoot '..\toggle-game-mute.ps1'
$shirenWrapper = Join-Path $PSScriptRoot '..\toggle-shiren-mute.ps1'
if (-not (Test-Path -LiteralPath $genericScript)) { throw 'Generic mute command is missing.' }

$genericSource = Get-Content -Raw -LiteralPath $genericScript
$wrapperSource = Get-Content -Raw -LiteralPath $shirenWrapper

if ($genericSource -notmatch 'Mandatory\s*=\s*\$true') {
    throw 'The generic mute command must require -ProcessName.'
}
if ($genericSource -match 'Shiren|シレン') {
    throw 'The generic mute command must not contain game-specific text.'
}
if ($genericSource -notmatch [regex]::Escape('Resolve-GameProcess')) {
    throw 'The generic mute command must use the shared process resolver.'
}
if ($wrapperSource -notmatch [regex]::Escape('ShirenTheWanderer6')) {
    throw 'The Shiren mute wrapper must retain its default process name.'
}
if ($wrapperSource -notmatch [regex]::Escape('toggle-game-mute.ps1')) {
    throw 'The Shiren mute wrapper must delegate to the generic mute command.'
}

Write-Host 'PASS: toggle-game-mute tests'
