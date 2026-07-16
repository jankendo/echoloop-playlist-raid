"""Generate deterministic, copyright-free WAV and chart fixtures."""

from __future__ import annotations

import hashlib
import json
import math
import shutil
import struct
import wave
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SAMPLE_RATE = 44_100
BPM = 120
BEAT_MS = 500
BEATS = 80
DURATION_MS = 40_500


def synthesize_audio(path: Path) -> None:
    total_samples = int(DURATION_MS / 1000 * SAMPLE_RATE)
    samples = [0.0] * total_samples

    def add_tone(start_ms: float, duration_ms: float, frequency: float, amplitude: float) -> None:
        start = int(start_ms / 1000 * SAMPLE_RATE)
        length = int(duration_ms / 1000 * SAMPLE_RATE)
        for offset in range(length):
            index = start + offset
            if index >= total_samples:
                break
            envelope = math.exp(-offset / max(1.0, length * 0.20))
            samples[index] += amplitude * envelope * math.sin(2 * math.pi * frequency * offset / SAMPLE_RATE)

    for beat in range(BEATS):
        bar = beat // 4
        accent = beat % 4 == 0
        chorus = 12 <= bar < 16
        add_tone(beat * BEAT_MS, 145 if accent else 95, 880 if accent else 620, 0.34 if chorus else 0.25)
        if beat % 2 == 0:
            add_tone(beat * BEAT_MS, 220, 110, 0.16 if chorus else 0.10)
        if 16 <= beat < 32 or chorus:
            add_tone(beat * BEAT_MS + 125, 270, 330 + (beat % 4) * 55, 0.08)
    add_tone(16 * BEAT_MS, 950, 220, 0.12)
    add_tone(48 * BEAT_MS, 1_600, 440, 0.10)

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            value = max(-1.0, min(1.0, sample))
            frames.extend(struct.pack("<h", int(value * 32767)))
        stream.writeframes(frames)


def build_chart() -> dict[str, Any]:
    notes: list[dict[str, Any]] = []
    note_id = 0

    def add(note_type: str, beat: float, lane: int, duration: int = 0, lanes: list[int] | None = None, accent: bool = False) -> None:
        nonlocal note_id
        payload: dict[str, Any] = {
            "id": f"n{note_id:03d}",
            "type": note_type,
            "lane": lane,
            "time_ms": int(beat * BEAT_MS),
            "duration_ms": duration,
            "phrase": int(beat // 16),
            "accent": accent,
            "section": "chorus" if 48 <= beat < 64 else ("verse" if beat >= 16 else "intro"),
        }
        if lanes is not None:
            payload["lanes"] = lanes
        notes.append(payload)
        note_id += 1

    for beat in range(BEATS):
        if beat < 8 and beat % 2 == 1:
            continue
        lane = (beat * 3 + 1) % 4
        add("tap", beat, lane, accent=beat % 4 == 0)
        if beat % 4 == 2:
            add("tap", beat + 0.5, (lane + 1) % 4)
        if beat in (8, 40, 56):
            add("hold", beat + 0.25, (lane + 2) % 4, duration=750)
        if beat in (12, 28, 44, 60, 72):
            add("chord", beat + 0.5, 0, lanes=[0, 2])
        if beat in (20, 52, 68):
            add("chord", beat + 0.5, 1, lanes=[0, 1, 3])
        if beat in (24, 48, 64):
            add("chord", beat + 0.5, 0, lanes=[0, 1, 2, 3], accent=True)

    notes.sort(key=lambda item: (item["time_ms"], item["lane"], item["id"]))
    phrases = [
        {"id": index, "start_ms": index * 8_000, "end_ms": (index + 1) * 8_000, "start_beat": index * 16, "end_beat": (index + 1) * 16, "bars": 4, "section": "chorus" if index == 3 else "main"}
        for index in range(5)
    ]
    return {
        "schema_version": 1,
        "chart_id": "test-chart-v1",
        "seed": 20260716,
        "bpm": BPM,
        "beats_per_bar": 4,
        "duration_ms": DURATION_MS,
        "phrases": phrases,
        "notes": notes,
    }


def main() -> None:
    audio_paths = [ROOT / "fixtures/generated_audio/test_song.wav", ROOT / "godot/audio/test_song.wav"]
    synthesize_audio(audio_paths[0])
    shutil.copy2(audio_paths[0], audio_paths[1])
    chart = build_chart()
    chart_paths = [ROOT / "fixtures/charts/test_chart.json", ROOT / "godot/data/test_chart.json"]
    for path in chart_paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(chart, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    sha = hashlib.sha256(audio_paths[0].read_bytes()).hexdigest()
    manifest = {
        "schema_version": 1,
        "song_id": "echoloop-test-song",
        "title": "Synthetic Crystal Pulse",
        "artist": "ECHOLOOP Fixture Generator",
        "duration_ms": DURATION_MS,
        "audio_file": "test_song.wav",
        "chart_file": "test_chart.json",
        "content_sha256": sha,
        "source": "generated-local-fixture",
    }
    for path in (ROOT / "fixtures/metadata/test_manifest.json", ROOT / "godot/data/test_manifest.json"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"generated {audio_paths[0]} sha256={sha} notes={len(chart['notes'])}")


if __name__ == "__main__":
    main()

