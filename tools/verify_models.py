"""Verify Beat This! checkpoint hashes and execute a real inference load."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models-root", type=Path, default=Path(".models"))
    parser.add_argument("--models", nargs="+", default=["final0", "small0"])
    parser.add_argument("--device", choices=["auto", "cpu", "cuda"], default="auto")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    root = args.models_root.resolve() / "beat_this"
    os.environ["TORCH_HOME"] = str(root / "torch")
    report: dict[str, Any] = {"models_root": str(root), "models": {}, "ok": True}
    try:
        import torch  # type: ignore[import-not-found]
        from beat_this.inference import load_model  # type: ignore[import-not-found]
    except ImportError as error:
        report["ok"] = False
        report["error"] = str(error)
        print(json.dumps(report) if args.json else report["error"])
        return 2
    device = "cuda" if args.device == "auto" and torch.cuda.is_available() else args.device
    if device == "cuda" and not torch.cuda.is_available():
        report["ok"] = False
        report["error"] = "CUDA requested but torch.cuda.is_available() is false"
    for model_name in args.models:
        files = sorted(
            path for path in root.rglob("*") if path.is_file() and model_name.lower() in path.name.lower()
        )
        entry: dict[str, Any] = {"files": [], "loaded": False, "device": device}
        for path in files:
            entry["files"].append({"path": str(path), "size": path.stat().st_size, "sha256": _sha256(path)})
        if not files:
            report["ok"] = False
            entry["error"] = "checkpoint missing"
        else:
            try:
                model = load_model(model_name, device=device)
                model.eval()
                entry["loaded"] = True
            except Exception as error:
                report["ok"] = False
                entry["error"] = str(error)
        report["models"][model_name] = entry
    if args.json:
        print(json.dumps(report, ensure_ascii=False))
    else:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
