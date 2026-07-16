# Windows build

## Prerequisites

- Godot Engine 4.7.1 Standard Windows build
- Installed Windows export templates for the same Godot version
- Python 3.11 for fixture generation and the optional local worker runtime
- FFmpeg and ffprobe on PATH for local audio import

## Command

```powershell
pwsh -File tools/build_windows.ps1
```

The script runs Python tests and Godot headless tests before invoking:

```powershell
godot.exe --headless --path godot --export-release "Windows Desktop" ..\dist\windows\ECHOLOOP_PLAYLIST_RAID.exe
```

The expected output is `dist/windows/ECHOLOOP_PLAYLIST_RAID.exe` plus its `.pck` when
the export is not embedded. If templates are unavailable, the script writes the exact
command and error to this document and reports the build as environment-limited.

Local verification on 2026-07-16 used the available `Godot_v4.2-stable_win64_console.exe`
and produced the embedded-PCK executable. This is a compatibility smoke result, not a
claim that Godot 4.7.1 has been locally installed. The export also warned that `rcedit`
was unavailable while setting Windows file-version metadata; the executable was still
created and launched.

The Windows executable does not bundle Python, FFmpeg, PyTorch, Beat This!, or
librosa in Phase 3. Without those tools, the executable keeps the built-in and
already registered songs playable and the Import/Diagnostics screens report the
missing environment.
