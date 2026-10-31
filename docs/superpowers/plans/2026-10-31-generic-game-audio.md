# Generic game audio controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make process detection, muting, and output routing work for arbitrary game process names while preserving Shiren commands.

**Architecture:** Put process-name normalization, lookup, and error construction in one PowerShell dot-sourced library. Generic entry points consume that library; old Shiren-named commands forward their current default and user options to the generic commands.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7, Pester, NirSoft SoundVolumeCommandLine.

**Spec:** `docs/superpowers/specs/2026-10-31-generic-game-audio-design.md`

## Global Constraints

- Keep `svcl.exe` as the output-routing backend.
- Support Windows PowerShell 5.1 and PowerShell 7.
- Keep side effects in entry-point scripts; the `lib/` module only resolves and formats data.
- Do not implement configuration, multi-game monitoring, or multi-endpoint/multi-PID behavior.
- Preserve user changes outside this worktree.

## Review Focus

- `ProcessName` supplied with `.exe` must resolve identically to the bare name.
- Missing processes must produce a generic message that identifies the requested name.
- The Shiren wrappers must retain no-argument behavior and pass all supported options through.
- `-List` and `-RawList` must not require a running game process.
- A failed `svcl.exe` invocation must still expose its exit code.

### Task 1: Shared process-resolution library

**Files:**
- Create: `lib/GameAudio.Common.ps1`
- Test: `tests/game-audio-common.tests.ps1`

**Interfaces:**
- Produces: `ConvertTo-GameProcessName([string] $ProcessName) -> [string]`, `Get-GameProcesses([string] $ProcessName) -> process[]`, and `Resolve-GameProcess([string] $ProcessName) -> process`.

- [ ] **Step 1: Write failing tests** for bare and `.exe`-suffixed process names, all matching processes, and a generic missing-process error.
- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File tests/game-audio-common.tests.ps1`

Expected: FAIL because the library does not exist.

- [ ] **Step 3: Implement the library functions** in `lib/GameAudio.Common.ps1` using `System.IO.Path::GetFileNameWithoutExtension` and `Get-Process -ErrorAction SilentlyContinue`; resolve the first match and include the requested name in missing-process errors.
- [ ] **Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -File tests/game-audio-common.tests.ps1`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/GameAudio.Common.ps1 tests/game-audio-common.tests.ps1
git commit -m "feat: add shared game process resolution"
```

### Task 2: Generic detect and output commands with Shiren compatibility wrappers

**Files:**
- Create: `detect-game-process.ps1`
- Create: `set-game-output.ps1`
- Modify: `detect-shiren-process.ps1`
- Modify: `set-shiren-output.ps1`
- Test: `tests/detect-game-process.tests.ps1`
- Test: `tests/set-game-output.tests.ps1`

**Interfaces:**
- Consumes: Task 1 library functions.
- Produces: `detect-game-process.ps1 -ProcessName <string>` and `set-game-output.ps1 -ProcessName <string> [-Device <string>] [-Reset] [-List] [-RawList] [-SvclPath <string>]`.

- [ ] **Step 1: Write failing tests** for game-neutral diagnostics, generic `svcl.exe` invocation using `SomeGame.exe`, Shiren wrapper defaults, and list commands operating without a running process.
- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File tests/detect-game-process.tests.ps1; pwsh -NoProfile -File tests/set-game-output.tests.ps1`

Expected: FAIL because the generic commands and wrapper forwarding do not exist.

- [ ] **Step 3: Implement generic commands and wrappers** by moving the existing output behavior to `set-game-output.ps1`, dot-sourcing the library, and forwarding wrapper parameters with `@PSBoundParameters`.
- [ ] **Step 4: Run output command tests**

Run: `pwsh -NoProfile -File tests/detect-game-process.tests.ps1; pwsh -NoProfile -File tests/set-game-output.tests.ps1; pwsh -NoProfile -File tests/set-shiren-output.tests.ps1; powershell.exe -NoProfile -File tests/set-shiren-output-windows-powershell.tests.ps1`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add detect-game-process.ps1 set-game-output.ps1 detect-shiren-process.ps1 set-shiren-output.ps1 tests/
git commit -m "feat: add generic process and output commands"
```

### Task 3: Generic mute command and Shiren wrapper

**Files:**
- Create: `toggle-game-mute.ps1`
- Modify: `toggle-shiren-mute.ps1`
- Test: `tests/toggle-game-mute.tests.ps1`

**Interfaces:**
- Consumes: `Resolve-GameProcess` from Task 1.
- Produces: `toggle-game-mute.ps1 -ProcessName <string>`; the wrapper defaults it to `ShirenTheWanderer6`.

- [ ] **Step 1: Write failing tests** for mandatory process selection, generic user-facing wording, and wrapper delegation.
- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File tests/toggle-game-mute.tests.ps1`

Expected: FAIL because `toggle-game-mute.ps1` does not exist.

- [ ] **Step 3: Move the Core Audio implementation to the generic command**, resolve the named game process through the library, and use process-neutral session/console messages; create a thin Shiren wrapper.
- [ ] **Step 4: Run mute tests**

Run: `pwsh -NoProfile -File tests/toggle-game-mute.tests.ps1`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add toggle-game-mute.ps1 toggle-shiren-mute.ps1 tests/toggle-game-mute.tests.ps1
git commit -m "feat: add generic game mute command"
```

### Task 4: Documentation and full verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: all generic and compatibility commands from Tasks 1–3.
- Produces: documented generic invocation plus unchanged Shiren examples.

- [ ] **Step 1: Add README examples** for generic process detection, mute toggling, and output routing, followed by a compatibility note for existing Shiren commands.
- [ ] **Step 2: Run the complete automated suite**

Run: `Get-ChildItem tests -Filter '*.tests.ps1' | ForEach-Object { & pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }`

Expected: all tests PASS.

- [ ] **Step 3: Run PowerShell syntax checks**

Run: `Get-ChildItem -Recurse -Filter '*.ps1' | ForEach-Object { $tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 } }`

Expected: exit code 0.

- [ ] **Step 4: Record manual Windows verification steps** in README: start a game process, run mute twice, set an active output device, reset to Windows default, and confirm that a missing process reports the requested name.
- [ ] **Step 5: Commit**

```powershell
git add README.md
git commit -m "docs: document generic game audio commands"
```

