# Third-party notices

## Desktop app (.NET / WPF)

The desktop application does not bundle any third-party executables. Per-application
audio routing uses the Windows audio policy API, and device/session control uses the
Windows Core Audio API, both provided by the operating system.

## PowerShell version (legacy)

The PowerShell version bundles the following unmodified files from the 64-bit
SoundVolumeCommandLine v1.28 distribution, located in `vendor/svcl/`:

- `vendor/svcl/svcl.exe`
- `vendor/svcl/svcl.chm`
- `vendor/svcl/readme.txt`

SoundVolumeCommandLine is Copyright (c) 2021-2026 Nir Sofer and is licensed
as freeware. Its distribution terms are separate from this repository's MIT
license: redistribution must be free of charge, non-commercial, and include
all files in the distribution package without modification.

See the official project page and full terms:
<https://www.nirsoft.net/utils/sound_volume_command_line.html>

These files are **not** used or redistributed by the desktop app.

## New Fonts / icons

The desktop app uses only the built-in Windows theme resources and system icons.

## Repository licence

The PowerShell source, C# source and documentation authored for Game Audio Manager
are licensed under the repository's [MIT License](LICENSE).
