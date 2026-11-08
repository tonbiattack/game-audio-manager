param(
    [string]$StartupDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup),
    [switch]$IncludeWatcher,
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\GameAudio.Startup.ps1"

if ($Remove) {
    $removedGui = Remove-GameAudioStartupShortcut -StartupDirectory $StartupDirectory
    $removedWatcher = $false
    try {
        $removedWatcher = Remove-GameAudioWatcherStartupShortcut -StartupDirectory $StartupDirectory
    }
    catch {
        # The watcher shortcut is optional; a missing registration is not an error.
    }
    if ($removedGui) {
        Write-Host 'Removed Game Audio Manager from Startup.'
    }
    else {
        Write-Host 'Game Audio Manager was not registered in Startup.'
    }
    if ($removedWatcher) {
        Write-Host 'Removed Game Audio Manager Watcher from Startup.'
    }
    exit 0
}

$shortcut = Set-GameAudioStartupShortcut -RepositoryPath $PSScriptRoot -StartupDirectory $StartupDirectory
Write-Host "Registered Game Audio Manager in Startup: $($shortcut.ShortcutPath)"

if ($IncludeWatcher) {
    $watcherShortcut = Set-GameAudioWatcherStartupShortcut -RepositoryPath $PSScriptRoot -StartupDirectory $StartupDirectory
    Write-Host "Registered Game Audio Manager Watcher in Startup: $($watcherShortcut.ShortcutPath)"
}
