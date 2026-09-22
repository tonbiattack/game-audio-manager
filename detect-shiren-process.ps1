param(
    [string]$ProcessName = "ShirenTheWanderer6"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$name = [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
$processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)

if ($processes.Count -eq 0) {
    Write-Host "Shiren 6 process was not found."
    Write-Host ""
    Write-Host "Expected executable: ShirenTheWanderer6.exe"
    Write-Host ""
    Write-Host "Running processes with visible windows:"
    Get-Process |
        Where-Object { $_.MainWindowTitle } |
        Select-Object ProcessName, Id, MainWindowTitle |
        Sort-Object ProcessName |
        Format-Table -AutoSize

    exit 1
}

foreach ($process in $processes) {
    $path = $null

    try {
        $path = $process.Path
    }
    catch {
        $path = "<unavailable>"
    }

    [PSCustomObject]@{
        ProcessName     = $process.ProcessName
        Id              = $process.Id
        MainWindowTitle = $process.MainWindowTitle
        Path            = $path
    }
}
