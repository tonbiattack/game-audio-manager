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

# --- device name validation ---
# svcl.exe exits 0 for an unknown device name, so the name must be validated
# against the active render devices before it is used.
$available = @('4- USB Audio Device', 'Steam Streaming Speakers', 'Soundcore Space A40')

Assert-Equal (Assert-GameAudioDeviceName -Device '4- USB Audio Device' -AvailableDevices $available) '4- USB Audio Device' 'An exact device name must be accepted.'
Assert-Equal (Assert-GameAudioDeviceName -Device '4- usb audio device' -AvailableDevices $available) '4- USB Audio Device' 'Device matching must be case-insensitive and return the canonical name.'
Assert-Equal (Assert-GameAudioDeviceName -Device '  Steam Streaming Speakers  ' -AvailableDevices $available) 'Steam Streaming Speakers' 'Surrounding whitespace must be tolerated.'

try {
    Assert-GameAudioDeviceName -Device 'Definitely Not A Device' -AvailableDevices $available | Out-Null
    throw 'An unknown device name must be rejected.'
}
catch {
    if ($_.Exception.Message -notmatch [regex]::Escape('Output device was not found')) {
        throw "An unknown device must produce a clear error. Actual: $($_.Exception.Message)"
    }
    if ($_.Exception.Message -notmatch [regex]::Escape('4- USB Audio Device')) {
        throw "An unknown device error must list the available devices. Actual: $($_.Exception.Message)"
    }
}

# A partial name must not silently select a device: svcl.exe would accept it,
# but the user did not ask for that exact endpoint.
try {
    Assert-GameAudioDeviceName -Device 'USB Audio' -AvailableDevices $available | Out-Null
    throw 'A partial device name must be rejected.'
}
catch {
    if ($_.Exception.Message -notmatch [regex]::Escape('Output device was not found')) {
        throw "A partial device name must be rejected. Actual: $($_.Exception.Message)"
    }
}

try {
    Assert-GameAudioDeviceName -Device '' -AvailableDevices $available | Out-Null
    throw 'An empty device name must be rejected.'
}
catch {
    if ($_.Exception.Message -notmatch [regex]::Escape('Specify the destination device')) {
        throw "An empty device name must ask for -Device. Actual: $($_.Exception.Message)"
    }
}

try {
    Assert-GameAudioDeviceName -Device '4- USB Audio Device' -AvailableDevices @() | Out-Null
    throw 'A device name must be rejected when no device is active.'
}
catch {
    if ($_.Exception.Message -notmatch [regex]::Escape('No active render device')) {
        throw "A missing active device must be explained. Actual: $($_.Exception.Message)"
    }
}

# --- reading active devices from svcl.exe ---
$stub = Join-Path ([System.IO.Path]::GetTempPath()) ("stub-svcl-{0}.ps1" -f [guid]::NewGuid())
$csv = @(
    'Name,Type,Direction,Device Name,Device State,Default'
    'Speakers,Device,Render,4- USB Audio Device,Active,Render'
    'Headphones,Device,Render,5- USB Audio Device,Active,'
    'Unplugged,Device,Render,Old Headset,Unplugged,'
    'Microphone,Device,Capture,Microphone,Active,'
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
    $active = @(Get-GameAudioActiveDeviceName -SvclPath $stub)
    Assert-Equal ($active -join ',') '4- USB Audio Device,5- USB Audio Device' 'Only active render devices must be returned.'
}
finally {
    Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue
}

Write-Host 'PASS: game-audio common tests'
