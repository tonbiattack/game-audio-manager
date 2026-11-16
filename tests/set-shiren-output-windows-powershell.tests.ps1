$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\set-shiren-output.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) { throw 'Shiren output wrapper is missing.' }

# A stub stands in for svcl.exe so this check does not need a real audio device.
$stub = Join-Path ([System.IO.Path]::GetTempPath()) ("stub-svcl-{0}.ps1" -f [guid]::NewGuid())
$csv = @(
    'Name,Type,Direction,Device Name,Device State,Default'
    'Speakers,Device,Render,4- USB Audio Device,Active,Render'
) -join [Environment]::NewLine
$source = @"
`$csv = @'
$csv
'@
Write-Output `$csv
exit 0
"@
[System.IO.File]::WriteAllText($stub, $source, (New-Object System.Text.UTF8Encoding($false)))

try {
    # Windows PowerShell 5.1 reads a BOM-less script as the ANSI code page, which
    # corrupts the Japanese labels. Running the wrapper under 5.1 proves the file
    # is still saved as UTF-8 with BOM.
    $output = @(& powershell.exe -NoProfile -File $scriptPath -List -SvclPath $stub 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Windows PowerShell 5.1 must parse -List successfully: $($output -join [Environment]::NewLine)"
    }
    $text = $output -join [Environment]::NewLine
    if ($text -notmatch [regex]::Escape('4- USB Audio Device')) {
        throw "The device listing is missing. Actual: $text"
    }
    $valueLabel = -join @(0x6307, 0x5b9a, 0x5024 | ForEach-Object { [char]$_ })
    if ($text -notmatch [regex]::Escape($valueLabel)) {
        throw "Windows PowerShell 5.1 must decode the Japanese label correctly. Actual: $text"
    }
}
finally {
    Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: Windows PowerShell parses set-shiren-output'
