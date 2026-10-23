param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Device,
    [string]$ProcessName = 'ShirenTheWanderer6',
    [string]$SvclPath = "$PSScriptRoot\svcl.exe",
    [ValidateRange(1, 3600)][int]$IntervalSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\shiren-output-watch.ps1"

if (-not (Test-Path -LiteralPath $SvclPath -PathType Leaf)) {
    throw "svcl.exe was not found: $SvclPath"
}
$name = [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
$state = New-ShirenWatchState
Write-Host "Monitoring $name and output device '$Device'. Press Ctrl+C to stop."

while ($true) {
    try {
        $process = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        $identity = if ($null -ne $process) { '{0}:{1}' -f $process.Id, $process.StartTime.ToUniversalTime().Ticks } else { $null }
        $csv = @(& $SvclPath /Stdout /scomma '')
        if ($LASTEXITCODE -ne 0) { throw "Device enumeration failed (exit code $LASTEXITCODE)." }
        $devices = @($csv | ConvertFrom-Csv | Where-Object {
            $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and
            $_.'Device State' -eq 'Active' -and $_.'Device Name' -eq $Device
        })
        if ($devices.Count -gt 1) { throw "Multiple active devices have the name '$Device'; choose a unique device name." }
        $apply = {
            try {
                & "$PSScriptRoot\set-shiren-output.ps1" -Device $Device -ProcessName $name -SvclPath $SvclPath | Out-Host
                return $true
            } catch {
                Write-Warning "Could not apply output; will retry: $_"
                return $false
            }
        }
        Update-ShirenWatchState $state $identity ($devices.Count -eq 1) $apply
    } catch {
        # An incomplete observation must not be treated as a successful application.
        $state.Applied = $false
        Write-Warning "Monitoring failed; will retry: $_"
    }
    Start-Sleep -Seconds $IntervalSeconds
}
