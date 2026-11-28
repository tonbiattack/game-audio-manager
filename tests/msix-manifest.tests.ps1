$ErrorActionPreference = 'Stop'

$repositoryPath = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifestPath = Join-Path $repositoryPath 'packaging\Package\AppxManifest.xml'
$packScriptPath = Join-Path $repositoryPath 'scripts\pack-msix.ps1'
$startupSourcePath = Join-Path $repositoryPath 'src\GameAudioManager.App\Startup\StartupTaskRegistration.cs'

function Assert-True {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'packaging/Package/AppxManifest.xml must exist.'

# makeappx rejects a UTF-8 BOM in the manifest with 0x80080204.
$bytes = [System.IO.File]::ReadAllBytes($manifestPath)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
Assert-True (-not $hasBom) 'The MSIX manifest must be saved as UTF-8 without a BOM; makeappx rejects a BOM.'

$document = New-Object System.Xml.XmlDocument
$document.Load($manifestPath)

$namespaces = New-Object System.Xml.XmlNamespaceManager($document.NameTable)
$namespaces.AddNamespace('f', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$namespaces.AddNamespace('uap5', 'http://schemas.microsoft.com/appx/manifest/uap/windows10/5')
$namespaces.AddNamespace('rescap', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities')

# --- the identity must match the Partner Center reservation ---
# A mismatch is only discovered at submission time, so pin it here.
$identity = $document.SelectSingleNode('/f:Package/f:Identity', $namespaces)
Assert-True ($null -ne $identity) 'The manifest must contain an Identity element.'
Assert-Equal $identity.Name 'tonbiattack.GameAudioManager' 'Identity Name must match the Partner Center reservation.'
Assert-Equal $identity.Publisher 'CN=2F14A66E-02DF-43E2-93E0-5C5900B38D2E' 'Identity Publisher must match the Partner Center reservation.'
Assert-Equal $identity.ProcessorArchitecture 'x64' 'The package is published for x64 only.'
Assert-True ($identity.Version -match '^\d+\.\d+\.\d+\.\d+$') "Identity Version must have four numeric parts, got '$($identity.Version)'."

$deviceFamily = $document.SelectSingleNode('/f:Package/f:Dependencies/f:TargetDeviceFamily', $namespaces)
Assert-True ($null -ne $deviceFamily) 'A TargetDeviceFamily is required.'
Assert-Equal $deviceFamily.MinVersion '10.0.17763.0' 'The supported minimum OS is Windows 10 1809.'

# --- capabilities ---
$fullTrust = $document.SelectSingleNode('/f:Package/f:Capabilities/rescap:Capability[@Name="runFullTrust"]', $namespaces)
Assert-True ($null -ne $fullTrust) 'runFullTrust is required for a WPF desktop app.'

# --- application extensions ---
$application = $document.SelectSingleNode('/f:Package/f:Applications/f:Application', $namespaces)
Assert-True ($null -ne $application) 'The manifest must declare an Application.'
Assert-Equal $application.Executable 'GameAudioManager.exe' 'The Application executable must match the published binary.'

# The startup task must be an *application* extension. A package-level
# <Extensions> block is rejected by makeappx with C00CE014.
$packageLevelExtensions = $document.SelectSingleNode('/f:Package/f:Extensions', $namespaces)
Assert-True ($null -eq $packageLevelExtensions) 'Move <Extensions> inside <Application>; makeappx rejects a package-level uap5 extension.'

$startupExtension = $document.SelectSingleNode(
    '/f:Package/f:Applications/f:Application/f:Extensions/uap5:Extension[@Category="windows.startupTask"]',
    $namespaces)
Assert-True ($null -ne $startupExtension) 'The startup task extension must be declared inside <Application>.'
Assert-Equal $startupExtension.Executable 'GameAudioManager.exe' 'The startup task must launch the app executable.'
Assert-Equal $startupExtension.EntryPoint 'Windows.FullTrustApplication' 'The startup task must use the full-trust entry point.'

$startupTask = $document.SelectSingleNode(
    '/f:Package/f:Applications/f:Application/f:Extensions/uap5:Extension/uap5:StartupTask',
    $namespaces)
Assert-True ($null -ne $startupTask) 'The startup task element is required inside the extension.'
Assert-Equal $startupTask.Enabled 'false' 'The task must start disabled; the in-app toggle enables it.'
Assert-Equal $startupTask.TaskId 'GameAudioManagerStartup' 'The task id must stay stable: existing installs store their state under it.'

# The app reads the id from this constant, so the two must not drift.
$startupSource = Get-Content -Raw -LiteralPath $startupSourcePath
Assert-True ($startupSource -match 'DefaultTaskId\s*=\s*"GameAudioManagerStartup"') 'StartupTaskRegistration.DefaultTaskId must match the manifest TaskId.'

# --- assets referenced by the manifest must exist at the declared sizes ---
Add-Type -AssemblyName System.Drawing
$assetNames = @('Square44x44Logo.png', 'Square150x150Logo.png', 'StoreLogo.png')
foreach ($assetName in $assetNames) {
    $assetPath = Join-Path $repositoryPath "packaging\Package\Assets\$assetName"
    Assert-True (Test-Path -LiteralPath $assetPath -PathType Leaf) "The manifest references $assetName but it is missing."
}

$square44 = [System.Drawing.Image]::FromFile((Join-Path $repositoryPath 'packaging\Package\Assets\Square44x44Logo.png'))
$square150 = [System.Drawing.Image]::FromFile((Join-Path $repositoryPath 'packaging\Package\Assets\Square150x150Logo.png'))
$storeLogo = [System.Drawing.Image]::FromFile((Join-Path $repositoryPath 'packaging\Package\Assets\StoreLogo.png'))
try {
    Assert-Equal $square44.Width 44 'Square44x44Logo.png must be 44x44.'
    Assert-Equal $square44.Height 44 'Square44x44Logo.png must be 44x44.'
    Assert-Equal $square150.Width 150 'Square150x150Logo.png must be 150x150.'
    Assert-Equal $square150.Height 150 'Square150x150Logo.png must be 150x150.'
    Assert-Equal $storeLogo.Width 50 'StoreLogo.png must be 50x50.'
    Assert-Equal $storeLogo.Height 50 'StoreLogo.png must be 50x50.'
}
finally {
    $square44.Dispose()
    $square150.Dispose()
    $storeLogo.Dispose()
}

# --- the packing script must default to the reserved publisher ---
$packScript = Get-Content -Raw -LiteralPath $packScriptPath
Assert-True ($packScript -match 'CN=2F14A66E-02DF-43E2-93E0-5C5900B38D2E') 'pack-msix.ps1 must default to the reserved Publisher.'

Write-Host 'PASS: MSIX manifest tests'
