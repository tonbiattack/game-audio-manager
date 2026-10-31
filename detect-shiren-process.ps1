param(
    [string]$ProcessName = 'ShirenTheWanderer6'
)

& "$PSScriptRoot\detect-game-process.ps1" -ProcessName $ProcessName
exit $LASTEXITCODE
