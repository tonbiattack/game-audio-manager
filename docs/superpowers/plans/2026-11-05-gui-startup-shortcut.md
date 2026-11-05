# GUI Startup Shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Register and remove a per-user Startup shortcut that launches Game Audio Manager GUI after logon.

**Architecture:** A focused library computes the `.lnk` definition and creates or removes it with `WScript.Shell`. A thin root script exposes install/remove commands; tests inject a temporary startup directory so no user shortcut is touched during testing.

**Tech Stack:** Windows PowerShell 5.1+, WScript.Shell COM, repository PowerShell test convention.

**Spec:** `docs/superpowers/specs/2026-11-05-gui-startup-shortcut-design.md`

## Global Constraints

- Register only the current user's Startup folder by default.
- The shortcut must launch the GUI visibly and must not start a background watcher.
- `-Remove` may delete only the named Game Audio Manager shortcut.

## Review Focus

- Startup folder injection: test registration in a temporary directory, never the real Startup folder.
- Absolute paths: target, script argument, and working directory must remain valid from any launch location.
- Re-registration: creating the shortcut twice must update the same file without creating duplicates.
- Removal: a missing shortcut must be a successful no-op.

---

### Task 1: Startup shortcut library and command

**Files:**
- Create: `lib/GameAudio.Startup.ps1`
- Create: `Install-GameAudioManagerStartup.ps1`
- Create: `tests/game-audio-startup.tests.ps1`

**Interfaces:**
- Produces `Get-GameAudioStartupShortcutDefinition -RepositoryPath -StartupDirectory`, `Set-GameAudioStartupShortcut -RepositoryPath -StartupDirectory`, and `Remove-GameAudioStartupShortcut -StartupDirectory`.

- [ ] **Step 1: Write failing tests**

Test a temporary Startup directory for the expected `Game Audio Manager.lnk` definition, creation/update, and safe missing-file removal.

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\game-audio-startup.tests.ps1`

Expected: FAIL because the startup library is missing.

- [ ] **Step 3: Implement the library and wrapper script**

Use `WScript.Shell.CreateShortcut`; point `TargetPath` to `powershell.exe`, add `-NoProfile -ExecutionPolicy Bypass -File` plus the absolute GUI script path, and set the working directory to the repository path.

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\game-audio-startup.tests.ps1`

Expected: `PASS: game-audio-startup tests`.

- [ ] **Step 5: Commit**

```powershell
git add lib/GameAudio.Startup.ps1 Install-GameAudioManagerStartup.ps1 tests/game-audio-startup.tests.ps1
git commit -m "feat: add GUI startup shortcut command"
```

### Task 2: Documentation and full verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes the root command from Task 1.

- [ ] **Step 1: Document installation and removal**

Add the two exact commands to the GUI section and state that it opens the GUI after the current user logs on.

- [ ] **Step 2: Run full suite and parser checks**

Run all `tests/*.tests.ps1`, then parse every `.ps1` with both Windows PowerShell and PowerShell 7.

- [ ] **Step 3: Commit**

```powershell
git add README.md docs/superpowers/specs/2026-11-05-gui-startup-shortcut-design.md docs/superpowers/plans/2026-11-05-gui-startup-shortcut.md
git commit -m "docs: document GUI startup shortcut"
```
