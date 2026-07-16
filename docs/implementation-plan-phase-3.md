# Phase 3 implementation plan

## Audit at the baseline

Baseline `3550f11b7653a7b3ca05bb0282e176bdee204ed8` had a working Godot Phase 0–2
vertical slice, a Python `health_check` worker, schema v1 charts, and a minimal
test-song-only `SongLibrary`. The gameplay clock was absolute-time based, but
Echo and Corruption converted phrase position through an implicit 120 BPM beat.

## Reuse and changes

- Keep `GameSession`, `TimingJudge`, `ScoreSystem`, `AudioClock`, the fixed test WAV,
  and all existing v1 fixture files.
- Add `BeatMap` as the only runtime musical-time conversion service. v1 charts are
  normalized into it from their legacy BPM; v2 charts carry explicit beat arrays.
- Replace the single worker `if` branch with a registry for `health_check`,
  `probe_local_audio`, `analyze_local_audio`, and `regenerate_charts`.
- Keep audio dependencies optional. The deterministic backend is used in normal
  CI; real local analysis uses FFmpeg plus librosa, and Beat This! is an optional
  adapter with no implicit model download.
- Store completed packages through a temporary directory and atomic rename.

## Schema migration

Schema v1 remains the fixed test-song contract. Schema v2 is used for generated
charts and `analysis.json`; `ChartLoader.normalize()` exposes the same Runtime
Chart shape to gameplay, including its `BeatMap` object.

## Godot integration

The main menu now exposes Import Local Audio and Song Library. The import flow
uses the asynchronous worker boundary, shows stage/progress in Japanese, and
supports cancellation. Beat Check draws waveform peaks, beats, and downbeats and
saves BPM/offset adjustments into `user_override.json` before chart regeneration.
Generated `playback.ogg` is loaded at runtime with `AudioStreamOggVorbis`.

## Test and risk plan

Python tests cover safe paths, ffprobe fields, argument-vector construction,
variable-tempo trackers, deterministic chart differences, SongPack atomicity,
and the job registry. A real synthetic-WAV E2E is run separately. Godot tests
cover v1 normalization, BeatMap interpolation, variable tempo, Echo replay, and
Corruption rules. Godot 4.7.1 remains the CI authority; local Godot 4.2 is only a
compatibility smoke environment.

Known risks are optional Beat This! model availability, external FFmpeg setup,
and the fact that a full product installer is outside Phase 3.

## Phase 3 completion boundary

The repository provides a working offline pipeline for local audio probing,
conversion, analysis fallback, four deterministic charts, quality metrics, atomic
SongPack storage, BeatMap-based gameplay, import progress, and registered-song
playback. YouTube acquisition, online features, Demucs, and a bundled analysis
runtime remain Phase 4 or later.
