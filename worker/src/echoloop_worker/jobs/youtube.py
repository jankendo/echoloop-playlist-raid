"""YouTube probe, import, playlist, and tool-management jobs."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any, Callable

from echoloop_worker.jobs.audio import run_analysis_job
from echoloop_worker.source_adapters import (
    SourceAdapterError,
    adapter_from_payload,
    installed_ytdlp_versions,
    validate_payload_keys,
)


StageCallback = Callable[[str, float], None]


def _cancelled(cancel_file: Path | None) -> bool:
    return cancel_file is not None and cancel_file.exists()


def _check_cancel(cancel_file: Path | None) -> None:
    if _cancelled(cancel_file):
        raise SourceAdapterError("JOB_CANCELLED", "取り込みをキャンセルしました")


def run_probe_youtube_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    validate_payload_keys(payload)
    stage("validating_youtube_url", 0.05)
    _check_cancel(cancel_file)
    adapter = adapter_from_payload(payload)
    stage("probing_youtube_metadata", 0.45)
    metadata = adapter.probe(str(payload.get("url", "")))
    stage("completed", 1.0)
    return {"metadata": metadata}


def run_probe_youtube_playlist_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    validate_payload_keys(payload)
    stage("validating_youtube_playlist", 0.05)
    _check_cancel(cancel_file)
    adapter = adapter_from_payload(payload)
    stage("probing_youtube_playlist_flat", 0.45)
    result = adapter.probe(str(payload.get("url", "")), playlist=True)
    entries = list(result.get("entries", []))
    max_entries = int(payload.get("max_entries", 500))
    result["entries"] = entries[:max(1, min(5000, max_entries))]
    result["entry_count"] = len(result["entries"])
    stage("completed", 1.0)
    return result


def run_import_youtube_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    validate_payload_keys(payload)
    job_id = str(payload.get("_job_id", uuid.uuid4().hex))
    output_root = Path(str(payload.get("_output_dir", ""))).resolve()
    if not output_root:
        raise SourceAdapterError("INVALID_REQUEST", "output_dirがありません")
    adapter = adapter_from_payload(payload)
    stage("probing_youtube_metadata", 0.08)
    metadata = adapter.probe(str(payload.get("url", "")))
    _check_cancel(cancel_file)

    def download_hook(progress: dict[str, Any]) -> None:
        _check_cancel(cancel_file)
        status = str(progress.get("status", ""))
        if status == "downloading":
            total = float(progress.get("total_bytes") or progress.get("total_bytes_estimate") or 0.0)
            done = float(progress.get("downloaded_bytes") or 0.0)
            fraction = done / total if total > 0 else 0.0
            stage("downloading_audio", 0.12 + max(0.0, min(1.0, fraction)) * 0.38)
        elif status == "finished":
            stage("downloaded_audio", 0.52)

    downloaded: Path | None = None
    try:
        downloaded = adapter.download_audio(str(payload.get("url", "")), job_id=job_id, output_root=output_root, hook=download_hook)
        _check_cancel(cancel_file)
        stage("analyzing_downloaded_audio", 0.55)
        analysis_payload = {
            key: value
            for key, value in payload.items()
            if key in {"project_root", "store_root", "ffmpeg_path", "ffprobe_path", "min_seconds", "max_seconds", "max_bytes", "duplicate_policy", "backend", "model", "test_bpm", "test_meter"}
        }
        analysis_payload.update(
            {
                "source_path": str(downloaded),
                "source_type": "youtube",
                "source_metadata": metadata,
                "title": str(payload.get("title") or metadata.get("title", "YouTube Audio")),
                "artist": str(payload.get("artist") or metadata.get("artist", "YouTube")),
            }
        )
        result = run_analysis_job(analysis_payload, lambda name, value: stage(name, 0.55 + value * 0.42), cancel_file)
        stage("completed", 1.0)
        return {**result, "source": metadata}
    finally:
        if downloaded is not None:
            shutil.rmtree(downloaded.parent, ignore_errors=True)


def run_import_youtube_batch_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    validate_payload_keys(payload)
    output_root = Path(str(payload.get("_output_dir", ""))).resolve()
    state_path = output_root / "batch.state.json"
    state = _read_json(state_path, {"schema_version": 1, "completed": {}, "failed": {}})
    adapter = adapter_from_payload(payload)
    stage("probing_youtube_playlist_flat", 0.04)
    playlist = adapter.probe(str(payload.get("url", "")), playlist=True)
    entries = _select_entries(playlist.get("entries", []), payload)
    retry_count = max(0, min(3, int(payload.get("retry_count", 1))))
    results: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for index, entry in enumerate(entries):
        _check_cancel(cancel_file)
        source_id = str(entry.get("source_id", ""))
        if source_id in state.get("completed", {}):
            results.append(state["completed"][source_id])
            continue
        url = str(entry.get("webpage_url", ""))
        item_payload = dict(payload)
        item_payload.update({"url": url, "_job_id": f"{payload.get('_job_id', 'batch')}-{source_id}"})
        last_error = ""
        for attempt in range(retry_count + 1):
            try:
                def item_stage(name: str, value: float, i: int = index, total: int = max(1, len(entries))) -> None:
                    stage(f"item_{i + 1}_{name}", 0.06 + ((i + value) / total) * 0.90)

                item = run_import_youtube_job(item_payload, item_stage, cancel_file)
                state.setdefault("completed", {})[source_id] = item
                results.append(item)
                _write_json_atomic(state_path, state)
                last_error = ""
                break
            except SourceAdapterError as error:
                last_error = error.code
                if attempt >= retry_count:
                    break
        if last_error:
            failure = {"source_id": source_id, "title": entry.get("title", ""), "error_code": last_error, "skipped": True}
            state.setdefault("failed", {})[source_id] = failure
            failures.append(failure)
            _write_json_atomic(state_path, state)
    stage("completed", 1.0)
    return {"playlist": {key: value for key, value in playlist.items() if key != "entries"}, "items": results, "failures": failures, "resumed": True}


def run_verify_ytdlp_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    validate_payload_keys(payload)
    stage("verifying_ytdlp", 0.25)
    _check_cancel(cancel_file)
    versions = installed_ytdlp_versions()
    deno = adapter_from_payload(payload).deno_path
    result: dict[str, Any] = {"versions": versions, "deno_path_present": bool(deno and Path(deno).is_file())}
    if payload.get("url"):
        stage("probing_youtube_metadata", 0.60)
        result["metadata"] = adapter_from_payload(payload).probe(str(payload["url"]))
    stage("completed", 1.0)
    return result


def run_update_ytdlp_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    del payload
    stage("updating_ytdlp", 0.20)
    _check_cancel(cancel_file)
    completed = subprocess.run([sys.executable, "-m", "pip", "install", "--upgrade", "yt-dlp[default]", "yt-dlp-ejs==0.8.0"], check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise SourceAdapterError("YTDLP_UPDATE_FAILED", "yt-dlpの更新に失敗しました", retryable=True)
    stage("completed", 1.0)
    return {"versions": installed_ytdlp_versions()}


def run_rollback_ytdlp_job(payload: dict[str, Any], stage: StageCallback, cancel_file: Path | None) -> dict[str, Any]:
    version = str(payload.get("version", ""))
    if not re.fullmatch(r"\d{4}\.\d{2}\.\d{2}(?:\.\d+)?", version):
        raise SourceAdapterError("YTDLP_VERSION_INVALID", "yt-dlpのrollback版が不正です")
    stage("rolling_back_ytdlp", 0.20)
    _check_cancel(cancel_file)
    completed = subprocess.run([sys.executable, "-m", "pip", "install", f"yt-dlp[default]=={version}", "yt-dlp-ejs==0.8.0"], check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise SourceAdapterError("YTDLP_ROLLBACK_FAILED", "yt-dlpのrollbackに失敗しました", retryable=True)
    stage("completed", 1.0)
    return {"versions": installed_ytdlp_versions()}


def _select_entries(entries: Any, payload: dict[str, Any]) -> list[dict[str, Any]]:
    values = [entry for entry in entries if isinstance(entry, dict)]
    query = str(payload.get("query", "")).strip().lower()
    if query:
        values = [entry for entry in values if query in str(entry.get("title", "")).lower() or query in str(entry.get("artist", "")).lower()]
    requested = payload.get("entries")
    if isinstance(requested, list) and requested:
        selected = {str(item) for item in requested}
        values = [entry for entry in values if str(entry.get("source_id", entry.get("playlist_index", ""))) in selected or str(entry.get("playlist_index", "")) in selected]
    sort_key = str(payload.get("sort", "index"))
    if sort_key == "title":
        values.sort(key=lambda entry: str(entry.get("title", "")).lower())
    elif sort_key == "duration":
        values.sort(key=lambda entry: float(entry.get("duration_seconds", 0.0)))
    else:
        values.sort(key=lambda entry: int(entry.get("playlist_index") or 0))
    return values


def _read_json(path: Path, fallback: dict[str, Any]) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else fallback
    except (OSError, json.JSONDecodeError):
        return fallback


def _write_json_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
