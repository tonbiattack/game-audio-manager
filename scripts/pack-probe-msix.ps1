#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds, packs and (optionally) registers the minimal MSIX probe for issue #39.

.DESCRIPTION
    Produces artifacts\GameAudioManagerProbe.msix from tools\msix-probe and a loose
    package layout in artifacts\probe-package.

    The package is NOT signed and NOT trusted. -Register uses a development
    registration (developer mode), which gives the process real package identity
    without changing certificate trust on the machine.

.PARAMETER Version
    Four-part MSIX version.

.PARAMETER Register
    Register the package layout for the current user. Uninstall with
    Remove-AppxPackage (see docs\msix-verification.md).

.PARAMETER Unregister
    Remove a previously registered probe package and exit.

.PARAMETER ScenarioPath
    Absolute path of the scenario file the packaged probe reads.
#>
[CmdletBinding()]
param(
    [string]$Version = '0.2.0.0',
    [switch]$Register,
    [switch]$Unregister,
    [switch]$SkipPublish,
    [string]$ScenarioPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$layout = Join-Path $repoRoot 'artifacts\probe-package'
$packagePath = Join-Path $repoRoot 'artifacts\GameAudioManagerProbe.msix'
$packageName = 'Tonbiattack.GameAudioManager.MsixProbe'

if ($Unregister) {
    Get-AppxPackage -Name $packageName | Remove-AppxPackage
    Write-Host "Removed $packageName (if it was registered)."
    exit 0
}

$makeAppx = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'makeappx.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
if (-not $makeAppx) {
    throw 'makeappx.exe was not found. Install the Windows SDK.'
}

function New-ProbeLayout {
    param([string]$Target)

    if (Test-Path -LiteralPath $Target) {
        Remove-Item -LiteralPath $Target -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null

    Copy-Item (Join-Path $repoRoot 'packaging\Package\Assets') $Target -Recurse
    Copy-Item (Join-Path $repoRoot 'packaging\Probe\AppxManifest.xml') $Target

    $publishDir = Join-Path $repoRoot 'artifacts\probe\win-x64'
    Get-ChildItem -LiteralPath $publishDir -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Target
    }

    $manifestPath = Join-Path $Target 'AppxManifest.xml'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath
    $manifest = [regex]::Replace($manifest, '(<Identity\b[^>]*?)Version="[0-9.]+"', '${1}Version="' + $Version + '"')
    [System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding($false)))

    # The packaged process cannot receive arguments, so it reads this bootstrap file
    # and, through it, a scenario file outside the package that can be edited freely.
    $bootstrap = @{ ScenarioPath = $ScenarioPath } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $Target 'probe-config.json'), $bootstrap, (New-Object System.Text.UTF8Encoding($false)))
}

if (-not $SkipPublish) {
    $project = Join-Path $repoRoot 'tools\msix-probe\MsixProbe.csproj'
    dotnet publish $project `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:DebugType=none `
        --output (Join-Path $repoRoot 'artifacts\probe\win-x64')
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE."
    }
}

New-ProbeLayout -Target $layout

& $makeAppx.FullName pack /d $layout /p $packagePath /o | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "makeappx failed with exit code $LASTEXITCODE."
}

Write-Host "Packed: $packagePath (unsigned)"
Write-Host "Layout: $layout"

if ($Register) {
    Add-AppxPackage -Register (Join-Path $layout 'AppxManifest.xml')
    $package = Get-AppxPackage -Name $packageName
    $aumid = "$($package.PackageFamilyName)!MsixProbe"
    Write-Host "Registered: $($package.PackageFullName)"
    Write-Host "Launch with: explorer.exe shell:AppsFolder\$aumid"
}
