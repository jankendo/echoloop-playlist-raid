param(
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$YtDlpArgs
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$currentPath = Join-Path $root ".runtime\current.json"
if (-not (Test-Path -LiteralPath $currentPath)) { throw "current.json がありません。tools/bootstrap_all.ps1 -Mode Repair を先に実行してください。" }
$current = Get-Content -Raw -LiteralPath $currentPath | ConvertFrom-Json
$python = [string]$current.python.Python
if (-not (Test-Path -LiteralPath $python)) { throw "管理venvのPythonがありません: $python" }
if ($null -eq $YtDlpArgs -or $YtDlpArgs.Count -eq 0) { $YtDlpArgs = @("--help") }
& $python -m yt_dlp @YtDlpArgs
exit $LASTEXITCODE
