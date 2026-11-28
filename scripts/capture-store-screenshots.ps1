#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Captures Microsoft Store screenshots of the desktop app at a fixed size.

.DESCRIPTION
    The Store wants screenshots of at least 1366x768, ideally 1920x1080. Capturing
    by hand is easy to get wrong (a window resized right before the capture can be
    painted half-way), so this script drives it:

      1. back up %LOCALAPPDATA%\GameAudioManager\settings.json
      2. for every theme x language combination, write that setting, start the app,
         resize the window, wait for the layout to settle, and capture the window
         with PrintWindow (not a screen grab, so other windows cannot cover it)
      3. restore the original settings file and stop the app

    The app is left stopped: start it again yourself if you were using it.

.PARAMETER ExecutablePath
    App to capture. Defaults to artifacts\win-x64\GameAudioManager.exe, then the
    locally installed copy.

.PARAMETER OutputDirectory
    Where the PNGs go. Defaults to docs\images\store.

.PARAMETER Width
    Window width in pixels. Default 1920.

.PARAMETER Height
    Window height in pixels. Default 1080.

.EXAMPLE
    ./scripts/capture-store-screenshots.ps1

.EXAMPLE
    ./scripts/capture-store-screenshots.ps1 -Width 1366 -Height 768
#>
[CmdletBinding()]
param(
    [string]$ExecutablePath,
    [string]$OutputDirectory = 'docs\images\store',
    [int]$Width = 1920,
    [int]$Height = 1080
)

$ErrorActionPreference = 'Stop'

if ($Width -lt 1366 -or $Height -lt 768) {
    throw "The Store requires at least 1366x768 (requested ${Width}x${Height})."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}

$candidates = @(
    $ExecutablePath,
    (Join-Path $repoRoot 'artifacts\win-x64\GameAudioManager.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\GameAudioManager\GameAudioManager.exe')
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$executable = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $executable) {
    throw 'GameAudioManager.exe was not found. Run scripts/publish.ps1 first or pass -ExecutablePath.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

Add-Type -AssemblyName System.Drawing, System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class StoreCapture {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    public const uint NoMove = 0x0002;
    public const uint NoZOrder = 0x0004;
    public const uint NoActivate = 0x0010;
    public const uint ShowNormal = 1;
}
"@

function Stop-App {
    Get-Process -Name 'GameAudioManager' -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 800
}

function Wait-ForWindow {
    param([System.Diagnostics.Process]$Process, [int]$TimeoutSeconds = 25)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne 0) {
            return $Process.MainWindowHandle
        }

        Start-Sleep -Milliseconds 250
    }

    throw "The app did not open a window within $TimeoutSeconds seconds."
}

function Save-WindowImage {
    param([IntPtr]$Handle, [string]$Path)

    $rect = New-Object StoreCapture+RECT
    if (-not [StoreCapture]::GetWindowRect($Handle, [ref]$rect)) {
        throw 'GetWindowRect failed.'
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        throw "The window has no size (${width}x${height})."
    }

    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $hdc = $graphics.GetHdc()
        try {
            # PW_RENDERFULLCONTENT (2) is required for WPF/DirectComposition windows.
            if (-not [StoreCapture]::PrintWindow($Handle, $hdc, 2)) {
                throw 'PrintWindow failed.'
            }
        }
        finally {
            $graphics.ReleaseHdc($hdc)
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    return @{ Width = $width; Height = $height; Path = $Path }
}

$settingsPath = Join-Path $env:LOCALAPPDATA 'GameAudioManager\settings.json'
$backupPath = $null
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $backupPath = Join-Path $env:TEMP ("gam-settings-" + [guid]::NewGuid().ToString('N') + '.json')
    Copy-Item -LiteralPath $settingsPath -Destination $backupPath -Force
}

$combinations = @(
    @{ Language = 'ja'; Theme = 'light' },
    @{ Language = 'ja'; Theme = 'dark' },
    @{ Language = 'en'; Theme = 'light' },
    @{ Language = 'en'; Theme = 'dark' }
)

$captures = [System.Collections.Generic.List[object]]::new()
Stop-App

try {
    foreach ($combination in $combinations) {
        $settings = @{}
        if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        }

        $settings['language'] = $combination.Language
        $settings['theme'] = $combination.Theme
        $settingsDirectory = Split-Path -Parent $settingsPath
        New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
        $settings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM

        $process = Start-Process -FilePath $executable -PassThru
        $handle = Wait-ForWindow -Process $process

        # Resize without moving: a window larger than the desktop still paints fully.
        [StoreCapture]::ShowWindow($handle, [StoreCapture]::ShowNormal) | Out-Null
        [StoreCapture]::SetWindowPos(
            $handle,
            [IntPtr]::Zero,
            0,
            0,
            $Width,
            $Height,
            ([StoreCapture]::NoMove -bor [StoreCapture]::NoZOrder -bor [StoreCapture]::NoActivate)) | Out-Null
        [StoreCapture]::SetForegroundWindow($handle) | Out-Null

        # Give WPF time to re-layout and repaint after the resize; the earlier
        # manual attempt produced clipped rows because the capture raced the paint.
        Start-Sleep -Milliseconds 1800

        $name = "store-$($combination.Language)-$($combination.Theme).png"
        $path = Join-Path $OutputDirectory $name
        $captures.Add((Save-WindowImage -Handle $handle -Path $path))

        Stop-App
    }
}
finally {
    Stop-App
    if ($backupPath) {
        Copy-Item -LiteralPath $backupPath -Destination $settingsPath -Force
        Remove-Item -LiteralPath $backupPath -Force
        Write-Host "Restored $settingsPath"
    }
    elseif (Test-Path -LiteralPath $settingsPath) {
        Remove-Item -LiteralPath $settingsPath -Force
    }
}

foreach ($capture in $captures) {
    Write-Host ("{0}  ({1}x{2})" -f $capture.Path, $capture.Width, $capture.Height)
}
