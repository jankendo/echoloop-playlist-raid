# yt-dlp update and rollback

Updates are explicit because YouTube extractor behavior changes independently
of the game. Run Verify before and after an update and keep the generated
.runtime/reports/ytdlp-install.json with the environment report.

Use Update for the tested pre-release channel. Use Rollback with an exact
version from a known-good report:

pwsh -File tools/install_ytdlp.ps1 -Mode Rollback -Version 2026.06.09

Rollback is package-scoped and does not change Godot, Deno, FFmpeg, models, or
the active song library. A failed install exits nonzero and writes a failed
report; it never claims the runtime is repaired.
