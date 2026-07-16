param([switch]$Quiet)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$currentPath = Join-Path $root ".runtime\current.json"
$checks = [ordered]@{}
function Check([string]$name, [bool]$ok, [string]$detail) { $checks[$name] = @{ ok = $ok; detail = $detail } }
if (-not (Test-Path -LiteralPath $currentPath)) { Check "current" $false "current.json not found"; $checks | ConvertTo-Json -Depth 5; exit 1 }
$current = Get-Content -Raw -LiteralPath $currentPath | ConvertFrom-Json
foreach ($toolName in @("Godot", "Deno", "Ffmpeg", "Ffprobe", "Rcedit")) {
    $value = $current.tools.$toolName
    $ok = $value -and (Test-Path -LiteralPath $value)
    Check $toolName $ok $(if ($value) { [string]$value } else { "missing" })
}
$python = [string]$current.python.Python
if (Test-Path -LiteralPath $python) {
    $probe = & $python -c "import sys, json; result={'python':sys.version.split()[0]}; import torch; result['torch']=torch.__version__; result['cuda_available']=bool(torch.cuda.is_available()); result['cuda_device']=torch.cuda.get_device_name(0) if torch.cuda.is_available() else ''; import yt_dlp; result['yt_dlp']=yt_dlp.version.__version__; import yt_dlp_ejs; result['yt_dlp_ejs']='installed'; import beat_this; result['beat_this']='installed'; print(json.dumps(result))" 2>&1
    if ($LASTEXITCODE -eq 0) { Check "python_runtime" $true ($probe -join " ") } else { Check "python_runtime" $false ($probe -join " ") }
    $cliVersion = & $python -m yt_dlp --version 2>&1
    Check "yt_dlp_cli" ($LASTEXITCODE -eq 0) ($cliVersion -join " ")
    $wrapper = Join-Path $root "tools\ytdlp.ps1"
    if (Test-Path -LiteralPath $wrapper) {
        $wrapperVersion = & pwsh -NoProfile -File $wrapper --version 2>&1
        Check "yt_dlp_wrapper" ($LASTEXITCODE -eq 0) ($wrapperVersion -join " ")
    } else { Check "yt_dlp_wrapper" $false "tools/ytdlp.ps1 not found" }
    & $python (Join-Path $root "tools/verify_models.py") --models-root (Join-Path $root ".models") --json
    Check "models" ($LASTEXITCODE -eq 0) "final0 and small0 inference cache"
} else { Check "python_runtime" $false "venv python missing"; Check "models" $false "python unavailable" }
$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value.ok }).Count
if (-not $Quiet) { $checks | ConvertTo-Json -Depth 8 }
if ($failed -gt 0) { exit 1 }
exit 0
