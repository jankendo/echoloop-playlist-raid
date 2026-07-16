$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$env:PYTHONPATH = Join-Path $root "worker/src"
python tools/generate_fixtures.py
python -m pytest worker/tests -q
python -m ruff check worker/src worker/tests tools/generate_fixtures.py
python -m mypy worker/src
