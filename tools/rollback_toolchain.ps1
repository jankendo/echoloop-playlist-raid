param([int]$Index = 0)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$path = Join-Path $root ".runtime\current.json"
if (-not (Test-Path -LiteralPath $path)) { throw "current.json がありません" }
$current = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
$history = @($current.history)
if ($Index -lt 0 -or $Index -ge $history.Count) { throw "rollback対象がありません" }
$target = $history[$Index]
$targetPath = [string]$target.python.Path
if (-not (Test-Path -LiteralPath $targetPath)) { throw "rollback対象のvenvがありません: $targetPath" }
$target.history = @($history | Where-Object { $_.python.Path -ne $targetPath } | Select-Object -First 3)
$target | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath "$path.tmp"
Move-Item -Force -LiteralPath "$path.tmp" -Destination $path
Write-Host "Rolled back toolchain to $targetPath"
