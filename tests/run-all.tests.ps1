param(
    [string]$PowerShellExecutablePath = 'powershell.exe'
)

$ErrorActionPreference = 'Stop'
$tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.tests.ps1' | Where-Object { $_.Name -ne 'run-all.tests.ps1' })
$failures = @()
foreach ($test in $tests) {
    Write-Host "RUN: $($test.Name)"
    $output = & $PowerShellExecutablePath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $test.FullName 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = ($output | Out-String).TrimEnd()
    if ($exitCode -ne 0) {
        $failures += $test.Name
        Write-Host $outputText
        Write-Host "FAIL: $($test.Name)"
    }
    else {
        foreach ($line in @($output | Where-Object { $_ -like 'PASS*' })) { Write-Host $line }
    }
}
if ($failures.Count -gt 0) {
    throw "Test failures: $($failures -join ', ')"
}
Write-Host "ALL PASS: $($tests.Count) test files"
