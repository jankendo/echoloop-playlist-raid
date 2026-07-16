from __future__ import annotations

import json
from pathlib import Path

import pytest

from echoloop_worker.cli import WorkerError, atomic_write_json, read_request, run


def request(tmp_path: Path) -> Path:
    path = tmp_path / "request.json"
    atomic_write_json(
        path,
        {"schema_version": 1, "job_id": "test-1", "job_type": "health_check", "output_dir": str(tmp_path / "out")},
    )
    return path


def test_health_check_writes_result_and_status(tmp_path: Path) -> None:
    result = run(request(tmp_path), tmp_path / "status.json", tmp_path / "worker.jsonl")
    assert result == 0
    assert json.loads((tmp_path / "out" / "health.json").read_text())['network'] == 'disabled_by_design'
    assert json.loads((tmp_path / "status.json").read_text())['state'] == 'completed'
    assert len((tmp_path / "worker.jsonl").read_text().splitlines()) == 2


def test_invalid_json_is_rejected(tmp_path: Path) -> None:
    bad = tmp_path / "bad.json"
    bad.write_text("{")
    with pytest.raises(WorkerError, match="could not be read"):
        read_request(bad)


def test_unsupported_job_is_rejected(tmp_path: Path) -> None:
    path = tmp_path / "request.json"
    atomic_write_json(path, {"schema_version": 1, "job_id": "x", "job_type": "download", "output_dir": "out"})
    with pytest.raises(WorkerError, match="unsupported job_type"):
        read_request(path)


def test_cancel_file_is_safe(tmp_path: Path) -> None:
    cancel = tmp_path / "cancel"
    cancel.touch()
    path = tmp_path / "request.json"
    atomic_write_json(
        path,
        {"schema_version": 1, "job_id": "x", "job_type": "health_check", "output_dir": str(tmp_path / "out"), "cancel_file": str(cancel)},
    )
    assert run(path, tmp_path / "status.json", tmp_path / "worker.jsonl") == 2
    assert json.loads((tmp_path / "status.json").read_text())['state'] == 'cancelled'

