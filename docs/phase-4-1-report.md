# Phase 4.1 report

Implemented the deterministic yt-dlp runtime installer and wrapper, locked the
tested nightly plus stable fallback, and removed the old confirmation gate from
current execution and UI. Legacy payloads remain compatible by ignoring the
old field at validation; new outputs omit it.

Verified locally on Windows:

- yt-dlp Python API and python -m yt_dlp: 2026.07.14.233956
- yt-dlp-ejs: 0.8.0
- Deno: 2.8.1
- FFmpeg/ffprobe: 8.1.2
- targeted YouTube tests: 7 passed

Real online smoke is still explicit and was not run in normal CI.
