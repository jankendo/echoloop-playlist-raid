$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "run_python_tests.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "run_godot_tests.ps1")
exit $LASTEXITCODE

