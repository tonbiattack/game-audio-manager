$ErrorActionPreference = 'Stop'

$library = Join-Path $PSScriptRoot '..\lib\GameAudio.Common.ps1'
if (-not (Test-Path -LiteralPath $library)) { throw 'Shared game-audio library is missing.' }
. $library

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function global:Get-Process {
    param([string]$Name, $ErrorAction)

    if ($Name -eq 'ExampleGame') {
        return @(
            [PSCustomObject]@{ ProcessName = 'ExampleGame'; Id = 101 },
            [PSCustomObject]@{ ProcessName = 'ExampleGame'; Id = 202 }
        )
    }
}

Assert-Equal (ConvertTo-GameProcessName -ProcessName 'ExampleGame') 'ExampleGame' 'A bare process name must remain unchanged.'
Assert-Equal (ConvertTo-GameProcessName -ProcessName 'ExampleGame.exe') 'ExampleGame' 'An executable suffix must be removed.'

$processes = @(Get-GameProcesses -ProcessName 'ExampleGame.exe')
Assert-Equal $processes.Count 2 'All matching processes must be returned.'
Assert-Equal (Resolve-GameProcess -ProcessName 'ExampleGame').Id 101 'The first matching process must be selected.'

try {
    Resolve-GameProcess -ProcessName 'MissingGame' | Out-Null
    throw 'Resolving a missing process must fail.'
}
catch {
    if ($_.Exception.Message -notmatch [regex]::Escape('MissingGame')) {
        throw "Missing-process diagnostics must identify the requested process. Actual: $($_.Exception.Message)"
    }
    if ($_.Exception.Message -match 'Shiren|シレン') {
        throw "Missing-process diagnostics must be game-neutral. Actual: $($_.Exception.Message)"
    }
}

Write-Host 'PASS: game-audio common tests'
