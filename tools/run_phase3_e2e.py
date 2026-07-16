"""Run the copyright-free local-audio Phase 3 pipeline end to end."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "worker" / "src"))

from echoloop_worker.cli import atomic_write_json, run  # noqa: E402


def main() -> int:
    fixture = ROOT / "fixtures" / "generated_audio" / "test_song.wav"
    with tempfile.TemporaryDirectory(prefix="echoloop-phase3-e2e-") as temporary:
        work = Path(temporary)
        request = work / "request.json"
        status = work / "status.json"
        log = work / "worker.jsonl"
        atomic_write_json(
            request,
            {
                "schema_version": 2,
                "job_id": "phase3-e2e",
                "job_type": "analyze_local_audio",
                "output_dir": str(work / "output"),
                "payload": {
                    "source_path": str(fixture),
                    "project_root": str(ROOT),
                    "store_root": str(work / "library"),
                    "backend": "deterministic_test",
                    "test_bpm": 120,
                    "test_meter": 4,
                },
            },
        )
        exit_code = run(request, status, log)
        if exit_code != 0:
            print(status.read_text(encoding="utf-8"), file=sys.stderr)
            return exit_code
        payload = json.loads(status.read_text(encoding="utf-8"))
        result = payload.get("result", {})
        manifest = Path(str(result["manifest_path"]))
        chart_paths = [Path(str(value)) for value in result["chart_paths"]]
        assert payload["state"] == "completed"
        assert (manifest / "playback.ogg").is_file()
        assert (manifest / "analysis.json").is_file()
        assert len(chart_paths) == 4
        assert all(path.is_file() for path in chart_paths)
        assert len({json.loads(path.read_text(encoding="utf-8"))["seed"] for path in chart_paths}) == 4
        print(
            "ECHOLOOP Phase 3 E2E: PASS "
            f"backend={result['backend']} charts=4 processing_ms={result['processing_duration_ms']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
