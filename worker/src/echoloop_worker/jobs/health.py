"""Deterministic local health check."""

from __future__ import annotations

import platform
import sys
from datetime import UTC, datetime
from typing import Any


def run_health_check() -> dict[str, Any]:
    """Return diagnostics without touching the network or user media."""
    return {
        "worker_version": "0.1.0",
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "executable": sys.executable,
        "network": "disabled_by_design",
        "checked_at": datetime.now(UTC).isoformat(),
    }

