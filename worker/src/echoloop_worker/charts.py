"""Deterministic, quality-checked chart generation."""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from typing import Any


DIFFICULTIES = ("easy", "normal", "hard", "expert")
MIN_LANE_INTERVAL_MS = {"easy": 160.0, "normal": 110.0, "hard": 75.0, "expert": 50.0}
TARGET_DENSITY = {"easy": 1.4, "normal": 2.4, "hard": 4.0, "expert": 6.0}
INSUFFICIENT_DATA_INTERVAL_MS = 60_000.0 / 120.0


@dataclass(frozen=True)
class ChartGenerationSettings:
    generator_version: str = "0.2.0"
    analysis_version: str = "0.2.0"
    max_regenerations: int = 3


def _hash_seed(
    audio_sha256: str,
    analysis_version: str,
    generator_version: str,
    difficulty: str,
    override: dict[str, Any],
) -> tuple[str, int]:
    override_hash = hashlib.sha256(json.dumps(override, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    material = audio_sha256 + analysis_version + generator_version + difficulty + override_hash
    digest = hashlib.sha256(material.encode()).hexdigest()
    return digest, int(digest[:16], 16)


def _beat_position(time_ms: float, beats_ms: list[float]) -> float:
    if not beats_ms:
        return 0.0
    if time_ms <= beats_ms[0]:
        interval = beats_ms[1] - beats_ms[0] if len(beats_ms) > 1 else INSUFFICIENT_DATA_INTERVAL_MS
        return (time_ms - beats_ms[0]) / max(1.0, interval)
    for index, right in enumerate(beats_ms[1:], start=1):
        left = beats_ms[index - 1]
        if time_ms <= right:
            return index - 1 + (time_ms - left) / max(1.0, right - left)
    interval = beats_ms[-1] - beats_ms[-2] if len(beats_ms) > 1 else INSUFFICIENT_DATA_INTERVAL_MS
    return len(beats_ms) - 1 + (time_ms - beats_ms[-1]) / max(1.0, interval)


def _nearest_grid(time_ms: float, beats_ms: list[float], subdivisions: int) -> tuple[float, float, float]:
    position = _beat_position(time_ms, beats_ms)
    quantized_position = round(position * subdivisions) / subdivisions
    lower = int(math.floor(quantized_position))
    fraction = quantized_position - lower
    if lower >= len(beats_ms) - 1:
        interval = beats_ms[-1] - beats_ms[-2] if len(beats_ms) > 1 else INSUFFICIENT_DATA_INTERVAL_MS
        quantized_time = beats_ms[-1] + (quantized_position - (len(beats_ms) - 1)) * interval
    else:
        quantized_time = beats_ms[lower] + fraction * (beats_ms[lower + 1] - beats_ms[lower])
    return quantized_time, quantized_position, abs(time_ms - quantized_time)


def classify_lane(event: dict[str, Any], fallback_index: int) -> int:
    """Map quick-analysis features to Pulse/Weight/Voice/Field lanes."""
    if "lane_hint" in event:
        return int(event["lane_hint"]) % 4
    low = float(event.get("low_energy", 0.0))
    high = float(event.get("high_energy", 0.0))
    harmonic = float(event.get("harmonic_ratio", 0.0))
    percussive = float(event.get("percussive_ratio", 0.0))
    if percussive >= 0.62:
        lane = 0
    elif low >= high * 1.15:
        lane = 1
    elif harmonic >= 0.6 and high >= low:
        lane = 2
    else:
        lane = 3
    return lane if event else fallback_index % 4


def _section_for(time_ms: float, sections: list[dict[str, Any]]) -> tuple[str, float]:
    for section in sections:
        if float(section.get("start_ms", 0.0)) <= time_ms < float(section.get("end_ms", 0.0)):
            return str(section.get("label", "unknown")), float(section.get("confidence", 0.0))
    return "unknown", 0.0


def _phrase_for(beat_position: float, meter: int) -> int:
    return max(0, int(math.floor(beat_position)) // max(1, meter * 4))


def _candidate_events(analysis: dict[str, Any], difficulty: str, seed: int) -> list[dict[str, Any]]:
    beats = [float(value) for value in analysis.get("beats_ms", [])]
    if len(beats) < 2:
        return []
    onsets = [item for item in analysis.get("onset_events", []) if isinstance(item, dict)]
    subdivisions = {"easy": 1, "normal": 2, "hard": 4, "expert": 4}[difficulty]
    candidates: list[dict[str, Any]] = []
    source_events = onsets or [{"time_ms": value, "strength": 0.7, "duration_ms": 120.0} for value in beats]
    if difficulty != "easy":
        expanded: list[dict[str, Any]] = list(source_events)
        for beat_index in range(len(beats) - 1):
            interval = beats[beat_index + 1] - beats[beat_index]
            for subdivision in range(subdivisions):
                if subdivision == 0 and beat_index % 2 == 1 and difficulty == "normal":
                    continue
                expanded.append(
                    {
                        "time_ms": beats[beat_index] + interval * subdivision / subdivisions,
                        "strength": 0.52 if subdivision else 0.68,
                        "duration_ms": 140.0,
                        "low_energy": 0.35 if (beat_index + subdivision) % 2 == 0 else 0.15,
                        "high_energy": 0.25,
                        "harmonic_ratio": 0.45,
                        "percussive_ratio": 0.58,
                        "confidence": 0.7,
                        "lane_hint": (beat_index + subdivision + seed) % 4,
                    }
                )
        source_events = expanded
    for index, event in enumerate(source_events):
        original = float(event.get("time_ms", 0.0))
        quantized, position, error = _nearest_grid(original, beats, subdivisions)
        strength = float(event.get("strength", 0.0))
        if error > 110.0 and strength < 0.7:
            continue
        beat_index = int(math.floor(position))
        if difficulty == "easy" and (position % 1.0 > 0.01 and strength < 0.75):
            continue
        if difficulty == "normal" and strength < 0.20 and position % 1.0 > 0.01:
            continue
        if difficulty == "hard" and strength < 0.12 and index % 2:
            continue
        if difficulty == "expert" and strength < 0.08 and index % 3:
            continue
        lane = classify_lane(event, index + seed % 4)
        section, section_confidence = _section_for(quantized, analysis.get("sections", []))
        candidates.append(
            {
                "original_time_ms": original,
                "time_ms": quantized,
                "beat_position": position,
                "quantization_error_ms": error,
                "lane": lane,
                "source": _source_name(event),
                "confidence": min(1.0, max(0.0, float(event.get("confidence", 0.5)))),
                "strength": strength,
                "duration_ms": float(event.get("duration_ms", 0.0)),
                "section": section,
                "section_confidence": section_confidence,
                "accent": beat_index % max(1, int(analysis.get("meter", 4))) == 0 or strength >= 0.75,
            }
        )
    candidates.sort(key=lambda item: (float(item["time_ms"]), int(item["lane"]), float(item["original_time_ms"])))
    return candidates


def _source_name(event: dict[str, Any]) -> str:
    percussive = float(event.get("percussive_ratio", 0.0))
    low = float(event.get("low_energy", 0.0))
    harmonic = float(event.get("harmonic_ratio", 0.0))
    if percussive >= 0.62:
        return "percussive_transient"
    if low > harmonic:
        return "percussive_low"
    if harmonic >= 0.6:
        return "harmonic_lead"
    return "broadband_event"


def _keep_playable(candidates: list[dict[str, Any]], difficulty: str, duration_ms: float) -> list[dict[str, Any]]:
    minimum = MIN_LANE_INTERVAL_MS[difficulty]
    last_by_lane: dict[int, float] = {}
    kept: list[dict[str, Any]] = []
    for candidate in candidates:
        time_ms = max(0.0, min(duration_ms - 1.0, float(candidate["time_ms"])))
        lane = int(candidate["lane"])
        if time_ms - last_by_lane.get(lane, -10_000.0) < minimum:
            continue
        candidate["time_ms"] = round(time_ms)
        last_by_lane[lane] = time_ms
        kept.append(candidate)
    return kept


def _make_notes(candidates: list[dict[str, Any]], analysis: dict[str, Any], difficulty: str, seed: int) -> list[dict[str, Any]]:
    meter = int(analysis.get("meter", 4))
    notes: list[dict[str, Any]] = []
    for index, candidate in enumerate(candidates):
        note_time = int(candidate["time_ms"])
        lane = int(candidate["lane"])
        note_type = "tap"
        lanes = [lane]
        event_duration = float(candidate.get("duration_ms", 0.0))
        if difficulty in {"hard", "expert"} and event_duration >= 300.0 and index % (3 if difficulty == "hard" else 2) == 0:
            note_type = "hold"
        if difficulty != "easy" and index > 0 and index % (7 if difficulty == "normal" else 5 if difficulty == "hard" else 3) == 0:
            partner = (lane + 2 + (seed % 2)) % 4
            if partner != lane:
                note_type = "chord"
                lanes = sorted({lane, partner})
                if difficulty == "expert" and index % 11 == 0:
                    lanes = sorted({lane, partner, (partner + 1) % 4})
        phrase = _phrase_for(float(candidate["beat_position"]), meter)
        note: dict[str, Any] = {
            "id": f"{difficulty}-{index:05d}",
            "type": note_type,
            "lane": lane,
            "lanes": lanes,
            "time_ms": note_time,
            "original_time_ms": round(float(candidate["original_time_ms"]), 3),
            "beat_position": round(float(candidate["beat_position"]), 5),
            "quantization_error_ms": round(float(candidate["quantization_error_ms"]), 3),
            "phrase": phrase,
            "section": candidate["section"],
            "source": candidate["source"],
            "confidence": round(float(candidate["confidence"]), 4),
            "weight": round(max(0.6, min(1.8, 0.7 + float(candidate["strength"]))), 4),
            "accent": bool(candidate["accent"]),
        }
        if note_type == "hold":
            note["duration_ms"] = int(min(1_500.0, max(300.0, event_duration)))
        else:
            note["duration_ms"] = 0
        notes.append(note)
    notes.sort(key=lambda item: (int(item["time_ms"]), int(item["lane"]), str(item["id"])))
    _rebalance_lane_concentration(notes)
    return notes


def _rebalance_lane_concentration(notes: list[dict[str, Any]]) -> None:
    """Move only dominant-lane taps when the source produces an unplayable stream."""
    if len(notes) < 8:
        return
    counts = [sum(1 for note in notes if int(note.get("lane", -1)) == lane) for lane in range(4)]
    dominant = max(range(4), key=lambda lane: counts[lane])
    if counts[dominant] / len(notes) <= 0.75:
        return
    shift = 0
    for note in notes:
        if int(note.get("lane", -1)) != dominant or str(note.get("type")) == "chord":
            continue
        shift += 1
        new_lane = (dominant + shift) % 4
        note["lane"] = new_lane
        note["lanes"] = [new_lane]


def validate_chart_quality(chart: dict[str, Any], analysis: dict[str, Any], difficulty: str) -> dict[str, Any]:
    notes = [item for item in chart.get("notes", []) if isinstance(item, dict)]
    duration = max(1.0, float(chart.get("duration_ms", 1)))
    counts = [sum(1 for note in notes if int(note.get("lane", -1)) == lane) for lane in range(4)]
    total = max(1, sum(counts))
    probabilities = [count / total for count in counts if count]
    entropy = -sum(probability * math.log(probability, 4) for probability in probabilities)
    lane_share = max(counts) / total if counts else 1.0
    density = len(notes) / (duration / 1000.0)
    target = TARGET_DENSITY[difficulty]
    same_lane_violations = 0
    last: dict[int, int] = {}
    for note in notes:
        lane = int(note.get("lane", -1))
        current = int(note.get("time_ms", 0))
        if current - last.get(lane, -100000) < MIN_LANE_INTERVAL_MS[difficulty]:
            same_lane_violations += 1
        last[lane] = current
    timing = max(0.0, 1.0 - sum(float(note.get("quantization_error_ms", 0.0)) for note in notes) / max(1.0, len(notes) * 120.0))
    density_score = max(0.0, 1.0 - abs(density - target) / max(target, 1.0))
    playability = max(0.0, 1.0 - same_lane_violations / max(1.0, len(notes)))
    result = {
        "timing_alignment": round(timing, 4),
        "phase_offset_ms": round(_phase_offset(notes, analysis), 3),
        "density_score": round(density_score, 4),
        "lane_entropy": round(entropy, 4),
        "pattern_diversity": round(min(1.0, len({(int(note.get("lane", 0)), str(note.get("type", "tap"))) for note in notes}) / 12.0), 4),
        "section_contrast": round(_section_contrast(notes), 4),
        "playability_score": round(playability, 4),
        "echo_utility_score": round(min(1.0, len(notes) / max(1.0, len(analysis.get("beats_ms", [])) * 0.5)), 4),
        "lane_share_max": round(lane_share, 4),
        "density_per_second": round(density, 4),
        "same_lane_violations": same_lane_violations,
        "warnings": ["LANE_CONCENTRATION"] if lane_share > 0.75 else [],
    }
    return result


def _phase_offset(notes: list[dict[str, Any]], analysis: dict[str, Any]) -> float:
    if not notes or not analysis.get("beats_ms"):
        return 0.0
    return sum(float(note.get("quantization_error_ms", 0.0)) for note in notes) / len(notes)


def _section_contrast(notes: list[dict[str, Any]]) -> float:
    counts: dict[str, int] = {}
    for note in notes:
        section = str(note.get("section", "unknown"))
        counts[section] = counts.get(section, 0) + 1
    if len(counts) < 2:
        return 0.5
    values = list(counts.values())
    return min(1.0, (max(values) - min(values)) / max(1.0, sum(values) / len(values)))


def simulate_bots(chart: dict[str, Any]) -> dict[str, Any]:
    """Cheap deterministic bot simulation for generation-time guardrails."""
    note_count = len(chart.get("notes", []))
    damage = note_count * 1.25
    return {
        "perfect": {"accuracy": 1.0, "boss_damage": round(damage, 3), "clears": damage >= 100.0},
        "skilled": {"accuracy": 0.95, "boss_damage": round(damage * 0.95, 3), "clears": damage * 0.95 >= 100.0},
        "average": {"accuracy": 0.85, "boss_damage": round(damage * 0.85, 3), "clears": damage * 0.85 >= 100.0},
        "beginner": {"accuracy": 0.70, "boss_damage": round(damage * 0.70, 3), "clears": damage * 0.70 >= 100.0},
    }


def generate_chart(
    analysis: dict[str, Any],
    difficulty: str,
    *,
    audio_sha256: str | None = None,
    user_override: dict[str, Any] | None = None,
    settings: ChartGenerationSettings = ChartGenerationSettings(),
) -> dict[str, Any]:
    """Generate one schema-v2 chart deterministically from analysis summaries."""
    if difficulty not in DIFFICULTIES:
        raise ValueError(f"unsupported difficulty: {difficulty}")
    override = user_override or {}
    effective = dict(analysis)
    effective["beats_ms"] = [float(value) for value in analysis.get("beats_ms", [])]
    multiplier = float(override.get("bpm_multiplier", 1.0))
    manual_bpm = override.get("manual_bpm")
    if manual_bpm or multiplier != 1.0:
        factor = (float(manual_bpm) / max(1.0, float(analysis.get("bpm_summary", 120.0)))) if manual_bpm else multiplier
        effective["beats_ms"] = [float(analysis.get("beats_ms", [])[0]) + (value - float(analysis.get("beats_ms", [])[0])) / factor for value in effective["beats_ms"]] if effective["beats_ms"] else []
        effective["bpm_summary"] = float(analysis.get("bpm_summary", 120.0)) * factor
    offset = float(override.get("beat_offset_ms", 0.0))
    effective["beats_ms"] = [value + offset for value in effective["beats_ms"]]
    digest, numeric_seed = _hash_seed(
        audio_sha256 or str(analysis.get("audio_sha256", "unknown")),
        settings.analysis_version,
        settings.generator_version,
        difficulty,
        override,
    )
    duration_ms = int(max(1.0, float(analysis.get("duration_ms", 1.0))))
    meter = int(analysis.get("meter", 4))
    downbeats = [float(value) for value in analysis.get("downbeats_ms", [])]
    phrases = _phrases(duration_ms, effective.get("beats_ms", []), downbeats, meter)
    notes: list[dict[str, Any]] = []
    quality: dict[str, Any] = {}
    for attempt in range(settings.max_regenerations + 1):
        attempt_seed = numeric_seed + attempt * 1009
        candidates = _candidate_events(effective, difficulty, attempt_seed)
        notes = _make_notes(
            _keep_playable(candidates, difficulty, float(analysis.get("duration_ms", 0.0))),
            effective,
            difficulty,
            attempt_seed,
        )
        quality = validate_chart_quality({"notes": notes, "duration_ms": duration_ms}, effective, difficulty)
        quality["bots"] = simulate_bots({"notes": notes})
        quality["generation_attempt"] = attempt
        if int(quality.get("same_lane_violations", 0)) == 0 and float(quality.get("lane_share_max", 1.0)) <= 0.75:
            break
    return {
        "schema_version": 2,
        "chart_id": f"{digest[:16]}-{difficulty}",
        "song_uuid": str(analysis.get("song_uuid", "")),
        "difficulty": difficulty,
        "generator_version": settings.generator_version,
        "seed": digest,
        "duration_ms": duration_ms,
        "timing": {
            "bpm_summary": round(float(effective.get("bpm_summary", 0.0)), 5),
            "beats_per_bar": meter,
            "beats_ms": [round(value, 3) for value in effective.get("beats_ms", [])],
            "downbeats_ms": [round(value, 3) for value in downbeats],
            "tempo_segments": effective.get("tempo_segments", []),
            "audio_offset_ms": offset,
        },
        "phrases": phrases,
        "sections": effective.get("sections", []),
        "notes": notes,
        "boss": {"max_hp": 100.0, "damage_per_note": 1.25},
        "quality": quality,
    }


def _phrases(duration_ms: int, beats: list[float], downbeats: list[float], meter: int) -> list[dict[str, Any]]:
    phrase_length = max(1, meter * 4)
    count = max(1, math.ceil(len(beats) / phrase_length)) if beats else max(1, math.ceil(duration_ms / 8_000))
    phrases: list[dict[str, Any]] = []
    for index in range(count):
        beat_start = index * phrase_length
        start = beats[beat_start] if beat_start < len(beats) else (downbeats[index] if index < len(downbeats) else index * 8_000.0)
        next_index = (index + 1) * phrase_length
        end = beats[next_index] if next_index < len(beats) else min(float(duration_ms), start + max(1, phrase_length) * 60_000.0 / 120.0)
        phrases.append({"id": index, "start_ms": round(max(0.0, start), 3), "end_ms": round(min(duration_ms, end), 3), "beat_start": beat_start, "beat_count": phrase_length, "section": "chorus" if index % 4 == 3 else "verse"})
    return phrases


def generate_all_charts(
    analysis: dict[str, Any],
    *,
    audio_sha256: str | None = None,
    user_override: dict[str, Any] | None = None,
    settings: ChartGenerationSettings = ChartGenerationSettings(),
) -> dict[str, dict[str, Any]]:
    return {difficulty: generate_chart(analysis, difficulty, audio_sha256=audio_sha256, user_override=user_override, settings=settings) for difficulty in DIFFICULTIES}
