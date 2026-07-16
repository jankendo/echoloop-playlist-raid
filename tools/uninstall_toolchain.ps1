param([switch]$RemoveCache)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$targets = @((Join-Path $root ".tools"), (Join-Path $root ".runtime"), (Join-Path $root ".models"))
if ($RemoveCache) { $targets += Join-Path $root ".cache" }
foreach ($target in $targets) {
    $resolved = [IO.Path]::GetFullPath($target)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($root + "\"), [StringComparison]::OrdinalIgnoreCase)) { throw "unsafe uninstall target: $resolved" }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -Recurse -Force -LiteralPath $resolved; Write-Host "removed $resolved" }
}
