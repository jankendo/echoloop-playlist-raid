"""Compact local audio feature extraction for chart generation."""

from __future__ import annotations

import math
import statistics
import time
import wave
from pathlib import Path
from typing import Any

from echoloop_worker.audio import AudioError, sha256_file
from echoloop_worker.tracking import BeatTracker, BeatTrackingError, track_with_fallback


def read_mono_samples(path: Path) -> tuple[list[float], int]:
    """Read common PCM WAV files without requiring NumPy or SoundFile."""
    try:
        import soundfile as sf  # type: ignore[import-untyped]

        data, sample_rate = sf.read(str(path), dtype="float32", always_2d=True)
        channels = len(data[0]) if len(data) else 1
        samples = [sum(float(frame[channel]) for channel in range(channels)) / channels for frame in data]
        return samples, int(sample_rate)
    except (ImportError, OSError, RuntimeError, ValueError):
        pass
    try:
        with wave.open(str(path), "rb") as handle:
            channels = handle.getnchannels()
            sample_rate = handle.getframerate()
            width = handle.getsampwidth()
            frames = handle.readframes(handle.getnframes())
    except (OSError, wave.Error) as error:
        raise AudioError("AUDIO_INVALID", "解析用音源を読み込めませんでした") from error
    if width not in {1, 2, 3, 4}:
        raise AudioError("AUDIO_INVALID", "対応していないPCMビット深度です")
    values: list[float] = []
    stride = width * channels
    for frame_start in range(0, len(frames), stride):
        frame = frames[frame_start : frame_start + stride]
        if len(frame) < stride:
            break
        channel_values: list[float] = []
        for channel in range(channels):
            start = channel * width
            raw = frame[start : start + width]
            if width == 1:
                value = (raw[0] - 128) / 128.0
            else:
                signed = int.from_bytes(raw, byteorder="little", signed=False)
                sign_bit = 1 << (width * 8 - 1)
                if signed & sign_bit:
                    signed -= 1 << (width * 8)
                value = signed / float(1 << (width * 8 - 1))
            channel_values.append(max(-1.0, min(1.0, value)))
        values.append(sum(channel_values) / len(channel_values))
    return values, sample_rate


def _frame_values(samples: list[float], sample_rate: int, frame_ms: float = 50.0) -> list[dict[str, float]]:
    frame_size = max(1, int(sample_rate * frame_ms / 1000.0))
    frames: list[dict[str, float]] = []
    for start in range(0, len(samples), frame_size):
        block = samples[start : start + frame_size]
        if not block:
            continue
        rms = math.sqrt(sum(value * value for value in block) / len(block))
        peak = max(abs(value) for value in block)
        crossing = sum(1 for left, right in zip(block, block[1:]) if (left < 0) != (right < 0)) / len(block)
        frames.append({"time_ms": start * 1000.0 / sample_rate, "rms": rms, "peak": peak, "zcr": crossing})
    return frames


def _onset_events(frames: list[dict[str, float]], sample_rate: int) -> list[dict[str, Any]]:
    if len(frames) < 2:
        return []
    differences = [max(0.0, current["rms"] - previous["rms"]) for previous, current in zip(frames, frames[1:])]
    baseline = statistics.median(differences) if differences else 0.0
    threshold = max(0.015, baseline * 1.8)
    events: list[dict[str, Any]] = []
    last_time = -10_000.0
    for index, strength in enumerate(differences, start=1):
        frame = frames[index]
        if strength < threshold or frame["time_ms"] - last_time < 80.0:
            continue
        rms = frame["rms"]
        zcr = frame["zcr"]
        low = max(0.0, rms * (1.0 - min(1.0, zcr * 2.0)))
        high = max(0.0, rms * min(1.0, zcr * 2.0))
        events.append(
            {
                "time_ms": round(frame["time_ms"], 3),
                "strength": round(min(1.0, strength * 8.0), 4),
                "duration_ms": 250.0 if rms > 0.08 else 120.0,
                "low_energy": round(low, 5),
                "mid_energy": round(rms * 0.7, 5),
                "high_energy": round(high, 5),
                "harmonic_ratio": round(max(0.0, 1.0 - zcr), 5),
                "percussive_ratio": round(min(1.0, zcr * 1.5), 5),
                "spectral_centroid": round(zcr * sample_rate / 2.0, 3),
                "confidence": round(min(1.0, 0.45 + strength * 4.0), 4),
            }
        )
        last_time = frame["time_ms"]
    return events


def _silence_ranges(frames: list[dict[str, float]], duration_ms: float) -> list[dict[str, float]]:
    quiet = [frame for frame in frames if frame["rms"] < 0.008]
    ranges: list[dict[str, float]] = []
    start: float | None = None
    previous: float | None = None
    for frame in quiet:
        current = frame["time_ms"]
        if start is None or previous is None or current - previous > 80.0:
            if start is not None and previous is not None and previous - start >= 500.0:
                ranges.append({"start_ms": start, "end_ms": previous + 50.0})
            start = current
        previous = current
    if start is not None and previous is not None and previous - start >= 500.0:
        ranges.append({"start_ms": start, "end_ms": min(duration_ms, previous + 50.0)})
    return ranges


