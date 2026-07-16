# Architecture

## Runtime layers

```text
Main scene (UI + GameplayView)
        │ signals / typed service calls
Autoload services ── AppState, Settings, Save, Log, AudioClock, JobService
        │
Pure gameplay logic ── ChartLoader, TimingJudge, ScoreSystem, GameSession,
                       EchoSystem
        │
Data boundary ── chart.json / manifest.json / replay.json / worker request-status
```

`Main.gd` owns screen composition and forwards input. Judgement and ECHOLOOP state are
kept in `scripts/core` so they can run without a scene or audio device.

## Clock contract

`AudioClock` reads `AudioStreamPlayer.get_playback_position()` plus the time since the
last audio mix and subtracts output latency when a real player is attached. It clamps
backward movement and applies audio offset. Visual offset is stored separately and is
only applied while calculating note positions.

## Gameplay flow

```text
input event → GameSession.handle_lane_input
           → TimingJudge → ScoreSystem
           → EchoSystem.record_success / record_miss
AudioClock → GameSession.advance
           → phrase boundary finalization
           → EchoSystem.replay_events / Corruption expiry
```

Echo events are effects only. They never mark a normal note as judged. A miss creates a
single Corruption event in the next phrase; Corruption failure cannot create another one.

## Python worker boundary

`JobService` writes a request JSON and launches `python -m echoloop_worker.cli`. The
worker writes status atomically and emits JSONL diagnostics. `health_check` is the only
implemented job in Phase 0. Audio analysis, yt-dlp and stem separation remain replaceable
future jobs behind this boundary.

## Autoload responsibilities

- `AppState`: current screen, active song, result snapshot.
- `SettingsService`: defaults and validated user settings.
- `SaveService`: versioned settings persistence and backup recovery.
- `LogService`: structured JSONL events.
- `AudioClock`: audio/fake clock state.
- `InputTiming`: lane mappings and judgement assist.
- `Accessibility`: visual/audio accessibility values.
- `SongLibrary`: immutable test-song metadata and future local packages.
- `JobService`: worker process boundary and diagnostic status.
- `VersionService`: product/schema versions.

