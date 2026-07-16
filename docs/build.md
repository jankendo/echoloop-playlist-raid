# Windows build

## Prerequisites

- Godot Engine 4.7.1 Standard and matching export templates.
- Python 3.11 for fixtures and the local worker runtime.
- FFmpeg/ffprobe 8.1.2 and rcedit 2.0.0 in the managed tools directory.
- yt-dlp verified with tools/install_ytdlp.ps1 -Mode Verify.

## Command

Run tools/build_windows.ps1. It executes Python tests and Godot headless tests
before exporting Windows Desktop and applying ProductName, FileDescription,
CompanyName, FileVersion, and ProductVersion with rcedit.

Phase 4.2 expects PE version 0.5.0.0 and output
dist/windows/ECHOLOOP_PLAYLIST_RAID.exe. If templates or rcedit are absent,
the script fails and records the exact environment-limited reason.

The Windows executable does not bundle Python, FFmpeg, PyTorch, Beat This!, or
librosa. Built-in and already registered songs remain playable offline; import
screens show a recovery message when optional worker dependencies are missing.
