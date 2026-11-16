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
        if ($game.outputDevices -isnot [System.Array]) {
            throw "Game '$($game.name)' must define outputDevices as an array."
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

    # An empty games array is a valid state; a rule can be registered later by the GUI.
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

function Get-GameAudioRuleProcessName {
    param([Parameter(Mandatory = $true)][string]$ProcessName)

    return [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
}

function Publish-GameAudioRuleConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Configuration
    )

    $json = $Configuration | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
    return $Configuration
}

# --- priority device list editing ---
#
# The GUI edits the ordered candidate list before saving it. These helpers keep
# the list valid: no blanks, no duplicates, and a stable order.

function Add-GameAudioPriorityDevice {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Devices,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Device
    )

    $current = @($Devices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $trimmed = $Device.Trim()
    foreach ($existing in $current) {
        if ([string]::Equals($existing, $trimmed, [System.StringComparison]::OrdinalIgnoreCase)) {
            # Already a candidate; keep the existing position and spelling.
            return [string[]]$current
        }
    }
    return [string[]](@($current) + $trimmed)
}

function Remove-GameAudioPriorityDevice {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Devices,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Device
    )

    $current = @($Devices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return [string[]]@($current | Where-Object {
        -not [string]::Equals($_, $Device, [System.StringComparison]::OrdinalIgnoreCase)
    })
}

# Moves the device one position toward the front (higher priority).
function Move-GameAudioPriorityDeviceUp {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Devices,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Device
    )

    return [string[]](Move-GameAudioPriorityDevice -Devices $Devices -Device $Device -Offset -1)
}

# Moves the device one position toward the back (lower priority).
function Move-GameAudioPriorityDeviceDown {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Devices,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Device
    )

    return [string[]](Move-GameAudioPriorityDevice -Devices $Devices -Device $Device -Offset 1)
}

function Move-GameAudioPriorityDevice {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Devices,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Device,
        [Parameter(Mandatory = $true)][ValidateSet(-1, 1)][int]$Offset
    )

    $current = @($Devices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $index = -1
    for ($i = 0; $i -lt $current.Count; $i++) {
        if ([string]::Equals($current[$i], $Device, [System.StringComparison]::OrdinalIgnoreCase)) {
            $index = $i
            break
        }
    }
    if ($index -lt 0) { return [string[]]$current }

    $target = $index + $Offset
    # Moving past either end is a no-op rather than an error.
    if ($target -lt 0 -or $target -ge $current.Count) { return [string[]]$current }

    $reordered = @($current)
    $reordered[$index] = $current[$target]
    $reordered[$target] = $current[$index]
    return [string[]]$reordered
}

function Set-GameAudioRule {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName,
        [string]$Name,
        [string[]]$OutputDevices,
        [bool]$Enabled = $true,
        # When set, OutputDevices replaces the stored list instead of being
        # merged in front of it. The GUI uses this to save an edited order.
        [switch]$ReplaceDevices
    )

    $processName = Get-GameAudioRuleProcessName -ProcessName $ProcessName
    $config = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Game configuration is not valid JSON: $Path. $($_.Exception.Message)"
        }
    }
    if ($null -eq $config) { $config = [PSCustomObject]@{ games = @() } }

    $games = @(@($config.games) | Where-Object { $null -ne $_ })
    $selectedDevices = @()
    if ($null -ne $OutputDevices) {
        $selectedDevices = @($OutputDevices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $displayName = $processName
    if (-not [string]::IsNullOrWhiteSpace($Name)) { $displayName = $Name }
    $integrationBase = @()

    $existingRule = $games | Where-Object {
        (Get-GameAudioRuleProcessName -ProcessName ([string]$_.processName)) -ieq $processName
    } | Select-Object -First 1

    if ($null -eq $existingRule) {
        if ($selectedDevices.Count -eq 0) {
            throw "Specify at least one output device to register '$processName'."
        }
    }
    else {
        $integrationBase = @()
        if ($null -ne $existingRule.outputDevices) {
            $integrationBase = @($existingRule.outputDevices | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
        if ([string]::IsNullOrWhiteSpace($Name)) { $displayName = [string]$existingRule.name }
    }

    if ($ReplaceDevices) {
        if ($selectedDevices.Count -eq 0) {
            throw "Specify at least one output device to register '$processName'."
        }
        $mergedDevices = @($selectedDevices)
    }
    else {
        $mergedDevices = @($selectedDevices) + @($integrationBase | Where-Object { $selectedDevices -notcontains $_ })
    }

    if ($null -eq $existingRule) {
        $rule = [PSCustomObject]@{
            name = $displayName
            processName = $processName
            outputDevices = [string[]]$mergedDevices
            enabled = [bool]$Enabled
        }
        $config.games = @($games) + $rule
    }
    else {
        $existingRule | Add-Member -MemberType NoteProperty -Name 'name' -Value $displayName -Force
        $existingRule | Add-Member -MemberType NoteProperty -Name 'processName' -Value $processName -Force
        $existingRule | Add-Member -MemberType NoteProperty -Name 'outputDevices' -Value ([string[]]$mergedDevices) -Force
        $existingRule | Add-Member -MemberType NoteProperty -Name 'enabled' -Value ([bool]$Enabled) -Force
        $rule = $existingRule
        $config.games = @($games)
    }

    $null = Publish-GameAudioRuleConfiguration -Path $Path -Configuration $config
    return $rule
}

function Remove-GameAudioRule {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ProcessName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Game configuration was not found: $Path"
    }
    try {
        $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Game configuration is not valid JSON: $Path. $($_.Exception.Message)"
    }

    $games = @(@($config.games) | Where-Object { $null -ne $_ })
    $processName = Get-GameAudioRuleProcessName -ProcessName $ProcessName
    $remaining = @($games | Where-Object {
        (Get-GameAudioRuleProcessName -ProcessName ([string]$_.processName)) -ine $processName
    })
    if ($remaining.Count -eq $games.Count) {
        throw "Configured rule was not found: $processName"
    }

    $config.games = $remaining
    $null = Publish-GameAudioRuleConfiguration -Path $Path -Configuration $config
    return $remaining
}
