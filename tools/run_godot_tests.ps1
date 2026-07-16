param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
if (-not $GodotPath) {
    $godot = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $godot) { $godot = Get-Command godot4 -ErrorAction SilentlyContinue }
    if ($godot) { $GodotPath = $godot.Source }
}
if (-not $GodotPath) { throw "Godot 4.7.1 was not found. Pass -GodotPath." }
& $GodotPath --headless --path (Join-Path $PSScriptRoot "../godot") -s res://tests/run_all.gd
if ($LASTEXITCODE -ne 0) { throw "Godot headless tests failed with exit code $LASTEXITCODE" }

