param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\GameAudio.Common.ps1"

$name = ConvertTo-GameProcessName -ProcessName $ProcessName
$processes = @(Get-GameProcesses -ProcessName $name)

if ($processes.Count -eq 0) {
    Write-Output "Game process '$name' was not found."
    Write-Output ''
    Write-Output "Expected executable: $name.exe"
    Write-Output ''
    Write-Output 'Running processes with visible windows:'
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
        $path = '<unavailable>'
    }

    [PSCustomObject]@{
        ProcessName = $process.ProcessName
        Id = $process.Id
        MainWindowTitle = $process.MainWindowTitle
        Path = $path
    }
}
