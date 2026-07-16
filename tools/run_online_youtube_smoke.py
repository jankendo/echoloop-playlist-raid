"""Explicit, manual-only YouTube smoke test.

This script is never called by normal CI. The caller must affirm rights for the
given short test asset; the URL itself is not written to the report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Any

from echoloop_worker.jobs.youtube import run_import_youtube_job
from echoloop_worker.source_adapters import SourceAdapterError


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--rights-confirmed", action="store_true")
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--store-root", type=Path)
    parser.add_argument("--report", type=Path, default=Path(".runtime/reports/online-youtube-smoke.json"))
    args = parser.parse_args()
    if not args.rights_confirmed:
        parser.error("--rights-confirmed is required for any online download")
    report_path = args.report.resolve()
    output_root = Path(tempfile.mkdtemp(prefix="echoloop-online-youtube-"))
    store_root = (args.store_root or (output_root / "songs")).resolve()
    status: list[dict[str, Any]] = []

    def stage(name: str, progress: float) -> None:
        status.append({"stage": name, "progress": round(progress, 4)})

    payload = {
        "url": args.url,
        "rights_confirmed": True,
        "project_root": str(args.project_root.resolve()),
        "store_root": str(store_root),
        "_output_dir": str(output_root),
        "_job_id": "online-youtube-smoke",
        "backend": "librosa",
        "min_seconds": 5,
    }
    result: dict[str, Any] = {
        "schema_version": 1,
        "url_sha256": hashlib.sha256(args.url.encode("utf-8")).hexdigest(),
        "rights_confirmed": True,
    }
    try:
        result["outcome"] = "passed"
        result["import"] = run_import_youtube_job(payload, stage, None)
    except SourceAdapterError as error:
        result["outcome"] = "failed"
        result["error_code"] = error.code
        result["retryable"] = error.retryable
        result["message"] = str(error)
        result["stages"] = status
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return 1
    result["stages"] = status
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"outcome": result["outcome"], "report": str(report_path), "song_uuid": result["import"].get("song_uuid", "")}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
