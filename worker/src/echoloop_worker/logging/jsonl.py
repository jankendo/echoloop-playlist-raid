"""JSON Lines logging with no secrets or media payloads."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


def write_event(path: Path, event: str, **fields: Any) -> None:
    """Append one structured event atomically at the line level."""
    path.parent.mkdir(parents=True, exist_ok=True)
    safe_fields = {key: value for key, value in fields.items() if key not in {"token", "cookie"}}
    record = {"timestamp": datetime.now(UTC).isoformat(), "event": event, **safe_fields}
    with path.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")

