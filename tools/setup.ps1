$ErrorActionPreference = "Stop"
python (Join-Path $PSScriptRoot "generate_fixtures.py")
python -m venv (Join-Path $PSScriptRoot "../worker/.venv")
& (Join-Path $PSScriptRoot "../worker/.venv/Scripts/python.exe") -m pip install -e (Join-Path $PSScriptRoot "../worker[dev]")

