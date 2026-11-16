$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\set-shiren-output.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) { throw 'Shiren output wrapper is missing.' }

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

# A stub stands in for svcl.exe so these checks do not need a real audio device.
# CI runners have no render endpoints, so a device-dependent -List would fail there.
function New-StubSvcl {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("stub-svcl-{0}.ps1" -f [guid]::NewGuid())
    $csv = @(
        'Name,Type,Direction,Device Name,Device State,Default'
        'Speakers,Device,Render,4- USB Audio Device,Active,Render'
        'Headphones,Device,Render,5- USB Audio Device,Active,'
        'Microphone,Device,Capture,Microphone,Active,'
    ) -join [Environment]::NewLine
    $source = @"
`$csv = @'
$csv
'@
Write-Output `$csv
exit 0
"@
    [System.IO.File]::WriteAllText($path, $source, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

$stub = New-StubSvcl
try {
    $valueLabel = -join @(0x6307, 0x5b9a, 0x5024 | ForEach-Object { [char]$_ })
    $output = @(& $scriptPath -List -SvclPath $stub 2>&1)
    $exitCode = $LASTEXITCODE
    $text = $output -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        throw "-List failed with exit code ${exitCode}: $text"
    }

    Assert-Contains -Text $text -Expected $valueLabel -Message '-List must label the value passed to -Device.'
    Assert-Contains -Text $text -Expected 'with -Device' -Message '-List must explain how to use the displayed device values.'
    Assert-Contains -Text $text -Expected '4- USB Audio Device' -Message '-List must show active render devices.'
    if ($text -match [regex]::Escape('Microphone')) {
        throw "-List must not show capture devices. Actual: $text"
    }

    $rawOutput = @(& $scriptPath -RawList -SvclPath $stub 2>&1)
    $rawExitCode = $LASTEXITCODE
    $rawText = $rawOutput -join [Environment]::NewLine

    if ($rawExitCode -ne 0) {
        throw "-RawList failed with exit code ${rawExitCode}: $rawText"
    }

    Assert-Contains -Text $rawText -Expected 'Name,Type,Direction,Device Name' -Message '-RawList must return SoundVolumeCommandLine CSV output.'
}
finally {
    Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue
}

# The wrapper must still default to the bundled svcl.exe when -SvclPath is omitted.
$wrapperSource = Get-Content -Raw -LiteralPath $scriptPath
if ($wrapperSource -notmatch [regex]::Escape('Get-GameAudioSvclPath')) {
    throw 'The Shiren output wrapper must resolve the bundled svcl.exe path.'
}
if ($wrapperSource -notmatch [regex]::Escape('ShirenTheWanderer6')) {
    throw 'The Shiren output wrapper must retain its default process name.'
}

Write-Host 'PASS: set-shiren-output tests'
