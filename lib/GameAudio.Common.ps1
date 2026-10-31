Set-StrictMode -Version Latest

function ConvertTo-GameProcessName {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    return [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
}

function Get-GameProcesses {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    $name = ConvertTo-GameProcessName -ProcessName $ProcessName
    return @(Get-Process -Name $name -ErrorAction SilentlyContinue)
}

function Resolve-GameProcess {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    $name = ConvertTo-GameProcessName -ProcessName $ProcessName
    $processes = @(Get-GameProcesses -ProcessName $name)

    if ($processes.Count -eq 0) {
        throw "Game process '$name' was not found. Start the game first, then run .\detect-game-process.ps1 -ProcessName '$name' to diagnose."
    }

    return $processes[0]
}
