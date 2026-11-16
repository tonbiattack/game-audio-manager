param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Device,
    [string]$ProcessName = 'ShirenTheWanderer6',
    [string]$SvclPath,
    [ValidateRange(1, 3600)][int]$IntervalSeconds = 5
)

# Compatibility wrapper: the implementation lives in legacy\shiren6\.
$parameters = @{
    Device = $Device
    ProcessName = $ProcessName
    IntervalSeconds = $IntervalSeconds
}
if (-not [string]::IsNullOrWhiteSpace($SvclPath)) {
    $parameters.SvclPath = $SvclPath
}

& "$PSScriptRoot\legacy\shiren6\watch-shiren-output.ps1" @parameters
exit $LASTEXITCODE
