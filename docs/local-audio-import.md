# Local audio import

The import path is intentionally local-only. The original file is never edited
or deleted, and no URL, cookie, YouTube, or cloud request is accepted.

## Worker jobs

| Job | Responsibility |
| --- | --- |
| `probe_local_audio` | Validate the path, run JSON `ffprobe`, select the first audio stream, and calculate SHA-256. |
| `analyze_local_audio` | Probe, convert, analyze, generate four charts, and atomically commit a SongPack. |
| `regenerate_charts` | Read `analysis.json` plus `user_override.json` and regenerate charts without decoding audio again. |

Progress is written atomically to `status.json`. Audio analysis uses the stage
keys from the Phase 3 specification, with `message_key` values suitable for a
Japanese UI. A cancel marker is checked before and between external processes,
analysis stages, difficulty generation, and package commit. FFmpeg is terminated
when cancellation is detected.

## Validation and security

Supported containers/codecs are WAV, MP3, M4A, AAC, OGG, OPUS, and FLAC. The
minimum duration is 30 seconds, maximum duration is 15 minutes, and the default
size limit is 1 GiB. `ffprobe` rather than the extension is authoritative for
the audio stream. Every subprocess uses an argument array with `shell=False`.
Temporary work is created below a UUID-prefixed system directory and a package is
visible only after atomic rename.

## Conversion outputs

- `playback.ogg`: Vorbis, 48 kHz, stereo, no video stream.
- `analysis.wav`: PCM WAV, 44.1 kHz, mono.

The same source and stream mapping are used for both outputs. Leading/trailing
silence is preserved; long silence is recorded as a warning rather than silently
trimmed.
