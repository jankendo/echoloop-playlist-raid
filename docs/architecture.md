# Architecture

## Runtime layers

Main scene and UI coordinator
        |
Autoload services: AppState, Settings, Save, Log, AudioClock, JobService
        |
Pure gameplay: ChartLoader, RuntimeChartAdapter, FourLaneToDuoProjector,
TimingJudge, ScoreSystem, GameSession, EchoSystem
        |
Data boundary: chart.json, manifest.json, replay.json, worker request/status

Main.gd coordinates screens. Reusable POP components live under godot/ui:
DesignTokens, PrimaryButton, SongCard, ProgressStepper, and PauseOverlay.

## Clock contract

AudioClock reads AudioStreamPlayer playback position plus mix timing and output
latency when a real player is attached. It clamps backward movement and stores
audio and visual offsets separately. Note positions never come from accumulated
frame deltas.

## Gameplay flow

InputTiming selects DUO F/J or CLASSIC D/F/J/K. GameSession receives one or both
input lanes, classifies timing, updates ScoreSystem, then records Echo success or
MISS Corruption. AudioClock advances the absolute song time; phrase boundaries
finalize Echo recordings and expire Corruption.

## Chart boundary

ChartLoader validates schema v1 and v2 and builds the BeatMap. RuntimeChartAdapter
then projects source lanes without mutating the chart on disk. Gameplay consumes
input_lane/input_lanes while Echo effects consume semantic_lane/semantic_lanes.
Musical time conversion occurs only through BeatMap.

## Python worker boundary

JobService writes a request JSON and launches the active staged Python venv
through the worker module. The registry contains local audio, YouTube probe and
import, and explicit yt-dlp verify/update/rollback jobs. Source adapters keep
yt-dlp, Deno/EJS, FFmpeg, and analysis dependencies behind this boundary.
