param(
    [ValidateSet("Install", "Repair", "Verify", "Update", "Rollback")][string]$Mode = "Verify",
    [string]$Version = "",
    [ValidateSet("Locked", "Nightly", "Stable")][string]$Channel = "Locked",
    [switch]$Force,
    [switch]$NoCache,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runtimeRoot = Join-Path $root ".runtime"
$currentPath = Join-Path $runtimeRoot "current.json"
$lockPath = Join-Path $root "toolchain.lock.json"
$reportPath = Join-Path $runtimeRoot "reports\ytdlp-install.json"

function Write-Report([hashtable]$report, [int]$exitCode = 0) {
    New-Item -ItemType Directory -Force -Path (Split-Path $reportPath) | Out-Null
    $report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $reportPath
    $report | ConvertTo-Json -Depth 12
    if ($exitCode -ne 0) { exit $exitCode }
}

function Invoke-Python([string]$python, [string[]]$pythonArgs) {
    & $python @pythonArgs
    if ($LASTEXITCODE -ne 0) { throw "Python command failed ($LASTEXITCODE): $($pythonArgs -join ' ')" }
}

function Invoke-Capture([string]$executable, [string[]]$arguments) {
    $output = & $executable @arguments 2>&1
    $exitCode = $LASTEXITCODE
    return @{ Output = ($output -join " ").Trim(); ExitCode = $exitCode }
}

try {
    if (-not (Test-Path -LiteralPath $currentPath)) { throw "current.json がありません。先に tools/bootstrap_all.ps1 -Mode Repair を実行してください。" }
    if (-not (Test-Path -LiteralPath $lockPath)) { throw "toolchain.lock.json がありません" }
    $current = Get-Content -Raw -LiteralPath $currentPath | ConvertFrom-Json
    $lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
    $python = [string]$current.python.Python
    if (-not (Test-Path -LiteralPath $python)) { throw "管理venvのPythonがありません: $python" }
    $ytdlpLock = $lock.python_packages.'yt-dlp'
    $ejsVersion = [string]$lock.python_packages.'yt-dlp-ejs'
    $lockedVersion = [string]$ytdlpLock.locked_version
    $stableVersion = [string]$ytdlpLock.stable_fallback
    if ([string]::IsNullOrWhiteSpace($lockedVersion)) { throw "toolchain.lock.json の yt-dlp.locked_version がありません" }
    if ([string]::IsNullOrWhiteSpace($stableVersion)) { throw "toolchain.lock.json の yt-dlp.stable_fallback がありません" }

    $selectedVersion = $Version.Trim()
    if ([string]::IsNullOrWhiteSpace($selectedVersion)) {
        if ($Channel -eq "Locked") { $selectedVersion = $lockedVersion }
        elseif ($Channel -eq "Stable") { $selectedVersion = $stableVersion }
    }
    if ($Mode -eq "Rollback" -and [string]::IsNullOrWhiteSpace($selectedVersion)) { throw "Rollbackには -Version が必要です" }
    if ($selectedVersion -and $selectedVersion -notmatch '^\d{4}\.\d{2}\.\d{2}(?:\.\d+)?(?:\.dev\d+)?$') { throw "yt-dlp versionが不正です: $selectedVersion" }

    $verify = {
        $versionResult = Invoke-Capture $python @("-m", "yt_dlp", "--version")
        $apiResult = Invoke-Capture $python @("-c", "import yt_dlp, yt_dlp_ejs; print(yt_dlp.version.__version__)")
        $deno = [string]$current.tools.Deno
        $ffmpeg = [string]$current.tools.Ffmpeg
        $ffprobe = [string]$current.tools.Ffprobe
        $checks = [ordered]@{
            python = @{ ok = $true; detail = $python }
            yt_dlp_cli = @{ ok = $versionResult.ExitCode -eq 0; detail = $versionResult.Output }
            yt_dlp_api = @{ ok = $apiResult.ExitCode -eq 0; detail = $apiResult.Output }
            yt_dlp_ejs = @{ ok = $apiResult.ExitCode -eq 0; detail = $ejsVersion }
            deno = @{ ok = (Test-Path -LiteralPath $deno); detail = $deno }
            ffmpeg = @{ ok = (Test-Path -LiteralPath $ffmpeg); detail = $ffmpeg }
            ffprobe = @{ ok = (Test-Path -LiteralPath $ffprobe); detail = $ffprobe }
        }
        $checks.Values | ForEach-Object { if (-not $_.ok) { throw "yt-dlp runtime verify failed: $($_.detail)" } }
        return @{ version = $versionResult.Output; checks = $checks }
    }

    if ($Mode -eq "Verify") {
        $verified = & $verify
        Write-Report @{ schema_version = 1; mode = $Mode; channel = $Channel; result = "verified"; version = $verified.version; checks = $verified.checks }
    }

    $installMode = $Mode -in @("Install", "Repair", "Update", "Rollback")
    if ($installMode) {
        $pipArgs = @("-m", "pip", "install")
        if ($NoCache) { $pipArgs += "--no-cache-dir" }
        if ($Mode -in @("Repair", "Rollback") -or $Force) { $pipArgs += "--force-reinstall" }
        if ($Mode -eq "Update" -and [string]::IsNullOrWhiteSpace($Version)) {
            $pipArgs += @("--pre", "--upgrade", "yt-dlp[default]")
        } elseif ($selectedVersion) {
            $pipArgs += "yt-dlp[default]==$selectedVersion"
        } else {
            $pipArgs += "yt-dlp[default]"
        }
        $pipArgs += @("-r", (Join-Path $root "worker\requirements-youtube.lock"))
        Invoke-Python $python $pipArgs
        $verified = & $verify
        $current.python.YtDlpVersion = [string]$verified.version
        $current | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath "$currentPath.tmp"
        Move-Item -Force -LiteralPath "$currentPath.tmp" -Destination $currentPath
        Write-Report @{ schema_version = 1; mode = $Mode; channel = $Channel; requested_version = $selectedVersion; result = "installed"; version = $verified.version; checks = $verified.checks }
    }
} catch {
    Write-Report @{ schema_version = 1; mode = $Mode; channel = $Channel; result = "failed"; error = $_.Exception.Message } 1
}
