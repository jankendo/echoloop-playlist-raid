param([string]$GodotPath = "")
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
& (Join-Path $PSScriptRoot "run_python_tests.ps1")
& (Join-Path $PSScriptRoot "run_godot_tests.ps1") -GodotPath $GodotPath
if (-not $GodotPath) {
	$managedGodot = Join-Path $root ".tools\godot\4.7.1-stable\Godot_v4.7.1-stable_win64_console.exe"
	if (Test-Path -LiteralPath $managedGodot) { $GodotPath = $managedGodot }
}
if (-not $GodotPath) {
    $godot = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $godot) { $godot = Get-Command godot4 -ErrorAction SilentlyContinue }
    if ($godot) { $GodotPath = $godot.Source }
}
if (-not $GodotPath) { throw "Godot executable is required for export." }
$rcedit = Join-Path $root ".tools\rcedit\2.0.0\rcedit-x64.exe"
if (Test-Path -LiteralPath $rcedit) {
	$env:PATH = (Split-Path -Parent $rcedit) + ";" + $env:PATH
}
$output = Join-Path $root "dist/windows/ECHOLOOP_PLAYLIST_RAID.exe"
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
$command = "$GodotPath --headless --path godot --export-release `"Windows Desktop`" $output"
Write-Output $command
$log = & $GodotPath --headless --path (Join-Path $root "godot") --export-release "Windows Desktop" $output 2>&1
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    $record = @"

## Last attempted build

Command: ``$command``

Exit code: $exitCode

````text
$($log -join "`n")
````

Result: environment-limited; no executable was claimed.
"@
    Add-Content -Path (Join-Path $root "docs/build.md") -Value $record
    throw "Godot export failed with exit code $exitCode"
}
Write-Output ($log -join "`n")
if (Test-Path -LiteralPath $rcedit) {
	& $rcedit $output --set-version-string ProductName "ECHOLOOP: PLAYLIST RAID" --set-version-string FileDescription "ECHOLOOP rhythm rogue-lite" --set-version-string CompanyName "ECHOLOOP" --set-file-version "0.4.0.0" --set-product-version "0.4.0.0"
	if ($LASTEXITCODE -ne 0) { throw "rcedit failed with exit code $LASTEXITCODE" }
	Write-Output "rcedit version resources applied: $rcedit"
} else {
	throw "rcedit is required for Phase 4 Windows metadata export: $rcedit"
}
Write-Output "Windows export succeeded: $output"
