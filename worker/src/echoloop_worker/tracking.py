"""Exchangeable beat-tracking backends with an offline fallback chain."""

from __future__ import annotations

import os
import importlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol


class BeatTrackingError(Exception):
    """Beat backend is unavailable or returned invalid data."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class BeatTrackingResult:
    beats_seconds: list[float]
    downbeats_seconds: list[float]
    bpm_summary: float
    meter: int
    confidence: float
    backend: str
    model: str
    device: str
    warnings: list[str]
    tempo_segments: list[dict[str, float]]


class BeatTracker(Protocol):
    """Common interface for all beat trackers."""

    backend_name: str

    def track(self, audio_path: Path) -> BeatTrackingResult:
        ...


class DeterministicTestBeatTracker:
    """Deterministic backend used by regular CI and synthetic fixtures."""

    backend_name = "deterministic_test"

    def __init__(
        self,
        *,
        bpm: float = 120.0,
        meter: int = 4,
        duration_seconds: float = 32.0,
        offset_seconds: float = 0.0,
        tempo_segments: list[dict[str, float]] | None = None,
    ) -> None:
        self.bpm = bpm
        self.meter = meter
        self.duration_seconds = duration_seconds
        self.offset_seconds = offset_seconds
        self._tempo_segments = tempo_segments

    def track(self, _audio_path: Path) -> BeatTrackingResult:
        segments = self._tempo_segments or [
            {"start_ms": self.offset_seconds * 1000.0, "end_ms": self.duration_seconds * 1000.0, "bpm": self.bpm}
        ]
        beats: list[float] = []
        downbeats: list[float] = []
        beat_index = 0
        for segment in segments:
            bpm = float(segment.get("bpm", self.bpm))
            interval = 60.0 / max(1.0, bpm)
            cursor = max(self.offset_seconds, float(segment.get("start_ms", 0.0)) / 1000.0)
            end = min(self.duration_seconds, float(segment.get("end_ms", self.duration_seconds * 1000.0)) / 1000.0)
            while cursor < end:
                beats.append(round(cursor, 6))
                if beat_index % self.meter == 0:
                    downbeats.append(round(cursor, 6))
                beat_index += 1
                cursor += interval
        return BeatTrackingResult(
            beats_seconds=beats,
            downbeats_seconds=downbeats,
            bpm_summary=self.bpm,
            meter=self.meter,
            confidence=1.0,
            backend=self.backend_name,
            model="deterministic",
            device="cpu",
            warnings=[],
            tempo_segments=segments,
        )


class LibrosaBeatTracker:
    """librosa tracker used when Beat This! is unavailable."""

    backend_name = "librosa"

    def track(self, audio_path: Path) -> BeatTrackingResult:
        try:
            librosa: Any = importlib.import_module("librosa")
        except ImportError as error:
            raise BeatTrackingError("LIBROSA_FAILED", "librosaがインストールされていません") from error
        try:
            _, sr = librosa.load(str(audio_path), sr=None, mono=True)
            tempo, beat_times = librosa.beat.beat_track(y=_, sr=sr, units="time")
            beat_values = beat_times.tolist() if hasattr(beat_times, "tolist") else list(beat_times)
            # The tracker boundary is seconds; analysis.py converts to ms once.
            # Do not interpret STFT frame indices as audio sample positions.
            beats = [float(value) for value in beat_values]
            if not beats:
                raise BeatTrackingError("BEAT_TRACK_EMPTY", "librosaが拍を検出できませんでした")
            bpm = float(tempo[0] if hasattr(tempo, "__len__") else tempo)
            onset = librosa.onset.onset_strength(y=_, sr=sr)
            downbeats, meter, confidence = estimate_downbeats(beats, onset, float(sr), bpm)
            return BeatTrackingResult(
                beats_seconds=beats,
                downbeats_seconds=downbeats,
                bpm_summary=bpm,
                meter=meter,
                confidence=confidence,
                backend=self.backend_name,
                model="librosa.beat.beat_track",
                device="cpu",
                warnings=[] if confidence >= 0.55 else ["DOWNBEAT_LOW_CONFIDENCE"],
                tempo_segments=_tempo_segments(beats, bpm),
            )
        except BeatTrackingError:
            raise
        except Exception as error:
            raise BeatTrackingError("LIBROSA_FAILED", "librosa解析に失敗しました") from error


class BeatThisTracker:
    """Optional Beat This! API adapter; no model is downloaded implicitly."""

    backend_name = "beat_this"

    def __init__(self, *, model: str = "final0", device: str = "auto") -> None:
        self.model = model
        self.requested_device = device

    def track(self, audio_path: Path) -> BeatTrackingResult:
        try:
            torch: Any = importlib.import_module("torch")
            inference_module: Any = importlib.import_module("beat_this.inference")
            file_to_beats: Any = inference_module.File2Beats
        except ImportError as error:
            raise BeatTrackingError("BEAT_THIS_UNAVAILABLE", "Beat This!またはPyTorchが利用できません") from error
        device = self.requested_device
        if device == "auto":
            device = "cuda" if bool(torch.cuda.is_available()) else "cpu"
        try:
            # Beat This! has changed its convenience API between releases. Keep the
            # adapter narrow and fail into librosa rather than guessing a CLI format.
            runner: Any = file_to_beats(checkpoint_path=self.model, device=device, dbn=False)
            result: Any = runner(str(audio_path))
            if isinstance(result, tuple) and len(result) >= 2:
                beats = _as_seconds(result[0])
                downbeats = _as_seconds(result[1])
            else:
                beats = _extract_seconds(result, "beats")
                downbeats = _extract_seconds(result, "downbeats")
            if not beats:
                raise BeatTrackingError("BEAT_TRACK_EMPTY", "Beat This!が拍を返しませんでした")
            bpm = _estimate_bpm(beats)
            return BeatTrackingResult(
                beats_seconds=beats,
                downbeats_seconds=downbeats or beats[::4],
                bpm_summary=bpm,
                meter=4,
                confidence=0.9,
                backend=self.backend_name,
                model=self.model,
                device=device,
                warnings=[] if downbeats else ["DOWNBEAT_LOW_CONFIDENCE"],
                tempo_segments=_tempo_segments(beats, bpm),
            )
        except BeatTrackingError:
            raise
        except Exception as error:
            code = "CUDA_UNAVAILABLE" if device == "cuda" else "BEAT_THIS_FAILED"
            raise BeatTrackingError(code, "Beat This!推論に失敗しました") from error


def track_with_fallback(
    audio_path: Path,
    *,
    preferred: str = "auto",
    model: str = "final0",
    deterministic: BeatTracker | None = None,
) -> BeatTrackingResult:
    """Try Beat This!, then librosa, and only use deterministic data when asked."""
    if deterministic is not None:
        return deterministic.track(audio_path)
    requested = preferred.lower()
    errors: list[str] = []
    if requested in {"auto", "beat_this"} and not os.environ.get("ECHOLOOP_DISABLE_BEAT_THIS"):
        try:
            return BeatThisTracker(model=model).track(audio_path)
        except BeatTrackingError as error:
            errors.append(error.code)
    if requested in {"auto", "beat_this", "librosa"}:
        try:
            result = LibrosaBeatTracker().track(audio_path)
            if errors:
                return BeatTrackingResult(
                    **{**result.__dict__, "warnings": [f"fallback:{code}" for code in errors] + result.warnings}
                )
            return result
        except BeatTrackingError as error:
            errors.append(error.code)
    raise BeatTrackingError(errors[-1] if errors else "BEAT_TRACK_EMPTY", ";".join(errors) or "拍解析に失敗しました")


def estimate_downbeats(
    beats: list[float], onset_strength: Any, sample_rate: float, bpm: float
) -> tuple[list[float], int, float]:
    """Compare 3/4 and 4/4 accents instead of assuming a meter."""
    if len(beats) < 3:
        return beats[::4], 4, 0.25
    values: list[float] = []
    try:
        values = [float(value) for value in onset_strength]
    except TypeError:
        values = []
    scores: dict[int, float] = {}
    for meter in (3, 4):
        accents: list[float] = []
        for index, beat in enumerate(beats):
            sample = min(len(values) - 1, max(0, int(beat * sample_rate))) if values else 0
            accents.append(values[sample] if values else (1.0 if index % meter == 0 else 0.0))
        scores[meter] = sum(accents[index] for index in range(0, len(accents), meter)) / max(1, len(accents) // meter)
    meter = 4 if scores[4] >= scores[3] else 3
    baseline = scores[3] if meter == 4 else scores[4]
    winning = scores[meter]
    confidence = max(0.25, min(1.0, 0.5 + (winning - baseline) / max(0.01, abs(winning) + abs(baseline))))
    return beats[::meter], meter, confidence


def _extract_seconds(result: Any, key: str) -> list[float]:
    if isinstance(result, dict):
        value = result.get(key, [])
    else:
        value = getattr(result, key, [])
    return _as_seconds(value)


def _as_seconds(value: Any) -> list[float]:
    if hasattr(value, "tolist"):
        value = value.tolist()
    return [float(item) for item in value] if isinstance(value, (list, tuple)) else []


def _estimate_bpm(beats: list[float]) -> float:
    if len(beats) < 2:
        return 0.0
    intervals = [right - left for left, right in zip(beats, beats[1:]) if right > left]
    return 60.0 / (sum(intervals) / len(intervals)) if intervals else 0.0


def _tempo_segments(beats: list[float], bpm: float) -> list[dict[str, float]]:
    if not beats:
        return []
    return [{"start_ms": beats[0] * 1000.0, "end_ms": beats[-1] * 1000.0, "bpm": bpm}]
