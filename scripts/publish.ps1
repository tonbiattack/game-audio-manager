#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds the distributable Game Audio Manager executable.

.DESCRIPTION
    Produces a self-contained, single-file executable so users do not need to
    install the .NET runtime. Output goes to artifacts\win-x64\.

    The app needs no external helper executable: per-app routing goes through the
    Windows audio policy API directly (see docs\dotnet-migration.md).

.PARAMETER Version
    Version stamped into the assembly. Defaults to 0.1.0.
#>
[CmdletBinding()]
param(
    [string]$Version = '0.1.0',
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$project = Join-Path $repoRoot 'src\GameAudioManager.App\GameAudioManager.App.csproj'
$output = Join-Path $repoRoot "artifacts\$Runtime"

if (Test-Path -LiteralPath $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}

Write-Host "Publishing $Version for $Runtime ..."

dotnet publish $project `
    --configuration Release `
    --runtime $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -p:Version=$Version `
    -p:DebugType=none `
    --output $output

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

$exe = Join-Path $output 'GameAudioManager.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "The expected executable was not produced: $exe"
}

# Ship the licence files alongside the binary.
foreach ($file in @('LICENSE', 'THIRD_PARTY_NOTICES.md', 'README.md')) {
    $source = Join-Path $repoRoot $file
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination $output -Force
    }
}

$size = [math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1)
Write-Host "Done: $exe ($size MB)"
