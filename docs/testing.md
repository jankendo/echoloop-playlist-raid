# Testing

## Python

`tools/run_python_tests.ps1` sets `PYTHONPATH=worker/src` and runs pytest. It then runs
ruff and mypy when those commands are available. The tests cover request validation,
atomic status writing, cancellation, JSONL logging, deterministic WAV generation,
schemas, and health-check completion.

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
6. Open Settings and Diagnostics; save settings and run the local worker health check.

