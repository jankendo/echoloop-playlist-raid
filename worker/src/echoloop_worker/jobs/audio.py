"""Audio-analysis jobs exposed through the worker registry."""

from __future__ import annotations

import json
import shutil
import tempfile
import time
from pathlib import Path
from typing import Any, Callable

from echoloop_worker.analysis import analyze_local_audio
from echoloop_worker.audio import AudioError, convert_audio, probe_local_audio, sha256_file
from echoloop_worker.charts import generate_all_charts
from echoloop_worker.song_pack import SongPackError, SongPackStore
from echoloop_worker.tracking import DeterministicTestBeatTracker


StageCallback = Callable[[str, float], None]


def _cancelled(cancel_file: Path | None) -> bool:
    return cancel_file is not None and cancel_file.exists()


def _check_cancel(cancel_file: Path | None) -> None:
    if _cancelled(cancel_file):
        raise AudioError("JOB_CANCELLED", "解析をキャンセルしました")


def run_probe_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    source = Path(str(payload.get("source_path", "")))
    stage("validating_request", 0.05)
    _check_cancel(cancel_file)
    result = probe_local_audio(
        source,
        ffprobe_path=_optional_string(payload.get("ffprobe_path")),
        project_root=_optional_path(payload.get("project_root")),
        min_seconds=float(payload.get("min_seconds", 30.0)),
        max_seconds=float(payload.get("max_seconds", 900.0)),
        max_bytes=int(payload.get("max_bytes", 1_073_741_824)),
    )
    stage("hashing_audio", 0.85)
    value = result.as_dict(audio_sha256=sha256_file(result.path))
    stage("completed", 1.0)
    return value


