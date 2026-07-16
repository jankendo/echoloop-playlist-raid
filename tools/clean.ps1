$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
foreach ($path in @("dist", "worker/.pytest_cache", "worker/.mypy_cache", "worker/.ruff_cache")) {
    $target = Join-Path $root $path
    if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
python (Join-Path $PSScriptRoot "generate_fixtures.py")

