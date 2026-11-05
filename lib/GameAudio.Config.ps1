Set-StrictMode -Version Latest

function Test-GameConfigurationText {
    param([object]$Value, [string]$Field, [string]$GameName)

    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) {
        throw "Game '$GameName' has an invalid $Field value."
    }
}

function Get-GameConfiguration {
    param([Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Game configuration was not found: $Path"
    }

    try {
        $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Game configuration is not valid JSON: $Path. $($_.Exception.Message)"
    }

    if ($null -eq $config -or $null -eq $config.games) {
        throw "Game configuration must contain a games array: $Path"
    }

    $names = @{}
    $processNames = @{}
    $validatedGames = @()

    foreach ($game in @($config.games)) {
        if ($null -eq $game) { throw 'Game configuration contains an empty game definition.' }

        Test-GameConfigurationText -Value $game.name -Field 'name' -GameName '<unknown>'
        Test-GameConfigurationText -Value $game.processName -Field 'processName' -GameName $game.name

        if ($names.ContainsKey($game.name.ToLowerInvariant())) {
            throw "Game configuration contains a duplicate game name: $($game.name)"
        }
        if ($processNames.ContainsKey($game.processName.ToLowerInvariant())) {
            throw "Game configuration contains a duplicate processName: $($game.processName)"
        }
        if ($game.enabled -isnot [bool]) {
            throw "Game '$($game.name)' has an invalid enabled value; use true or false."
        }
        $devices = @($game.outputDevices)
        if ($devices.Count -eq 0) {
            throw "Game '$($game.name)' must define at least one outputDevices value."
        }
        foreach ($device in $devices) {
            Test-GameConfigurationText -Value $device -Field 'outputDevices' -GameName $game.name
        }

        $names[$game.name.ToLowerInvariant()] = $true
        $processNames[$game.processName.ToLowerInvariant()] = $true
        $validatedGames += [PSCustomObject]@{
            Name = $game.name
            ProcessName = $game.processName
            OutputDevices = [string[]]$devices
            Enabled = [bool]$game.enabled
        }
    }

    if ($validatedGames.Count -eq 0) { throw "Game configuration has no games: $Path" }
    return $validatedGames
}

function Resolve-ConfiguredGame {
    param(
        [Parameter(Mandatory = $true)][object[]]$Games,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$GameName
    )

    $matches = @($Games | Where-Object { $_.Name -ieq $GameName })
    if ($matches.Count -eq 0) { throw "Configured game was not found: $GameName" }
    $game = $matches[0]
    if (-not $game.Enabled) { throw "Configured game is disabled: $GameName" }
    return $game
}

function Get-PreferredConfiguredDevice {
    param(
        [Parameter(Mandatory = $true)][string[]]$Candidates,
        [Parameter(Mandatory = $true)][string[]]$ActiveDevices
    )

    foreach ($candidate in $Candidates) {
        if ($ActiveDevices -contains $candidate) { return $candidate }
    }
    return $null
}
