$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '..\set-shiren-output.ps1'
$output = @(& powershell.exe -NoProfile -File $scriptPath -List 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Windows PowerShell 5.1 must parse -List successfully: $($output -join [Environment]::NewLine)"
}
if (($output -join [Environment]::NewLine) -notmatch 'Device') {
    throw 'The device listing is missing.'
}
Write-Host 'PASS: Windows PowerShell parses set-shiren-output'
