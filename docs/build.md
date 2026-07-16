# Windows build

## Prerequisites

- Godot Engine 4.7.1 Standard Windows build (`.tools/godot/4.7.1-stable` after bootstrap)
- Installed Windows export templates for the same Godot version
- Python 3.11 for fixture generation and the optional local worker runtime
- FFmpeg and ffprobe from `.tools/ffmpeg/8.1.2` or PATH for local audio import
- rcedit 2.0.0 from `.tools/rcedit/2.0.0` for Windows version resources

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

Phase 4's managed build prepends the versioned `rcedit-x64.exe` to PATH and applies
ProductName, FileDescription, CompanyName, FileVersion, and ProductVersion after export.
If the managed rcedit is absent the script fails instead of reporting a
metadata-complete build. The project icon is `godot/icon.svg`.

The Windows executable does not bundle Python, FFmpeg, PyTorch, Beat This!, or
librosa. Without those tools, the executable keeps the built-in and already registered
songs playable; the YouTube/analysis screens report the missing environment.