def _sections(frames: list[dict[str, float]], beats_ms: list[float], duration_ms: float) -> list[dict[str, Any]]:
    if not beats_ms:
        return []
    chunk_ms = max(1_000.0, duration_ms / 8.0)
    chunks: list[dict[str, float]] = []
    for start in range(0, int(duration_ms), int(chunk_ms)):
        values = [frame["rms"] for frame in frames if start <= frame["time_ms"] < start + chunk_ms]
        chunks.append({"start_ms": float(start), "end_ms": min(duration_ms, start + chunk_ms), "energy": sum(values) / len(values) if values else 0.0})
    energies = [item["energy"] for item in chunks]
    average = sum(energies) / len(energies) if energies else 0.0
    sections: list[dict[str, Any]] = []
    for index, chunk in enumerate(chunks):
        beat_start = min(range(len(beats_ms)), key=lambda item: abs(beats_ms[item] - chunk["start_ms"]))
        beat_end = min(range(len(beats_ms)), key=lambda item: abs(beats_ms[item] - chunk["end_ms"]))
        energy = chunk["energy"]
        if index == 0:
            label = "intro_like"
        elif index == len(chunks) - 1:
            label = "outro_like"
        elif energy >= average * 1.25 and energy > 0.01:
            label = "chorus_like"
        elif energy <= average * 0.65:
            label = "breakdown_like"
        else:
            label = "verse_like"
        sections.append(
            {
                "id": f"section-{index}",
                "start_ms": round(chunk["start_ms"], 3),
                "end_ms": round(chunk["end_ms"], 3),
                "start_beat": beat_start,
                "end_beat": beat_end,
                "label": label,
                "energy": round(min(1.0, energy * 8.0), 4),
                "repetition": 0.5,
                "confidence": 0.65 if energy > 0.0 else 0.35,
            }
        )
    return sections


def _waveform_peaks(frames: list[dict[str, float]], limit: int = 512) -> list[float]:
    if len(frames) <= limit:
        return [round(min(1.0, frame["peak"]), 4) for frame in frames]
    stride = len(frames) / limit
    peaks: list[float] = []
    for index in range(limit):
        start = int(index * stride)
        end = min(len(frames), max(start + 1, int((index + 1) * stride)))
        peaks.append(round(max(frames[start:end], key=lambda item: item["peak"])["peak"], 4))
    return peaks


def analyze_local_audio(
    analysis_path: Path,
    *,
    audio_sha256: str | None = None,
    tracker: BeatTracker | None = None,
    preferred_backend: str = "auto",
    model: str = "final0",
) -> dict[str, Any]:
    """Analyze an analysis.wav and return compact JSON-safe summary values."""
    started = time.perf_counter()
    samples, sample_rate = read_mono_samples(analysis_path)
    duration_ms = len(samples) * 1000.0 / sample_rate if samples else 0.0
    if duration_ms <= 0.0:
        raise AudioError("AUDIO_INVALID", "解析用音源が空です")
    try:
        tracking = track_with_fallback(
            analysis_path,
            preferred=preferred_backend,
            model=model,
            deterministic=tracker,
        )
    except BeatTrackingError as error:
        raise AudioError(error.code, str(error), retryable=True) from error
    beats_ms = [round(value * 1000.0, 3) for value in tracking.beats_seconds if value >= 0.0]
    downbeats_ms = [round(value * 1000.0, 3) for value in tracking.downbeats_seconds if value >= 0.0]
    frames = _frame_values(samples, sample_rate)
    onset_events = _onset_events(frames, sample_rate)
    silence = _silence_ranges(frames, duration_ms)
    sections = _sections(frames, beats_ms, duration_ms)
    rms_values = [frame["rms"] for frame in frames]
    peak = max((frame["peak"] for frame in frames), default=0.0)
    rms = sum(rms_values) / len(rms_values) if rms_values else 0.0
    return {
        "schema_version": 2,
        "audio_sha256": audio_sha256 or sha256_file(analysis_path),
        "duration_ms": round(duration_ms, 3),
        "sample_rate": sample_rate,
        "loudness": {"rms": round(rms, 6), "integrated_lufs": round(20.0 * math.log10(max(rms, 1e-6)), 3)},
        "peak": round(peak, 6),
        "silence_ranges": silence,
        "beat_backend": tracking.backend,
        "model": tracking.model,
        "device": tracking.device,
        "beats_ms": beats_ms,
        "downbeats_ms": downbeats_ms,
        "bpm_summary": round(tracking.bpm_summary, 5),
        "tempo_segments": tracking.tempo_segments,
        "meter": tracking.meter,
        "onset_events": onset_events,
        "band_energies": {
            "low": round(sum(item["low_energy"] for item in onset_events) / max(1, len(onset_events)), 6),
            "mid": round(sum(item["mid_energy"] for item in onset_events) / max(1, len(onset_events)), 6),
            "high": round(sum(item["high_energy"] for item in onset_events) / max(1, len(onset_events)), 6),
        },
        "hpss": {"harmonic_ratio": round(sum(item.get("harmonic_ratio", 0.0) for item in onset_events) / max(1, len(onset_events)), 5), "percussive_ratio": round(sum(item.get("percussive_ratio", 0.0) for item in onset_events) / max(1, len(onset_events)), 5)},
        "sections": sections,
        "waveform_peaks": _waveform_peaks(frames),
        "confidence": tracking.confidence,
        "warnings": tracking.warnings + (["LONG_SILENCE"] if silence else []),
        "dependency_versions": _dependency_versions(),
        "processing_duration_ms": round((time.perf_counter() - started) * 1000.0, 3),
    }


def _dependency_versions() -> dict[str, str]:
    versions: dict[str, str] = {}
    for name in ("numpy", "scipy", "librosa", "soundfile", "soxr", "torch", "beat_this"):
        try:
            module = __import__(name)
            versions[name] = str(getattr(module, "__version__", "installed"))
        except (ImportError, OSError):
            versions[name] = "unavailable"
    return versions
