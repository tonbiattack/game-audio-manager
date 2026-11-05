param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Device,
    [string]$ProcessName = 'ShirenTheWanderer6',
    [string]$SvclPath,
    [ValidateRange(1, 3600)][int]$IntervalSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\shiren-output-watch.ps1"

if ([string]::IsNullOrWhiteSpace($SvclPath)) {
    $SvclPath = Join-Path $PSScriptRoot 'svcl.exe'
}

$Device = Split-ShirenOutputDevices -Values $Device
if ($Device.Count -eq 0) {
    throw 'Specify at least one output device.'
}

if (-not (Test-Path -LiteralPath $SvclPath -PathType Leaf)) {
    throw "svcl.exe was not found: $SvclPath"
}
$name = [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
$mutex = Enter-ShirenWatchMutex -Name "toggle-shiren-mute-$name-$($Device -join '|')"
if ($null -eq $mutex) {
    Write-Host "A monitor for $name and '$Device' is already running."
    exit 0
}
$state = New-ShirenWatchState
Write-Host "Monitoring $name and output devices '$($Device -join "', '")'. Press Ctrl+C to stop."

try {
    while ($true) {
        try {
        $process = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
        $identity = if ($null -ne $process) { '{0}:{1}' -f $process.Id, $process.StartTime.ToUniversalTime().Ticks } else { $null }
        $csv = @(& $SvclPath /Stdout /scomma '')
        if ($LASTEXITCODE -ne 0) { throw "Device enumeration failed (exit code $LASTEXITCODE)." }
        $activeDeviceNames = @($csv | ConvertFrom-Csv | Where-Object {
            $_.Type -eq 'Device' -and $_.Direction -eq 'Render' -and
            $_.'Device State' -eq 'Active'
        } | ForEach-Object { $_.'Device Name' })
        $destination = Get-PreferredActiveDevice -Candidates $Device -ActiveDevices $activeDeviceNames
        $apply = {
            param($SelectedDevice)
            try {
                & "$PSScriptRoot\set-shiren-output.ps1" -Device $SelectedDevice -ProcessName $name -SvclPath $SvclPath | Out-Host
                return $true
            } catch {
                Write-Warning "Could not apply output; will retry: $_"
                return $false
            }
        }
        Update-ShirenWatchState $state $identity $destination $apply
        } catch {
            # An incomplete observation must not be treated as a successful application.
            $state.Applied = $false
            Write-Warning "Monitoring failed; will retry: $_"
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