def run_analysis_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    started = time.perf_counter()
    source = Path(str(payload.get("source_path", "")))
    source_type = str(payload.get("source_type", "local"))
    source_metadata = payload.get("source_metadata")
    if not isinstance(source_metadata, dict):
        source_metadata = {}
    project_root = _optional_path(payload.get("project_root"))
    stage("validating_request", 0.02)
    _check_cancel(cancel_file)
    stage("probing_audio", 0.08)
    probe = probe_local_audio(
        source,
        ffprobe_path=_optional_string(payload.get("ffprobe_path")),
        project_root=project_root,
        min_seconds=float(payload.get("min_seconds", 5.0 if source_type == "youtube" else 30.0)),
        max_seconds=float(payload.get("max_seconds", 900.0)),
        max_bytes=int(payload.get("max_bytes", 1_073_741_824)),
    )
    stage("hashing_audio", 0.12)
    audio_sha256 = sha256_file(probe.path)
    _check_cancel(cancel_file)
    stage("checking_duplicate", 0.16)
    store = SongPackStore(Path(str(payload.get("store_root", source.parent / "echoloop-data"))))
    duplicate = store.find_by_hash(audio_sha256)
    if duplicate is not None and str(payload.get("duplicate_policy", "reject")) == "reject":
        raise SongPackError("LOCAL_AUDIO_DUPLICATE", "同じ音源はすでに登録されています")
    source_duplicate = store.find_by_source(str(source_metadata.get("extractor", "")), str(source_metadata.get("source_id", "")))
    if source_duplicate is not None and str(payload.get("duplicate_policy", "reject")) == "reject":
        raise SongPackError("SONG_PACK_ALREADY_EXISTS", "同じ取得元の音源はすでに登録されています")
    temporary_root = Path(tempfile.mkdtemp(prefix="echoloop-analysis-"))
    try:
        stage("copying_source", 0.19)
        copied_source = temporary_root / f"source_audio{probe.path.suffix.lower()}"
        shutil.copy2(probe.path, copied_source)
        _check_cancel(cancel_file)
        playback = temporary_root / "playback.ogg"
        analysis_wav = temporary_root / "analysis.wav"
        stage("converting_playback", 0.24)
        convert_audio(
            copied_source,
            playback,
            analysis_wav,
            ffmpeg_path=_optional_string(payload.get("ffmpeg_path")),
            project_root=project_root,
            cancel_check=lambda: _cancelled(cancel_file),
        )
        stage("converting_analysis", 0.29)
        stage("measuring_loudness", 0.33)
        preferred = str(payload.get("backend", "auto"))
        tracker = None
        if preferred == "deterministic_test":
            tracker = DeterministicTestBeatTracker(
                bpm=float(payload.get("test_bpm", 120.0)),
                meter=int(payload.get("test_meter", 4)),
                duration_seconds=probe.duration_seconds,
            )
        stage("loading_beat_model", 0.38)
        stage("tracking_beats", 0.45)
        analysis = analyze_local_audio(
            analysis_wav,
            audio_sha256=audio_sha256,
            tracker=tracker,
            preferred_backend=preferred,
            model=str(payload.get("model", "final0")),
        )
        stage("tracking_downbeats", 0.50)
        stage("analyzing_onsets", 0.58)
        stage("analyzing_bands", 0.63)
        stage("analyzing_structure", 0.68)
        stage("building_beat_map", 0.72)
        charts: dict[str, dict[str, Any]] = {}
        for difficulty, progress in (("easy", 0.77), ("normal", 0.80), ("hard", 0.83), ("expert", 0.86)):
            _check_cancel(cancel_file)
            stage(f"generating_{difficulty}", progress)
            charts[difficulty] = generate_all_charts(analysis, audio_sha256=audio_sha256)[difficulty]
        stage("validating_charts", 0.89)
        stage("simulating_gameplay", 0.92)
        _check_cancel(cancel_file)
        stage("writing_song_pack", 0.96)
        manifest_path = store.write_pack(
            copied_source,
            playback_source=playback,
            probe={**probe.as_dict(audio_sha256=audio_sha256), "audio_sha256": audio_sha256},
            analysis=analysis,
            charts=charts,
            title=str(payload.get("title", probe.tags.get("title", probe.path.stem))),
            artist=str(payload.get("artist", probe.tags.get("artist", "Local Audio"))),
            source_metadata=source_metadata,
        )
        stage("completed", 1.0)
        return {
            "song_uuid": manifest_path.name,
            "manifest_path": str(manifest_path),
            "audio_sha256": audio_sha256,
            "backend": analysis.get("beat_backend"),
            "duration_ms": analysis.get("duration_ms"),
            "chart_paths": [str(manifest_path / "charts" / f"{difficulty}.json") for difficulty in charts],
            "processing_duration_ms": round((time.perf_counter() - started) * 1000.0, 3),
        }
    finally:
        shutil.rmtree(temporary_root, ignore_errors=True)


def run_regenerate_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    stage("validating_request", 0.05)
    _check_cancel(cancel_file)
    store = SongPackStore(Path(str(payload.get("store_root", ""))))
    song_uuid = str(payload.get("song_uuid", ""))
    pack = store.read_pack(song_uuid)
    if pack is None:
        raise SongPackError("LOCAL_FILE_NOT_FOUND", "登録曲が見つかりません")
    pack_path = Path(str(pack["path"]))
    analysis_path = pack_path / "analysis.json"
    analysis = json.loads(analysis_path.read_text(encoding="utf-8"))
    override_path = pack_path / "user_override.json"
    override = json.loads(override_path.read_text(encoding="utf-8")) if override_path.exists() else {}
    if not isinstance(analysis, dict) or not isinstance(override, dict):
        raise SongPackError("SCHEMA_UNSUPPORTED", "解析結果または修正値が不正です")
    stage("generating_easy", 0.25)
    charts = generate_all_charts(analysis, audio_sha256=str(pack.get("audio_sha256", "")), user_override=override)
    _check_cancel(cancel_file)
    stage("validating_charts", 0.70)
    store.replace_charts(song_uuid, charts)
    stage("completed", 1.0)
    return {"song_uuid": song_uuid, "chart_paths": [str(pack_path / "charts" / f"{difficulty}.json") for difficulty in charts]}


def _optional_string(value: Any) -> str | None:
    return str(value) if value else None


def _optional_path(value: Any) -> Path | None:
    return Path(str(value)) if value else None
