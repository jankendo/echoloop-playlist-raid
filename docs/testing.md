# Testing

## Python

`tools/run_python_tests.ps1` sets `PYTHONPATH=worker/src` and runs pytest. It then runs
ruff and mypy when those commands are available. The tests cover request validation,
atomic status writing, cancellation, JSONL logging, deterministic WAV generation,
schemas, health-check completion, safe ffprobe/FFmpeg boundaries, variable tempo,
fallback tracking, deterministic chart generation, SongPack atomicity, and user
override inputs. `tools/run_phase3_e2e.py` exercises the real synthetic WAV through
probe, conversion, analysis, four charts, and SongPack commit.

## Godot

`tools/run_godot_tests.ps1` locates Godot 4.x from PATH or `-GodotPath` and runs
`godot/tests/run_all.gd` headlessly. The runner checks the clock contract, judgement
boundaries, score/rank, chart validation, EchoTrack timing/lifetime, Corruption rules,
and deterministic game-session outcomes.

## Manual smoke checklist

1. Start the game and select `PLAY TEST SONG`.
2. Confirm D/F/J/K lane response and TAP/HOLD/CHORD feedback.
3. Let a phrase pass with misses; confirm Corruption appears in the next phrase.
4. Play a phrase accurately; confirm a visible EchoTrack appears from the next phrase.
5. Let the song finish; confirm Results, RETRY, and MAIN MENU.
6. Open Import Local Audio with a local fixture file; confirm progress and
   cancellation behavior.
7. Open Song Library / Beat Check; confirm waveform, beats, downbeats, preview,
   BPM/offset override, regeneration, and offline playback.
8. Open Settings and Diagnostics; save settings and run the local worker health check.
