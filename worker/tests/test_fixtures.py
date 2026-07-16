from __future__ import annotations

import hashlib
import json
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_schema_documents_and_fixture_data_are_valid_json() -> None:
    schema_dir = ROOT / "schemas"
    for path in schema_dir.glob("*.schema.json"):
        document = json.loads(path.read_text(encoding="utf-8"))
        assert document["$schema"].startswith("https://json-schema.org/")
        assert document["type"] == "object"
    chart = json.loads((ROOT / "fixtures/charts/test_chart.json").read_text(encoding="utf-8"))
    assert chart["schema_version"] == 1
    assert chart["bpm"] == 120
    assert len(chart["phrases"]) == 5
    assert len(chart["notes"]) == 110


def test_synthetic_audio_is_deterministic_and_has_expected_format() -> None:
    audio = ROOT / "fixtures/generated_audio/test_song.wav"
    first_hash = hashlib.sha256(audio.read_bytes()).hexdigest()
    with wave.open(str(audio), "rb") as stream:
        assert stream.getnchannels() == 1
        assert stream.getsampwidth() == 2
        assert stream.getframerate() == 44_100
        assert stream.getnframes() == 1_786_050
    assert first_hash == "384ba4a72087682de5be138d4c863825b0d5dc3bbc64517cddeb0833bd80ded0"

