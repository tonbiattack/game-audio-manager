$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\set-shiren-output.ps1'

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Expected,
        [string]$Message
    )

    if ($Text -notmatch [regex]::Escape($Expected)) {
        throw "$Message Expected to find: $Expected"
    }
}

function Test-ListShowsPlaybackDevices {
    $output = @(& $scriptPath -List 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $output -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        throw "-List failed with exit code ${exitCode}: $text"
    }

    Assert-Contains -Text $text -Expected '指定値' -Message '-List must label the value passed to -Device.'
    Assert-Contains -Text $text -Expected 'with -Device' -Message '-List must explain how to use the displayed device values.'
}

function Test-RawListRetainsSvclCsv {
    $output = @(& $scriptPath -RawList 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $output -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        throw "-RawList failed with exit code ${exitCode}: $text"
    }

    Assert-Contains -Text $text -Expected 'Name,Type,Direction,Device Name' -Message '-RawList must return SoundVolumeCommandLine CSV output.'
}

Test-ListShowsPlaybackDevices
Test-RawListRetainsSvclCsv
Write-Host 'PASS: set-shiren-output tests'
