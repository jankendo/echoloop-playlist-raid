from __future__ import annotations

from echoloop_worker.charts import generate_all_charts


def _analysis() -> dict[str, object]:
    beats = [float(index * 500) for index in range(40)]
    return {
        "song_uuid": "duo-fixture",
        "audio_sha256": "duo-fixture-sha",
        "duration_ms": 19_500,
        "bpm_summary": 120.0,
        "meter": 4,
        "beats_ms": beats,
        "downbeats_ms": beats[::4],
        "tempo_segments": [],
        "sections": [{"start_ms": 0, "end_ms": 19_500, "label": "verse", "confidence": 1.0}],
        "onset_events": [{"time_ms": value, "strength": 0.8, "duration_ms": 140.0, "lane_hint": index % 4} for index, value in enumerate(beats)],
    }


def test_generated_charts_include_duo_contract_and_metrics() -> None:
    charts = generate_all_charts(_analysis())
    assert all(chart["gameplay_mode"] == "duo_2key" for chart in charts.values())
    for chart in charts.values():
        quality = chart["quality"]
        assert {"duo_balance", "alternation_ratio", "left_density", "right_density", "jack_density", "duo_chord_ratio", "hold_conflict_count", "duo_playability_score"} <= quality.keys()
        assert all(set(note["input_lanes"]) <= {0, 1} and note["semantic_lanes"] for note in chart["notes"])


def test_classic_generation_remains_available() -> None:
    charts = generate_all_charts(_analysis(), gameplay_mode="classic_4lane")
    assert all(chart["gameplay_mode"] == "classic_4lane" for chart in charts.values())
    assert all("input_lanes" not in note for chart in charts.values() for note in chart["notes"])
