# Phase 4.1 implementation plan

## Goal

Make the Windows yt-dlp runtime repeatable and remove the obsolete rights prompt
from the execution contract while preserving URL, path, credential, host, and
process safety boundaries.

## Deliverables

- tools/install_ytdlp.ps1 with Install, Repair, Verify, Update, and Rollback.
- tools/ytdlp.ps1 resolving the active Python environment from current.json.
- locked yt-dlp, yt-dlp-ejs, Deno, FFmpeg, and ffprobe verification.
- legacy request compatibility that ignores the old confirmation field without
  emitting it in new status, result, or SongPack data.
- fake-adapter tests for no field, false, and true legacy values.

## Exit criteria

The managed Python API and CLI report the same version, yt-dlp-ejs imports,
Deno/FFmpeg/ffprobe paths exist, the wrapper works, and the full Python/Godot
test suites pass. Online YouTube smoke remains an explicit manual workflow.
