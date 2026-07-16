from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import wave
from pathlib import Path

import pytest

from echoloop_worker.audio import (
    AudioError,
    build_ffmpeg_args,
    probe_local_audio,
    validate_local_path,
)
from echoloop_worker.analysis import analyze_local_audio
from echoloop_worker.charts import generate_all_charts
from echoloop_worker.cli import JOB_REGISTRY, read_request
from echoloop_worker.song_pack import SongPackStore
from echoloop_worker.tracking import DeterministicTestBeatTracker, LibrosaBeatTracker


ROOT = Path(__file__).resolve().parents[2]


def _write_synthetic_wav(path: Path, seconds: float = 2.0) -> None:
    sample_rate = 8_000
    frames = int(sample_rate * seconds)
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(sample_rate)
        data = bytearray()
        for index in range(frames):
            pulse = 0.75 if (index % sample_rate) < 40 else 0.0
            value = int(32767 * pulse)
            data.extend(value.to_bytes(2, byteorder="little", signed=True))
        stream.writeframes(data)


def test_ffmpeg_arguments_are_an_argument_vector() -> None:
    arguments = build_ffmpeg_args(Path("ffmpeg.exe"), Path("C:/日本語/track name.wav"), Path("out.ogg"), output_kind="playback")
    assert arguments[0] == "ffmpeg.exe"
    assert str(Path("C:/日本語/track name.wav")) in arguments
    assert "-i" in arguments
    assert "-map" in arguments
    assert "0:a:0" in arguments


def test_local_path_validation_rejects_url_and_unsupported_file(tmp_path: Path) -> None:
    with pytest.raises(AudioError, match="ローカル音源"):
        validate_local_path("https://example.invalid/song.mp3")
    unsupported = tmp_path / "track.txt"
    unsupported.write_text("audio")
    with pytest.raises(AudioError, match="対応していない"):
        validate_local_path(unsupported)


def test_probe_reads_fixture_when_ffprobe_is_available() -> None:
    if shutil.which("ffprobe") is None:
        pytest.skip("ffprobe is not installed")
    result = probe_local_audio(ROOT / "fixtures/generated_audio/test_song.wav")
    assert result.codec_name == "pcm_s16le"
    assert result.duration_seconds > 30.0
    assert result.channels == 1


def test_tracker_supports_variable_tempo_and_meters() -> None:
    tracker = DeterministicTestBeatTracker(
        meter=3,
        duration_seconds=12.0,
        tempo_segments=[
            {"start_ms": 0.0, "end_ms": 6_000.0, "bpm": 60.0},
            {"start_ms": 6_000.0, "end_ms": 12_000.0, "bpm": 180.0},
        ],
    )
    result = tracker.track(Path("synthetic.wav"))
    assert result.meter == 3
    assert result.beats_seconds[1] - result.beats_seconds[0] == pytest.approx(1.0)
    assert result.beats_seconds[-1] - result.beats_seconds[-2] == pytest.approx(1 / 3, abs=1e-5)
    assert len(result.downbeats_seconds) > 1


@pytest.mark.skipif(importlib.util.find_spec("librosa") is None, reason="librosa is optional")
def test_librosa_tracker_returns_audio_time_scale(tmp_path: Path) -> None:
    audio = tmp_path / "tracker.wav"
    _write_synthetic_wav(audio, seconds=30.0)
    result = LibrosaBeatTracker().track(audio)
    assert result.beats_seconds
    assert result.beats_seconds[-1] > 20.0


def test_analysis_and_charts_are_deterministic_and_distinct(tmp_path: Path) -> None:
    audio = tmp_path / "日本語 track.wav"
    _write_synthetic_wav(audio)
    digest = hashlib.sha256(audio.read_bytes()).hexdigest()
    analysis = analyze_local_audio(
        audio,
        audio_sha256=digest,
        tracker=DeterministicTestBeatTracker(bpm=120.0, duration_seconds=2.0),
    )
    first = generate_all_charts(analysis)
    second = generate_all_charts(analysis)
    assert first == second
    assert len({len(chart["notes"]) for chart in first.values()}) >= 3
    assert all(chart["schema_version"] == 2 for chart in first.values())
    assert all(chart["quality"]["same_lane_violations"] == 0 for chart in first.values())


def test_song_pack_is_atomic_and_duplicate_checked(tmp_path: Path) -> None:
    source = tmp_path / "source.wav"
    source.write_bytes(b"safe local source")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    store = SongPackStore(tmp_path / "library")
    analysis = {
        "duration_ms": 2_000,
        "bpm_summary": 120.0,
        "audio_sha256": digest,
        "beat_backend": "deterministic_test",
        "warnings": [],
    }
    charts = {"easy": {"schema_version": 2, "notes": []}}
    pack = store.write_pack(source, probe={"audio_sha256": digest}, analysis=analysis, charts=charts, title="Test", artist="Local")
    assert (pack / "manifest.json").exists()
    assert (pack / "charts/easy.json").exists()
    assert not list((tmp_path / "library/songs").glob(".tmp-*"))
    with pytest.raises(Exception, match="同じ音源"):
        store.write_pack(source, probe={"audio_sha256": digest}, analysis=analysis, charts=charts, title="Test", artist="Local")


def test_job_registry_and_schema_v2_request(tmp_path: Path) -> None:
    assert set(JOB_REGISTRY) == {
        "probe_local_audio",
        "analyze_local_audio",
        "regenerate_charts",
        "probe_youtube",
        "probe_youtube_playlist",
        "import_youtube",
        "import_youtube_batch",
        "verify_ytdlp",
        "update_ytdlp",
        "rollback_ytdlp",
    }
    request = tmp_path / "request.json"
    request.write_text(json.dumps({"schema_version": 2, "job_id": "job", "job_type": "probe_local_audio", "output_dir": str(tmp_path / "out"), "payload": {}}))
    assert read_request(request)["job_type"] == "probe_local_audio"
