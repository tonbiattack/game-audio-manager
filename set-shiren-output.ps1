param(
    [string]$Device,
    [string]$ProcessName = "ShirenTheWanderer6",
    [string]$SvclPath = "$PSScriptRoot\svcl.exe",
    [switch]$Reset,
    [switch]$List,
    [switch]$RawList
)

$parameters = @{
    ProcessName = $ProcessName
    SvclPath = $SvclPath
    Reset = $Reset
    List = $List
    RawList = $RawList
}
if ($PSBoundParameters.ContainsKey('Device')) {
    $parameters.Device = $Device
}

& "$PSScriptRoot\set-game-output.ps1" @parameters
exit $LASTEXITCODE
