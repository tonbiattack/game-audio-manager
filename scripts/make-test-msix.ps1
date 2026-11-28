#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Builds and signs a test MSIX package for local verification.

.DESCRIPTION
    Publishes the app, packs the MSIX and signs it with a self-signed certificate.

    This script deliberately does NOT add the certificate to any trusted store and
    does NOT install the package. Both need a decision from the owner because they
    change machine/user trust. The exact commands to run are printed at the end.

    A development certificate is created in the *current user* personal store only
    when -CreateDevCertificate is passed, and can be removed with -RemoveDevCertificate.

.PARAMETER Version
    Four-part MSIX version, e.g. 0.2.0.0.

.PARAMETER CreateDevCertificate
    Create a self-signed development certificate in Cert:\CurrentUser\My.
    Skipped when -CertificateThumbprint is supplied.

.PARAMETER CertificateThumbprint
    Use an existing certificate from Cert:\CurrentUser\My.

.PARAMETER RemoveDevCertificate
    Remove the certificate created by this script (identified by thumbprint) and exit.

.EXAMPLE
    ./scripts/make-test-msix.ps1 -CreateDevCertificate

.EXAMPLE
    ./scripts/make-test-msix.ps1 -CertificateThumbprint 0123ABCD...
#>
[CmdletBinding()]
param(
    [string]$Version = '0.2.0.0',
    [switch]$CreateDevCertificate,
    [string]$CertificateThumbprint,
    [switch]$RemoveDevCertificate,
    [switch]$SkipPublish
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$msixPath = Join-Path $repoRoot 'artifacts\GameAudioManager.msix'
$errorLog = Join-Path $repoRoot 'artifacts\msix-signing-error.txt'

function Get-SignTool {
    $tool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'signtool.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1
    if (-not $tool) {
        throw 'signtool.exe was not found. Install the Windows SDK.'
    }

    return $tool.FullName
}

if ($RemoveDevCertificate) {
    if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
        throw 'Pass -CertificateThumbprint so only the intended certificate is removed.'
    }

    $cert = Get-ChildItem "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
    if ($cert) {
        Remove-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -Force
        Write-Host "Removed certificate $CertificateThumbprint from Cert:\CurrentUser\My"
    }
    else {
        Write-Host "Certificate $CertificateThumbprint was not present."
    }

    exit 0
}

# --- publish ---------------------------------------------------------------
if (-not $SkipPublish) {
    & (Join-Path $PSScriptRoot 'publish.ps1') -Version ($Version.Split('.')[0..2] -join '.')
    if ($LASTEXITCODE -ne 0) {
        throw "publish.ps1 failed with exit code $LASTEXITCODE."
    }
}

# --- package ---------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($CertificateThumbprint) -and -not $CreateDevCertificate) {
    throw @'
No signing certificate supplied.

Either pass -CreateDevCertificate to create a throwaway certificate in
Cert:\CurrentUser\My, or pass -CertificateThumbprint for an existing one.

Nothing is trusted or installed by this script.
'@
}

if ($CreateDevCertificate -and [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    $subject = 'CN=GameAudioManager-Dev'
    $existing = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq $subject } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if ($existing) {
        $CertificateThumbprint = $existing.Thumbprint
        Write-Host "Reusing development certificate $CertificateThumbprint"
    }
    else {
        $created = New-SelfSignedCertificate `
            -Type Custom `
            -Subject $subject `
            -KeyUsage DigitalSignature `
            -FriendlyName 'GameAudioManager development signing' `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}') `
            -NotAfter (Get-Date).AddYears(1)
        $CertificateThumbprint = $created.Thumbprint
        Write-Host "Created development certificate $CertificateThumbprint in Cert:\CurrentUser\My"
    }
}

$cert = Get-ChildItem "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue
if (-not $cert) {
    throw "Certificate $CertificateThumbprint was not found in Cert:\CurrentUser\My."
}

# --- pack with the certificate's publisher ---------------------------------
$publisher = $cert.Subject
Write-Host "Publisher: $publisher"

& (Join-Path $PSScriptRoot 'pack-msix.ps1') -Version $Version -Publisher $publisher
if (-not (Test-Path -LiteralPath $msixPath -PathType Leaf)) {
    throw "MSIX was not produced: $msixPath"
}

# --- sign ------------------------------------------------------------------
$pfx = Join-Path $env:TEMP ("gam-msix-" + [guid]::NewGuid().ToString('N') + ".pfx")
$password = [guid]::NewGuid().ToString('N')
$secure = ConvertTo-SecureString -String $password -Force -AsPlainText

try {
    Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $secure | Out-Null

    $signTool = Get-SignTool
    & $signTool sign /fd SHA256 /f $pfx /p $password $msixPath
    if ($LASTEXITCODE -ne 0) {
        throw "signtool failed with exit code $LASTEXITCODE."
    }

    & $signTool verify /pa /v $msixPath 2>&1 | Out-File -FilePath $errorLog
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "signtool verify reported a failure (expected for a self-signed chain). See $errorLog"
    }
    else {
        Write-Host 'Signature verified (self-signed chain).'
    }
}
finally {
    Remove-Item -LiteralPath $pfx -Force -ErrorAction SilentlyContinue
}

$hash = (Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Signed MSIX: $msixPath"
Write-Host "SHA256    : $hash"
Write-Host "Certificate thumbprint: $CertificateThumbprint"
Write-Host ''
Write-Host 'Not installed and not trusted. To install it you (the owner) need administrator rights:' -ForegroundColor Yellow
Write-Host ''
Write-Host '  # 1. Export the public certificate (no admin needed)'
Write-Host "  Export-Certificate -Cert Cert:\CurrentUser\My\$CertificateThumbprint -FilePath `$env:TEMP\gam-dev.cer"
Write-Host ''
Write-Host '  # 2. Trust it for the machine (ADMIN). Required because the package root must be trusted.'
Write-Host '  Import-Certificate -FilePath $env:TEMP\gam-dev.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople'
Write-Host ''
Write-Host '  # 3. Install (no admin needed once trusted)'
Write-Host "  Add-AppxPackage -Path `"$msixPath`""
Write-Host ''
Write-Host '  # 4. Verify routing from inside the package, then uninstall'
Write-Host '  Get-AppxPackage tonbiattack.GameAudioManager | Remove-AppxPackage'
Write-Host ''
Write-Host '  # 5. Remove the trust entry when finished (ADMIN)'
Write-Host '  Get-ChildItem Cert:\LocalMachine\TrustedPeople | Where-Object { $_.Subject -eq "CN=GameAudioManager-Dev" } | Remove-Item'
Write-Host ''
Write-Host "To delete the development certificate: ./scripts/make-test-msix.ps1 -RemoveDevCertificate -CertificateThumbprint $CertificateThumbprint"
