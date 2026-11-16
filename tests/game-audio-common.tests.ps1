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

function Assert-True {
    param([bool]$Value, [string]$Message)

    if (-not $Value) { throw $Message }
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

# --- bundled svcl.exe location ---
$repositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$defaultSvclPath = Get-GameAudioSvclPath -RepositoryPath $repositoryPath
Assert-Equal $defaultSvclPath (Join-Path $repositoryPath 'vendor\svcl\svcl.exe') 'The default svcl.exe path must resolve into vendor\svcl.'
Assert-True (Test-Path -LiteralPath $defaultSvclPath -PathType Leaf) 'The bundled svcl.exe must exist at the default path.'

Assert-GameAudioSvclPath -SvclPath $defaultSvclPath
try {
    Assert-GameAudioSvclPath -SvclPath (Join-Path $repositoryPath 'vendor\svcl\missing-svcl.exe')
    throw 'A missing svcl.exe must be rejected.'
}
catch {
    if ($_.Exception.Message -notmatch [regex]::Escape('svcl.exe was not found')) {
        throw "A missing svcl.exe must produce a clear error. Actual: $($_.Exception.Message)"
    }
}

Write-Host 'PASS: game-audio common tests'
