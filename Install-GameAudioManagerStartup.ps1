param(
    [string]$StartupDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup),
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\GameAudio.Startup.ps1"

if ($Remove) {
    if (Remove-GameAudioStartupShortcut -StartupDirectory $StartupDirectory) {
        Write-Host 'Removed Game Audio Manager from Startup.'
    }
    else {
        Write-Host 'Game Audio Manager was not registered in Startup.'
    }
    exit 0
}

$shortcut = Set-GameAudioStartupShortcut -RepositoryPath $PSScriptRoot -StartupDirectory $StartupDirectory
Write-Host "Registered Game Audio Manager in Startup: $($shortcut.ShortcutPath)"
