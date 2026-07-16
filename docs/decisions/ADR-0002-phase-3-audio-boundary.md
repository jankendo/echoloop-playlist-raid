# ADR-0002: Phase 3 audio boundary and optional backends

## Status

Accepted for Phase 3.

## Decision

Keep FFmpeg, Python audio libraries, PyTorch, and Beat This! outside the Godot
Windows executable. Expose them through the existing local worker request/status
boundary, use optional dependency groups, and provide a deterministic test
backend. Use Beat This! through its Python API when installed; fall back to
librosa when it is missing or fails. Never download a model implicitly.

## Reasons

The Phase 3 scope explicitly permits an external Python environment and does not
require a product installer containing PyTorch. Keeping the boundary replaceable
also leaves a future yt-dlp source adapter able to feed the same pipeline without
adding network access now. It makes normal CI deterministic and avoids a CUDA or
model-cache requirement.

## Consequences

Users must install FFmpeg and the optional Python environment for local import.
The game remains playable with the built-in test song and previously registered
SongPacks when those dependencies are unavailable. The diagnostics/import UI must
explain missing tools rather than crash.

Loudness is measured and stored as replay gain metadata; Phase 3 does not perform
a two-pass loudnorm rewrite because it could change timing and duration.
