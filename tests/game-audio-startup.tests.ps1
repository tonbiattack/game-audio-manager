$ErrorActionPreference = 'Stop'

$library = Join-Path $PSScriptRoot '..\lib\GameAudio.Startup.ps1'
$installer = Join-Path $PSScriptRoot '..\Install-GameAudioManagerStartup.ps1'
if (-not (Test-Path -LiteralPath $library)) { throw 'Game audio startup library is missing.' }
if (-not (Test-Path -LiteralPath $installer)) { throw 'Game audio startup installer is missing.' }
. $library

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}

$repositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$startupDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("game-audio-startup-{0}" -f [guid]::NewGuid())
$windowsPowerShellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

try {
    $definition = Get-GameAudioStartupShortcutDefinition -RepositoryPath $repositoryPath -StartupDirectory $startupDirectory -PowerShellExecutablePath $windowsPowerShellPath
    Assert-Equal $definition.ShortcutPath (Join-Path $startupDirectory 'Game Audio Manager.lnk') 'Shortcut name must be stable.'
    Assert-Equal $definition.TargetPath $windowsPowerShellPath 'Shortcut must launch Windows PowerShell even when registration is started from PowerShell 7.'
    Assert-Equal $definition.WorkingDirectory $repositoryPath 'Shortcut must use the repository as its working directory.'
    Assert-True ($definition.Arguments -match [regex]::Escape((Join-Path $repositoryPath 'game-audio-manager.ps1'))) 'Shortcut must launch the GUI script by absolute path.'

    $watcherDefinition = Get-GameAudioWatcherStartupShortcutDefinition -RepositoryPath $repositoryPath -StartupDirectory $startupDirectory -PowerShellExecutablePath $windowsPowerShellPath
    Assert-Equal $watcherDefinition.ShortcutPath (Join-Path $startupDirectory 'Game Audio Manager Watcher.lnk') 'Watcher shortcut name must be stable.'
    Assert-True ($watcherDefinition.Arguments -match [regex]::Escape((Join-Path $repositoryPath 'watch-game-output.ps1'))) 'Watcher shortcut must launch the watcher script by absolute path.'
    Assert-True ($watcherDefinition.Arguments -match '-WindowStyle Hidden') 'Watcher shortcut must stay hidden.'

    & $installer -StartupDirectory $startupDirectory -IncludeWatcher
    Assert-True (Test-Path -LiteralPath $definition.ShortcutPath -PathType Leaf) 'Installer must create the startup shortcut.'
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($definition.ShortcutPath)
    Assert-Equal $shortcut.TargetPath $definition.TargetPath 'Created shortcut target must match the definition.'
    Assert-Equal $shortcut.Arguments $definition.Arguments 'Created shortcut arguments must match the definition.'
    Assert-Equal $shortcut.WorkingDirectory $definition.WorkingDirectory 'Created shortcut working directory must match the definition.'
    Assert-True (Test-Path -LiteralPath $watcherDefinition.ShortcutPath -PathType Leaf) 'IncludeWatcher must create the watcher startup shortcut.'
    $watcherShortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($watcherDefinition.ShortcutPath)
    Assert-Equal $watcherShortcut.Arguments $watcherDefinition.Arguments 'Created watcher shortcut arguments must match the definition.'

    & $installer -StartupDirectory $startupDirectory
    Assert-True (Test-Path -LiteralPath $definition.ShortcutPath -PathType Leaf) 'Reinstalling must retain the same shortcut.'
    & $installer -StartupDirectory $startupDirectory -Remove
    Assert-True (-not (Test-Path -LiteralPath $definition.ShortcutPath)) 'Remove must delete the startup shortcut.'
    Assert-True (-not (Test-Path -LiteralPath $watcherDefinition.ShortcutPath)) 'Remove must also delete the watcher startup shortcut.'
    & $installer -StartupDirectory $startupDirectory -Remove
}
finally {
    Remove-Item -LiteralPath $startupDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: game-audio-startup tests'
