"""Command-line entry point for local jobs."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Callable

from echoloop_worker.audio import AudioError
from echoloop_worker.jobs.audio import run_analysis_job, run_probe_job, run_regenerate_job
from echoloop_worker.jobs.health import run_health_check
from echoloop_worker.jobs.youtube import (
    run_import_youtube_batch_job,
    run_import_youtube_job,
    run_probe_youtube_job,
    run_probe_youtube_playlist_job,
    run_rollback_ytdlp_job,
    run_update_ytdlp_job,
    run_verify_ytdlp_job,
)
from echoloop_worker.logging.jsonl import write_event
from echoloop_worker.song_pack import SongPackError
from echoloop_worker.source_adapters import SourceAdapterError


class WorkerError(Exception):
    """Expected, user-facing worker failure."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


JobHandler = Callable[[dict[str, Any], Callable[[str, float], None], Path | None], dict[str, Any]]
JOB_REGISTRY: dict[str, JobHandler] = {
    "probe_local_audio": run_probe_job,
    "analyze_local_audio": run_analysis_job,
    "regenerate_charts": run_regenerate_job,
    "probe_youtube": run_probe_youtube_job,
    "probe_youtube_playlist": run_probe_youtube_playlist_job,
    "import_youtube": run_import_youtube_job,
    "import_youtube_batch": run_import_youtube_batch_job,
    "verify_ytdlp": run_verify_ytdlp_job,
    "update_ytdlp": run_update_ytdlp_job,
    "rollback_ytdlp": run_rollback_ytdlp_job,
}


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    """Write JSON through a sibling temp file and replace the destination."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        for attempt in range(20):
            try:
                os.replace(temporary, path)
                return
            except PermissionError:
                if attempt == 19:
                    raise
                time.sleep(0.05)
    finally:
        temporary.unlink(missing_ok=True)


def read_request(path: Path) -> dict[str, Any]:
    """Parse and validate a version-one request."""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise WorkerError("invalid_json", f"request JSON could not be read: {error}") from error
    if not isinstance(payload, dict):
        raise WorkerError("invalid_request", "request root must be an object")
    required = {"schema_version", "job_id", "job_type", "output_dir"}
    missing = sorted(required - payload.keys())
    if missing:
        raise WorkerError("invalid_request", f"missing fields: {', '.join(missing)}")
    if payload["schema_version"] not in {1, 2}:
        raise WorkerError("unsupported_schema", "schema_version must be 1 or 2")
    allowed = {"health_check", *JOB_REGISTRY.keys()}
    if not isinstance(payload["job_type"], str) or payload["job_type"] not in allowed:
        raise WorkerError("unsupported_job", f"unsupported job_type: {payload['job_type']}")
    if not isinstance(payload["output_dir"], str) or not payload["output_dir"]:
        raise WorkerError("invalid_request", "output_dir must be a non-empty string")
    if "payload" in payload and not isinstance(payload["payload"], dict):
        raise WorkerError("invalid_request", "payload must be an object")
    return payload


def status(job_id: str, job_type: str, state: str, message: str = "", **extra: Any) -> dict[str, Any]:
    """Build a status record."""
    return {
        "schema_version": 1 if job_type == "health_check" else 2,
        "job_id": job_id,
        "job_type": job_type,
        "state": state,
        "progress": 1.0 if state == "completed" else 0.0,
        "updated_at": datetime.now(UTC).isoformat(),
        "message": message,
        **extra,
    }


def run(request_path: Path, status_path: Path, log_path: Path) -> int:
    """Run one request and return a process exit code."""
    job_id = "unknown"
    job_type = "unknown"
    try:
        request = read_request(request_path)
        job_id = str(request["job_id"])
        job_type = str(request["job_type"])
        output_dir = Path(str(request["output_dir"]))
        cancel_file = Path(str(request.get("cancel_file", ""))) if request.get("cancel_file") else None
        write_event(log_path, "job_started", job_id=job_id, job_type=job_type)
        if cancel_file is not None and cancel_file.exists():
            atomic_write_json(status_path, status(job_id, job_type, "cancelled", "cancel file found"))
            write_event(log_path, "job_cancelled", job_id=job_id)
            return 2
        output_dir.mkdir(parents=True, exist_ok=True)
        if job_type == "health_check":
            atomic_write_json(status_path, status(job_id, job_type, "running", "health check started"))
            result = run_health_check()
            atomic_write_json(output_dir / "health.json", result)
            atomic_write_json(status_path, status(job_id, job_type, "completed", "health check complete", result=result))
        else:
            handler = JOB_REGISTRY[job_type]
            payload = dict(request.get("payload", {}))
            payload["_output_dir"] = str(output_dir)
            payload["_job_id"] = job_id

            def update_stage(stage_name: str, progress: float) -> None:
                atomic_write_json(
                    status_path,
                    status(
                        job_id,
                        job_type,
                        "running",
                        stage_name,
                        stage=stage_name,
                        message_key=f"job.{stage_name}",
                        progress=max(0.0, min(1.0, progress)),
                        error=None,
                    ),
                )

            update_stage("validating_request", 0.0)
            result = handler(payload, update_stage, cancel_file)
            atomic_write_json(status_path, status(job_id, job_type, "completed", "completed", result=result, stage="completed", message_key="job.completed", error=None))
        write_event(log_path, "job_completed", job_id=job_id)
        return 0
    except (WorkerError, AudioError, SongPackError, SourceAdapterError) as error:
        error_code = getattr(error, "code", "internal_error")
        state = "cancelled" if error_code == "JOB_CANCELLED" else "failed"
        atomic_write_json(status_path, status(job_id, job_type, state, str(error), error_code=error_code))
        write_event(log_path, "job_cancelled" if state == "cancelled" else "job_failed", job_id=job_id, error_code=error_code)
        return 2 if state == "cancelled" else 1
    except Exception as error:  # pragma: no cover - final safety boundary
        atomic_write_json(status_path, status(job_id, job_type, "failed", str(error), error_code="internal_error", error=str(error)))
        write_event(log_path, "job_failed", job_id=job_id, error_code="internal_error")
        return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="ECHOLOOP offline worker")
    parser.add_argument("--request", type=Path, help="path to request.json")
    parser.add_argument("--status", type=Path, help="path to status.json")
    parser.add_argument("--log", type=Path, help="path to worker.jsonl")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.request is None:
        return 0
    if args.status is None or args.log is None:
        print("--status and --log are required with --request", file=sys.stderr)
        return 2
    return run(args.request, args.status, args.log)


if __name__ == "__main__":
    raise SystemExit(main())
