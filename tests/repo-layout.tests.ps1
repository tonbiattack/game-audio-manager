$ErrorActionPreference = 'Stop'

$repositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

# --- bundled SoundVolumeCommandLine lives in vendor\svcl\ ---
foreach ($name in @('svcl.exe', 'svcl.chm', 'readme.txt')) {
    $bundled = Join-Path $repositoryPath "vendor\svcl\$name"
    Assert-True (Test-Path -LiteralPath $bundled -PathType Leaf) "The bundled $name must live in vendor\svcl\."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $repositoryPath $name))) "The bundled $name must not sit in the repository root."
}

# --- Shiren 6 implementation lives in legacy\shiren6\ ---
$legacyImplementation = Join-Path $repositoryPath 'legacy\shiren6\ShirenOutputWatch.ps1'
$legacyEntryPoint = Join-Path $repositoryPath 'legacy\shiren6\watch-shiren-output.ps1'
Assert-True (Test-Path -LiteralPath $legacyImplementation -PathType Leaf) 'The Shiren watch implementation must live in legacy\shiren6\.'
Assert-True (Test-Path -LiteralPath $legacyEntryPoint -PathType Leaf) 'The Shiren watch entry point must live in legacy\shiren6\.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $repositoryPath 'shiren-output-watch.ps1'))) 'The Shiren watch implementation must not sit in the repository root.'

# --- root Shiren commands stay as thin compatibility wrappers ---
$wrappers = @{
    'detect-shiren-process.ps1' = 'detect-game-process.ps1'
    'toggle-shiren-mute.ps1'    = 'toggle-game-mute.ps1'
    'set-shiren-output.ps1'     = 'set-game-output.ps1'
    'watch-shiren-output.ps1'   = 'legacy\shiren6\watch-shiren-output.ps1'
}
foreach ($wrapper in $wrappers.Keys) {
    $wrapperPath = Join-Path $repositoryPath $wrapper
    Assert-True (Test-Path -LiteralPath $wrapperPath -PathType Leaf) "The compatibility wrapper $wrapper must stay in the repository root."
    $source = Get-Content -Raw -LiteralPath $wrapperPath
    Assert-True ($source -match [regex]::Escape($wrappers[$wrapper])) "$wrapper must delegate to $($wrappers[$wrapper])."
    $lineCount = @($source -split "`n").Count
    Assert-True ($lineCount -le 40) "$wrapper must stay a thin wrapper, but it has $lineCount lines."
}

# --- the Shiren 6 procedure is documented separately from the generic README ---
$readme = Get-Content -Raw -LiteralPath (Join-Path $repositoryPath 'README.md')
$shirenDoc = Join-Path $repositoryPath 'docs\shiren6.md'
Assert-True (Test-Path -LiteralPath $shirenDoc -PathType Leaf) 'The Shiren 6 procedure must be documented in docs\shiren6.md.'
Assert-True ($readme -match [regex]::Escape('docs/shiren6.md')) 'The README must link to docs/shiren6.md.'
Assert-True ($readme -notmatch [regex]::Escape('C:\apps\toggle-shiren-mute')) 'The README must not keep the old repository path.'

$shirenDocText = Get-Content -Raw -LiteralPath $shirenDoc
Assert-True ($shirenDocText -notmatch [regex]::Escape('C:\apps\toggle-shiren-mute')) 'docs/shiren6.md must not keep the old repository path.'

# --- shared libraries live in lib\ ---
foreach ($name in @('GameAudio.Common.ps1', 'GameAudio.Config.ps1', 'GameAudio.Gui.ps1', 'GameAudio.Mute.ps1', 'GameAudio.Startup.ps1', 'GameAudio.Watch.ps1')) {
    $libraryPath = Join-Path $repositoryPath "lib\$name"
    Assert-True (Test-Path -LiteralPath $libraryPath -PathType Leaf) "The shared library lib\$name must exist."
}

# --- CI runs the device-independent suite ---
$workflow = Join-Path $repositoryPath '.github\workflows\tests.yml'
Assert-True (Test-Path -LiteralPath $workflow -PathType Leaf) 'A GitHub Actions workflow must run the tests.'
$workflowText = Get-Content -Raw -LiteralPath $workflow
Assert-True ($workflowText -match 'windows-latest') 'The test workflow must run on windows-latest.'
Assert-True ($workflowText -match [regex]::Escape('tests/run-all.tests.ps1')) 'The test workflow must run tests/run-all.tests.ps1.'

# --- every script that contains non-ASCII text must be UTF-8 with BOM ---
# Windows PowerShell 5.1 reads a BOM-less file as the ANSI code page, which
# corrupts Japanese string literals and breaks parsing. The startup shortcut
# launches the GUI with powershell.exe, so this must hold for every script.
$scripts = @(Get-ChildItem -LiteralPath $repositoryPath -Recurse -Filter '*.ps1' -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' })
Assert-True ($scripts.Count -gt 0) 'The repository must contain PowerShell scripts.'
foreach ($script in $scripts) {
    $bytes = [System.IO.File]::ReadAllBytes($script.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    if ($text -match '[^\x00-\x7F]') {
        Assert-True $hasBom "$($script.Name) contains non-ASCII text and must be saved as UTF-8 with BOM so Windows PowerShell 5.1 parses it."
    }
}

Write-Host 'PASS: repository layout tests'
