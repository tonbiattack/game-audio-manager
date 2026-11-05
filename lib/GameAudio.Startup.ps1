Set-StrictMode -Version Latest

function Get-GameAudioStartupShortcutDefinition {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StartupDirectory,
        [string]$PowerShellExecutablePath = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )

    $resolvedRepositoryPath = (Resolve-Path -LiteralPath $RepositoryPath -ErrorAction Stop).Path
    $guiScriptPath = Join-Path $resolvedRepositoryPath 'game-audio-manager.ps1'
    if (-not (Test-Path -LiteralPath $guiScriptPath -PathType Leaf)) {
        throw "Game Audio Manager GUI script was not found: $guiScriptPath"
    }
    if (-not (Test-Path -LiteralPath $PowerShellExecutablePath -PathType Leaf)) {
        throw "Windows PowerShell executable was not found: $PowerShellExecutablePath"
    }

    return [PSCustomObject]@{
        ShortcutPath = Join-Path $StartupDirectory 'Game Audio Manager.lnk'
        TargetPath = $PowerShellExecutablePath
        Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $guiScriptPath)
        WorkingDirectory = $resolvedRepositoryPath
    }
}

function Set-GameAudioStartupShortcut {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StartupDirectory,
        [string]$PowerShellExecutablePath = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )

    $definition = Get-GameAudioStartupShortcutDefinition -RepositoryPath $RepositoryPath -StartupDirectory $StartupDirectory -PowerShellExecutablePath $PowerShellExecutablePath
    $null = New-Item -ItemType Directory -Path $StartupDirectory -Force
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($definition.ShortcutPath)
    $shortcut.TargetPath = $definition.TargetPath
    $shortcut.Arguments = $definition.Arguments
    $shortcut.WorkingDirectory = $definition.WorkingDirectory
    $shortcut.Description = 'Launch Game Audio Manager'
    $shortcut.Save()
    return $definition
}

function Remove-GameAudioStartupShortcut {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StartupDirectory)

    $shortcutPath = Join-Path $StartupDirectory 'Game Audio Manager.lnk'
    if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { return $false }
    Remove-Item -LiteralPath $shortcutPath -Force
    return $true
}
