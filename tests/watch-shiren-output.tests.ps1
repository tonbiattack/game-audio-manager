$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\shiren-output-watch.ps1'
if (-not (Test-Path $module)) { throw 'Monitor implementation is missing.' }
. $module

function Assert-Equal($actual, $expected, $message) {
    if ($actual -ne $expected) { throw "$message Expected $expected, got $actual" }
}

$firstMutex = Enter-ShirenWatchMutex -Name 'toggle-shiren-mute-test'
if ($null -eq $firstMutex) { throw 'The first monitor must acquire its mutex.' }
$secondMutex = Enter-ShirenWatchMutex -Name 'toggle-shiren-mute-test'
if ($null -ne $secondMutex) { throw 'A second monitor must not acquire the same mutex.' }
$firstMutex.ReleaseMutex()
$firstMutex.Dispose()

$state = New-ShirenWatchState
$attempts = 0
$apply = { $script:attempts++; return $true }
Update-ShirenWatchState $state 10 $true $apply
Update-ShirenWatchState $state 10 $true $apply
Assert-Equal $attempts 1 'A stable process and device must not be reapplied.'
Update-ShirenWatchState $state 11 $true $apply
Assert-Equal $attempts 2 'A restarted game must be reapplied.'
Update-ShirenWatchState $state 11 $false $apply
Update-ShirenWatchState $state 11 $true $apply
Assert-Equal $attempts 3 'A reconnected device must be reapplied.'
Update-ShirenWatchState $state $null $true $apply
Update-ShirenWatchState $state 11 $true $apply
Assert-Equal $attempts 4 'A stopped and restarted game must be reapplied.'

$state = New-ShirenWatchState
$attempts = 0
$retry = { $script:attempts++; return ($script:attempts -gt 1) }
Update-ShirenWatchState $state 12 $true $retry
Update-ShirenWatchState $state 12 $true $retry
Assert-Equal $attempts 2 'A failed application must be retried.'
Write-Host 'PASS: watch-shiren-output tests'
