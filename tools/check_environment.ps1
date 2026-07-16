param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw "Python 3.11 was not found on PATH." }
Write-Output ("Python: " + $python.Source)
python --version

if ($GodotPath) {
    if (-not (Test-Path -LiteralPath $GodotPath)) { throw "GodotPath does not exist: $GodotPath" }
    Write-Output ("Godot: " + (Resolve-Path -LiteralPath $GodotPath).Path)
    exit 0
}

$godot = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godot) { $godot = Get-Command godot4 -ErrorAction SilentlyContinue }
if ($godot) {
    Write-Output ("Godot: " + $godot.Source)
    & $godot.Source --version
    exit 0
}
Write-Output "Godot: NOT FOUND (pass -GodotPath or install Godot 4.7.1 Standard)"
exit 2

