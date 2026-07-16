"""Explicitly download and validate Beat This! checkpoints.

This file is intentionally never called by normal game startup or normal CI.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _checkpoint_files(root: Path, model_name: str) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file() and model_name.lower() in path.name.lower()
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models-root", type=Path, default=Path(".models"))
    parser.add_argument("--models", nargs="+", default=["final0", "small0"])
    parser.add_argument("--python-executable", default=sys.executable)
    args = parser.parse_args()
    root = args.models_root.resolve() / "beat_this"
    root.mkdir(parents=True, exist_ok=True)
    os.environ["TORCH_HOME"] = str(root / "torch")
    try:
        import torch  # type: ignore[import-not-found]
        from beat_this.inference import load_model  # type: ignore[import-not-found]
    except ImportError as error:
        print(f"Beat This! prefetch unavailable: {error}", file=sys.stderr)
        return 2
    entries: dict[str, Any] = {}
    for model_name in args.models:
        print(f"prefetching Beat This! {model_name}", flush=True)
        try:
            model = load_model(model_name, device="cpu")
            model.eval()
            files = _checkpoint_files(root, model_name)
            if not files:
                files = _checkpoint_files(Path(torch.hub.get_dir()), model_name)
            if not files:
                raise RuntimeError("checkpoint file was not found after load_model")
            entries[model_name] = {
                "files": [
                    {"path": str(path), "size": path.stat().st_size, "sha256": _sha256(path)}
                    for path in files
                ],
                "device": "cpu",
                "loaded": True,
            }
        except Exception as error:
            print(f"model {model_name} failed: {error}", file=sys.stderr)
            return 1
    manifest = {
        "schema_version": 1,
        "generated_at": datetime.now(UTC).isoformat(),
        "python": args.python_executable,
        "torch": torch.__version__,
        "models": entries,
    }
    (root / "models.manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(root / "models.manifest.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
