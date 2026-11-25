#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Installs Game Audio Manager for the current user so it can be started from
    Windows Search and the Start menu.

.DESCRIPTION
    Publishes (unless -SkipPublish), copies the self-contained executable to a stable
    per-user location, and registers a Start menu shortcut.

    No administrator rights are required, and the script never enables "start with
    Windows" - that stays the user's choice inside the app.

.PARAMETER Version
    Version stamped into the build. Defaults to 0.2.0.

.PARAMETER SkipPublish
    Reuse artifacts\win-x64\GameAudioManager.exe instead of building.

.PARAMETER Uninstall
    Remove the shortcut and the installed files. User settings are kept unless
    -PurgeSettings is also passed.

.PARAMETER PurgeSettings
    With -Uninstall, also delete %LOCALAPPDATA%\GameAudioManager (settings, backups).

.EXAMPLE
    ./scripts/install-local.ps1

.EXAMPLE
    ./scripts/install-local.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$Version = '0.2.0',
    [switch]$SkipPublish,
    [switch]$Uninstall,
    [switch]$PurgeSettings
)

$ErrorActionPreference = 'Stop'

$appName = 'GameAudioManager'
$displayName = 'Game Audio Manager'
$installDir = Join-Path $env:LOCALAPPDATA "Programs\$appName"
$installedExe = Join-Path $installDir "$appName.exe"
$startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuDir "$displayName.lnk"
$settingsDir = Join-Path $env:LOCALAPPDATA 'GameAudioManager'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Stop-RunningApp {
    # Stopping the app is safe: it only holds configuration, no unsaved work.
    $running = Get-Process -Name $appName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $installedExe }

    foreach ($process in $running) {
        Write-Host "Stopping running instance (PID $($process.Id)) ..."
        Stop-Process -Id $process.Id -Force
    }

    if ($running) {
        Start-Sleep -Seconds 2
        if (Get-Process -Name $appName -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $installedExe }) {
            throw "GameAudioManager.exe is still running. Stop it and retry."
        }
        Write-Host 'Stopped the running instance to replace the executable.'
    }
}

if ($Uninstall) {
    Stop-RunningApp

    if (Test-Path -LiteralPath $shortcutPath) {
        Remove-Item -LiteralPath $shortcutPath -Force
        Write-Host "Removed shortcut: $shortcutPath"
    }
    else {
        Write-Host 'No Start menu shortcut was registered.'
    }

    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force
        Write-Host "Removed install directory: $installDir"
    }

    if ($PurgeSettings) {
        if (Test-Path -LiteralPath $settingsDir) {
            Remove-Item -LiteralPath $settingsDir -Recurse -Force
            Write-Host "Removed settings: $settingsDir"
        }
    }
    elseif (Test-Path -LiteralPath $settingsDir) {
        Write-Host "Kept settings at $settingsDir (pass -PurgeSettings to delete)."
    }

    Write-Host 'Uninstalled. The "start with Windows" entry, if enabled, must be turned off in the app before uninstalling.'
    exit 0
}

# --- install -----------------------------------------------------------------
if (-not $SkipPublish) {
    & (Join-Path $PSScriptRoot 'publish.ps1') -Version $Version
    if ($LASTEXITCODE -ne 0) {
        throw "publish.ps1 failed with exit code $LASTEXITCODE."
    }
}

$sourceExe = Join-Path $repoRoot 'artifacts\win-x64\GameAudioManager.exe'
if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
    throw "Published executable not found: $sourceExe. Run without -SkipPublish, or run scripts\publish.ps1 first."
}

Stop-RunningApp

New-Item -ItemType Directory -Path $installDir -Force | Out-Null

# Copy everything published so an accidental extra file is not silently dropped.
Get-ChildItem -LiteralPath (Split-Path -Parent $sourceExe) -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $installDir -Force
}
Write-Host "Installed to $installDir"

# --- Start menu shortcut (idempotent: always rewritten, never duplicated) -----
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $installedExe
$shortcut.WorkingDirectory = $installDir
$shortcut.Description = 'アプリ・ゲームごとの音声出力先とミュートを切り替える常駐アプリ'
$shortcut.IconLocation = "$installedExe,0"
$shortcut.Save()
Write-Host "Registered Start menu shortcut: $shortcutPath"

# Tell the shell about the new entry so Search can pick it up sooner.
try {
    $signature = '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);'
    $type = Add-Type -MemberDefinition $signature -Name 'ShellNotify' -Namespace 'GameAudioManager' -PassThru
    $type::SHChangeNotify(0x8000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)
}
catch {
    Write-Warning "Could not notify the shell of the new shortcut: $($_.Exception.Message)"
}

Write-Host ''
Write-Host 'Done. Press the Windows key and type "Game Audio Manager" to start it.'
Write-Host 'Search indexing can take a few minutes to show a newly added shortcut.'
Write-Host ''
Write-Host "To remove it later: ./scripts/install-local.ps1 -Uninstall"
