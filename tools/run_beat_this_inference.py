"""Run real Beat This! inference for final0 and small0 without downloading."""

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path
from typing import Any


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", type=Path, default=Path("fixtures/generated_audio/test_song.wav"))
    parser.add_argument("--models-root", type=Path, default=Path(".models"))
    parser.add_argument("--device", choices=["auto", "cpu", "cuda"], default="auto")
    args = parser.parse_args()
    root = args.models_root.resolve() / "beat_this"
    os.environ["TORCH_HOME"] = str(root / "torch")
    import torch  # type: ignore[import-not-found]
    from beat_this.inference import File2Beats  # type: ignore[import-not-found]

    device = "cuda" if args.device == "auto" and torch.cuda.is_available() else args.device
    if device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA requested but not available")
    report: dict[str, Any] = {"audio": str(args.audio.resolve()), "device": device, "torch": torch.__version__, "models": {}}
    for model_name in ("final0", "small0"):
        started = time.perf_counter()
        runner = File2Beats(checkpoint_path=model_name, device=device, dbn=False)
        beats, downbeats = runner(str(args.audio.resolve()))
        beat_values = beats.tolist() if hasattr(beats, "tolist") else list(beats)
        downbeat_values = downbeats.tolist() if hasattr(downbeats, "tolist") else list(downbeats)
        report["models"][model_name] = {
            "beats": len(beat_values),
            "downbeats": len(downbeat_values),
            "duration_ms": round((time.perf_counter() - started) * 1000.0, 3),
        }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
