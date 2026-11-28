#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds an MSIX package for the desktop app.

.DESCRIPTION
    Produces artifacts\GameAudioManager.msix from the published self-contained
    executable and packaging\Package.

    The package is NOT signed by this script. Signing and side-loading require a
    trusted certificate chain; see docs/msix-verification.md before relying on the
    output.

.PARAMETER Version
    Four-part version written into AppxManifest (e.g. 0.2.0.0).

.PARAMETER Publisher
    Directory name of the signing certificate subject, e.g. "CN=Your Name".
    Must match the certificate used to sign the package.
#>
[CmdletBinding()]
param(
    [string]$Version = '2.0.0.0',
    [string]$Publisher = 'CN=2F14A66E-02DF-43E2-93E0-5C5900B38D2E'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$makeAppx = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'makeappx.exe' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1

if (-not $makeAppx) {
    throw 'makeappx.exe was not found. Install the Windows SDK.'
}

$published = Join-Path $repoRoot 'artifacts\win-x64\GameAudioManager.exe'
if (-not (Test-Path -LiteralPath $published -PathType Leaf)) {
    throw "Publish first: scripts\publish.ps1. Missing $published"
}

$staging = Join-Path $env:TEMP ("gam-msix-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $staging -Force | Out-Null

try {
    Copy-Item (Join-Path $repoRoot 'packaging\Package\Assets') $staging -Recurse
    Copy-Item -LiteralPath $published -Destination $staging

    $manifest = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'packaging\Package\AppxManifest.xml')
    # Only touch the Identity element: a bare Version="…" pattern also matches
    # MinVersion="…" in TargetDeviceFamily and produces an invalid manifest.
    $manifest = [regex]::Replace($manifest, '(<Identity\b[^>]*?)Version="[0-9.]+"', '${1}Version="' + $Version + '"')
    $manifest = [regex]::Replace($manifest, '(<Identity\b[^>]*?)Publisher="[^"]+"', '${1}Publisher="' + $Publisher + '"')
    # makeappx rejects a UTF-8 BOM in the manifest; write plain UTF-8.
    $manifestPath = Join-Path $staging 'AppxManifest.xml'
    [System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding($false)))

    $output = Join-Path $repoRoot 'artifacts\GameAudioManager.msix'
    New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
    & $makeAppx.FullName pack /d $staging /p $output /o | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "makeappx failed with exit code $LASTEXITCODE."
    }

    $size = [math]::Round((Get-Item -LiteralPath $output).Length / 1MB, 1)
    Write-Host "Packed: $output ($size MB)"
    Write-Host 'Not signed. See docs/msix-verification.md.'
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}


