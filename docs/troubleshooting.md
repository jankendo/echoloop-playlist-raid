# Troubleshooting

## FFmpeg, Deno, or yt-dlp is missing

Run tools/install_ytdlp.ps1 -Mode Verify and tools/verify_toolchain.ps1. If a
managed path is missing, run tools/bootstrap_all.ps1 -Mode Repair. Verify reads
the active current.json and does not install anything.

## F/J input does not judge a legacy chart

DUO projection is the default. Use SETTINGS > CLASSIC 4-LANE for the original
D/F/J/K positions, or ensure the chart is loaded through ChartLoader instead of
reading source lane values directly.

## YouTube import fails

Check the canonical YouTube URL, the Deno path, and the worker status message.
Credential fields, proxy options, arbitrary headers, file URLs, non-YouTube
hosts, and traversal paths are rejected by design. No network access is needed
for the built-in fixture.

## Pause or return-to-title behaves unexpectedly

Pause stops AudioClock and the audio stream. Return-to-title intentionally does
not save the current result, but SongPack and settings persist. Use the
confirmation dialog's CANCEL action to remain in gameplay.
