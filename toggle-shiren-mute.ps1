param(
    [string]$ProcessName = 'ShirenTheWanderer6'
)

& "$PSScriptRoot\toggle-game-mute.ps1" -ProcessName $ProcessName
exit $LASTEXITCODE

