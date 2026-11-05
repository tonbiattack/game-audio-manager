# Configurable game-audio GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users add games through JSON configuration and change each game's audio output from a small Windows GUI.

**Architecture:** A validation-focused configuration library owns JSON loading and preferred-device selection. CLI commands resolve `-Game` through that library, while a WinForms script invokes the existing output command in a child PowerShell process and renders its result.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7, Windows Forms, Pester-style PowerShell scripts, NirSoft SoundVolumeCommandLine.

**Spec:** `docs/superpowers/specs/2026-11-05-configurable-game-audio-gui-design.md`

## Global Constraints

- `config/games.json` is personal and must never be committed; `config/games.example.json` is the committed template.
- A game definition requires unique non-empty `name` and `processName`, a non-empty `outputDevices` array, and boolean `enabled`.
- Device priority is the first active candidate in `outputDevices` order.
- GUI output changes delegate to `set-game-output.ps1`; no second audio-control implementation.
- Support Windows PowerShell 5.1 and PowerShell 7.
- GUI does not edit configuration, monitor games, or run at login.

## Review Focus

- Malformed JSON, duplicate names, duplicate process names, empty candidates, and non-boolean `enabled` must identify the invalid field.
- `-Game` selection must reject disabled or unknown games without silently targeting another process.
- List operations must still work without a selected/running game.
- The GUI must not invoke a child output command when the selected game is not running or no active preferred candidate exists.
- The output command’s default `svcl.exe` path must work from Windows PowerShell 5.1.

### Task 1: Configuration schema and validation library

**Files:**
- Create: `config/games.example.json`
- Create: `lib/GameAudio.Config.ps1`
- Modify: `.gitignore`
- Test: `tests/game-audio-config.tests.ps1`

**Interfaces:**
- Produces: `Get-GameConfiguration([string] $Path)`, `Resolve-ConfiguredGame([object[]] $Games, [string] $GameName)`, and `Get-PreferredConfiguredDevice([string[]] $Candidates, [string[]] $ActiveDevices)`.

- [ ] Write failing tests for valid Shiren 6, Slay the Spire 2, and Balatro definitions; missing fields; duplicate names/processes; invalid enabled values; and candidate priority.
- [ ] Run `pwsh -NoProfile -File tests/game-audio-config.tests.ps1` and confirm failure because the library and example config are absent.
- [ ] Implement the config template, ignore personal `config/games.json`, and implement validation/selection functions.
- [ ] Run `pwsh -NoProfile -File tests/game-audio-config.tests.ps1` and confirm PASS.
- [ ] Commit with `feat: add game configuration`.

### Task 2: Config-aware output command and PowerShell 5.1 path repair

**Files:**
- Modify: `set-game-output.ps1`
- Modify: `watch-shiren-output.ps1`
- Test: `tests/set-game-output.tests.ps1`
- Test: `tests/set-game-output-windows-powershell.tests.ps1`

**Interfaces:**
- Consumes: configuration library from Task 1.
- Produces: `set-game-output.ps1 -Game <string> [-ConfigPath <string>]` and correct default `SvclPath` after the param block.

- [ ] Write failing tests for `-Game` resolving its configured process and rejecting an unknown/disabled game; add a Windows PowerShell test that exercises the default `SvclPath`.
- [ ] Run the named tests and confirm failure.
- [ ] Resolve `SvclPath` after parameter binding, add `-Game`/`-ConfigPath` with mutually exclusive explicit process behavior, and make the watcher resolve its default path after binding.
- [ ] Run the named tests plus existing output tests under PowerShell 7 and Windows PowerShell 5.1; confirm PASS.
- [ ] Commit with `feat: resolve games from configuration`.

### Task 3: GUI state and WinForms entry point

**Files:**
- Create: `lib/GameAudio.Gui.ps1`
- Create: `game-audio-manager.ps1`
- Test: `tests/game-audio-gui.tests.ps1`

**Interfaces:**
- Consumes: Task 1 config functions and Task 2 command interface.
- Produces: `Get-GameAudioGuiState`, `New-GameAudioApplyRequest`, and a WinForms window with game/device selectors, action buttons, refresh, and status.

- [ ] Write failing tests for running/not-running game state, preferred-device selection, disabled games omitted from selectable state, and apply requests refusing invalid state.
- [ ] Run `pwsh -NoProfile -File tests/game-audio-gui.tests.ps1` and confirm failure because the GUI library is absent.
- [ ] Implement pure state/request functions, then the WinForms UI that launches `set-game-output.ps1` as a child process and displays its result.
- [ ] Run `pwsh -NoProfile -File tests/game-audio-gui.tests.ps1` and confirm PASS; parse the entry point with both PowerShell versions.
- [ ] Commit with `feat: add configurable game audio GUI`.

### Task 4: Documentation, personal configuration, and end-to-end verification

**Files:**
- Modify: `README.md`
- Create: local ignored `config/games.json` from the example (not committed)

**Interfaces:**
- Consumes: all prior configuration, command, and GUI behavior.
- Produces: setup steps, add-game instructions, and manual GUI test procedure.

- [ ] Document copying the example configuration, adding a game, setting device priority, and launching the GUI.
- [ ] Create the local personal configuration for the current games and configured device priority without staging it.
- [ ] Run every `tests/*.tests.ps1`, parse every PowerShell source file in both PowerShell 7 and Windows PowerShell 5.1, and run `git diff --check`; confirm PASS.
- [ ] Manually open the GUI, confirm configured games appear, and use Balatro to apply a preferred device; record the observable result in the final report.
- [ ] Commit documentation only with `docs: document configurable game audio GUI`.
