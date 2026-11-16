param(
    [string]$Device,
    [string]$ProcessName = "ShirenTheWanderer6",
    [string]$SvclPath,
    [switch]$Reset,
    [switch]$List,
    [switch]$RawList
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\GameAudio.Common.ps1"

if ([string]::IsNullOrWhiteSpace($SvclPath)) {
    $SvclPath = Get-GameAudioSvclPath -RepositoryPath $PSScriptRoot
}

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
