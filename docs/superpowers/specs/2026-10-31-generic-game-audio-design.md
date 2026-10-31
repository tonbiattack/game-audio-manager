# Generic game audio controls — design

## Intent

Issue #5 makes the current Shiren 6-only PowerShell commands usable for any game process while keeping existing Shiren commands working unchanged. This is the dependency for configuration-based multi-game support.

## Goals

- Add generic commands for process detection, mute toggling, and output-device changes using `-ProcessName`.
- Move shared process-name normalization, lookup, and human-readable error generation into `lib/`.
- Remove Shiren-specific text from generic command output and errors.
- Preserve the old Shiren command paths as wrappers, retaining their existing defaults and options.

## Non-goals

- No `games.json`, multi-game monitoring, RimWorld-specific settings, or multi-endpoint/multi-PID audio-session behavior (Issues #6–#9).
- Do not change the user’s existing `docs/audio-output-investigation.md` work.

## Constraints

- Support Windows PowerShell 5.1 and PowerShell 7.
- Preserve `svcl.exe` as the output-routing backend.
- Keep all external side effects in entry-point scripts; library code only resolves data and formats errors.

## Approaches

1. Modify each current script in place. This minimizes new files but leaves duplicated process lookup and keeps generic code coupled to Shiren names.
2. Create generic entry points plus a focused `lib/GameAudio.Common.ps1`, then turn Shiren scripts into default-providing wrappers. **Selected:** it fulfills the explicit shared-library and compatibility requirements, and provides stable entry points for the next phase.

## Design

`lib/GameAudio.Common.ps1` exports `ConvertTo-GameProcessName`, `Get-GameProcesses`, and `Resolve-GameProcess`. They normalize an optional `.exe` suffix, return all matching processes, and throw errors that name the requested process and point to `detect-game-process.ps1`.

`detect-game-process.ps1` accepts a mandatory `-ProcessName`, writes matching process details, and on absence shows the visible-process diagnostic without referring to a particular game. `set-game-output.ps1` uses the shared resolver, preserves `-List`, `-RawList`, `-Reset`, and `-SvclPath`, and sends the resolved executable name to `svcl.exe`. `toggle-game-mute.ps1` accepts a mandatory `-ProcessName`; it reuses the Core Audio implementation but reports generic process/session errors.

The old `detect-shiren-process.ps1`, `set-shiren-output.ps1`, and `toggle-shiren-mute.ps1` remain public compatibility wrappers. Each supplies `ShirenTheWanderer6` unless a caller explicitly overrides it, then delegates to the generic command. Watch-script migration is deferred because the issue calls out the three direct commands and Phase 3 owns multi-game monitoring.

## Verification

Pester tests will mock process lookup and `svcl.exe` invocation to demonstrate generic process-name normalization, clear absence errors, generic output command behavior, and Shiren wrapper delegation. The existing watcher tests remain part of the full suite. Hardware/Core Audio behavior is documented as a manual Windows check because it requires a live audio session.
