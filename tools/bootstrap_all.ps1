param(
    [ValidateSet("Full", "Repair", "Verify", "Update", "Offline")]
    [string]$Mode = "Full",
    [ValidateSet("Auto", "Cpu", "Cuda")]
    [string]$ComputePlatform = "Auto",
    [switch]$Force,
    [switch]$NoCache,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$lockPath = Join-Path $root "toolchain.lock.json"
$toolsRoot = Join-Path $root ".tools"
$runtimeRoot = Join-Path $root ".runtime"
$modelsRoot = Join-Path $root ".models"
$cacheRoot = Join-Path $root ".cache"

function Read-Lock {
    if (-not (Test-Path -LiteralPath $lockPath)) { throw "toolchain.lock.json がありません" }
    return Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
}

function Ensure-Dir([string]$path) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

function Invoke-Download([string]$url, [string]$destination) {
    Ensure-Dir (Split-Path -Parent $destination)
    $temporary = "$destination.$([guid]::NewGuid().ToString('N')).download"
    Write-Host "download: $url"
    try {
        & curl.exe --fail --location --retry 3 --retry-all-errors --connect-timeout 30 --max-time 1800 --output $temporary $url 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "download failed ($LASTEXITCODE): $url" }
        Move-Item -Force -LiteralPath $temporary -Destination $destination
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -Force -LiteralPath $temporary }
    }
}

function Get-Sha256([string]$path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
}

function Expand-Zip([string]$archive, [string]$destination) {
    $temporary = Join-Path $cacheRoot ("extract-" + [guid]::NewGuid().ToString("N"))
    Ensure-Dir $temporary
    try {
        Expand-Archive -LiteralPath $archive -DestinationPath $temporary -Force
        Ensure-Dir $destination
        Get-ChildItem -LiteralPath $temporary -Force | Move-Item -Destination $destination -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -Recurse -Force -LiteralPath $temporary }
    }
}

function Invoke-ParallelDownload([string]$url, [string]$destination) {
    $head = (& curl.exe --silent --show-error --fail --location --range 0-0 --dump-header - --output NUL $url 2>$null) -join "`n"
    $match = [regex]::Match($head, "(?im)^content-range:\s*bytes\s*0-0/(\d+)")
    if (-not $match.Success) { Invoke-Download $url $destination; return }
    $length = [int64]$match.Groups[1].Value
    if ($length -lt 50MB) { Invoke-Download $url $destination; return }
    $partRoot = Join-Path $cacheRoot ("parts-" + [guid]::NewGuid().ToString("N"))
    Ensure-Dir $partRoot
    $partCount = 12
    $partSize = [math]::Ceiling($length / $partCount)
    $processes = @()
    try {
        for ($index = 0; $index -lt $partCount; $index++) {
            $start = [int64]($index * $partSize)
            $end = [math]::Min($length - 1, [int64](($index + 1) * $partSize - 1))
            $part = Join-Path $partRoot ("part-{0:D2}" -f $index)
            $arguments = @("--silent", "--show-error", "--fail", "--location", "--retry", "3", "--retry-all-errors", "--connect-timeout", "30", "--max-time", "1800", "--range", "$start-$end", "--output", $part, $url)
            $processes += Start-Process -FilePath "curl.exe" -ArgumentList $arguments -PassThru -WindowStyle Hidden
        }
        while (@($processes | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Seconds 3 }
        if (@($processes | Where-Object { $_.ExitCode -ne 0 }).Count -gt 0) { throw "parallel download failed: $url" }
        $temporary = "$destination.$([guid]::NewGuid().ToString('N')).download"
        Ensure-Dir (Split-Path -Parent $destination)
        $output = [IO.File]::Open($temporary, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            for ($index = 0; $index -lt $partCount; $index++) {
                $part = Join-Path $partRoot ("part-{0:D2}" -f $index)
                if (-not (Test-Path -LiteralPath $part)) { throw "missing download part: $index" }
                $input = [IO.File]::OpenRead($part)
                try { $input.CopyTo($output) } finally { $input.Dispose() }
            }
        } finally { $output.Dispose() }
        Move-Item -Force -LiteralPath $temporary -Destination $destination
    } finally {
        if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -Force -LiteralPath $temporary }
        if (Test-Path -LiteralPath $partRoot) { Remove-Item -Recurse -Force -LiteralPath $partRoot }
    }
}

function Resolve-ComputePlatform([string]$requested) {
    if ($requested -ne "Auto") { return $requested }
    $nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $nvidia) { return "Cpu" }
    try {
        & $nvidia.Source --query-gpu=name --format=csv,noheader 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return "Cuda" }
    } catch { }
    return "Cpu"
}

function Install-PortableTools($lock) {
    Ensure-Dir $toolsRoot
    Ensure-Dir $cacheRoot
    $godot = $lock.tools.godot
    $godotDir = Join-Path $toolsRoot ("godot\" + $godot.'version')
    $godotExe = Join-Path $godotDir ("Godot_v" + $godot.'version'.Replace("-stable", "-stable") + "_win64.exe")
    if ($Force -or -not (Test-Path -LiteralPath $godotExe)) {
        $archive = Join-Path $cacheRoot "godot-win64.zip"
        if ($NoCache -or -not (Test-Path -LiteralPath $archive)) { Invoke-Download $godot.archive_url $archive }
        if ($godot.sha256) {
            if ((Get-Sha256 $archive) -ne $godot.sha256.ToLowerInvariant()) { throw "Godot SHA-256 mismatch" }
        }
        if (Test-Path -LiteralPath $godotDir) { Remove-Item -Recurse -Force -LiteralPath $godotDir }
        Expand-Zip $archive $godotDir
    }
    $templateVersion = $godot.'version'.Replace("-stable", ".stable")
    $templatesDir = Join-Path $env:APPDATA ("Godot\export_templates\" + $templateVersion)
    $templateArchive = Join-Path $cacheRoot "godot-export-templates.tpz"
    if ($Force -or -not (Test-Path -LiteralPath $templatesDir)) {
        if ($NoCache -or -not (Test-Path -LiteralPath $templateArchive)) { Invoke-ParallelDownload $godot.templates_url $templateArchive }
        if ($godot.templates_sha256 -and (Get-Sha256 $templateArchive) -ne $godot.templates_sha256.ToLowerInvariant()) { throw "Godot templates SHA-256 mismatch" }
        $temporary = Join-Path $cacheRoot ("templates-" + [guid]::NewGuid().ToString("N"))
        Ensure-Dir $temporary
        try {
            Expand-Archive -LiteralPath $templateArchive -DestinationPath $temporary -Force
            $payload = Get-ChildItem -LiteralPath $temporary -Recurse -File | Select-Object -First 1
            if (-not $payload) { throw "Godot export templates archive is empty" }
            if (Test-Path -LiteralPath $templatesDir) { Remove-Item -Recurse -Force -LiteralPath $templatesDir }
            Ensure-Dir $templatesDir
            $templatePayload = Join-Path $temporary "templates"
            $moveFrom = if (Test-Path -LiteralPath $templatePayload) { $templatePayload } else { $temporary }
            Get-ChildItem -LiteralPath $moveFrom -Force | Move-Item -Destination $templatesDir -Force
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -Recurse -Force -LiteralPath $temporary }
        }
    }
    $deno = $lock.tools.deno
    $denoDir = Join-Path $toolsRoot ("deno\" + $deno.'version')
    $denoExe = Join-Path $denoDir "deno.exe"
    if ($Force -or -not (Test-Path -LiteralPath $denoExe)) {
        $archive = Join-Path $cacheRoot "deno-win64.zip"
        if ($NoCache -or -not (Test-Path -LiteralPath $archive)) { Invoke-Download $deno.archive_url $archive }
        if ($deno.sha256 -and (Get-Sha256 $archive) -ne $deno.sha256.ToLowerInvariant()) { throw "Deno SHA-256 mismatch" }
        if (Test-Path -LiteralPath $denoDir) { Remove-Item -Recurse -Force -LiteralPath $denoDir }
        Expand-Zip $archive $denoDir
    }
    $ffmpeg = $lock.tools.ffmpeg
    $ffmpegDir = Join-Path $toolsRoot ("ffmpeg\" + $ffmpeg.'version')
    $ffmpegExe = Join-Path $ffmpegDir "ffmpeg.exe"
    if ($Force -or -not (Test-Path -LiteralPath $ffmpegExe)) {
        $archive = Join-Path $cacheRoot "ffmpeg-essentials.zip"
        if ($NoCache -or -not (Test-Path -LiteralPath $archive)) { Invoke-ParallelDownload $ffmpeg.archive_url $archive }
        if ($ffmpeg.sha256) { if ((Get-Sha256 $archive) -ne $ffmpeg.sha256.ToLowerInvariant()) { throw "FFmpeg SHA-256 mismatch" } }
        if (Test-Path -LiteralPath $ffmpegDir) { Remove-Item -Recurse -Force -LiteralPath $ffmpegDir }
        Expand-Zip $archive $ffmpegDir
        $nested = Get-ChildItem -LiteralPath $ffmpegDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1
        if ($nested) { Copy-Item -Force $nested.FullName (Join-Path $ffmpegDir "ffmpeg.exe"); Copy-Item -Force ($nested.DirectoryName + "\ffprobe.exe") (Join-Path $ffmpegDir "ffprobe.exe") }
    }
    $rcedit = $lock.tools.rcedit
    $rceditDir = Join-Path $toolsRoot ("rcedit\" + $rcedit.'version')
    $rceditExe = Join-Path $rceditDir "rcedit-x64.exe"
    if ($Force -or -not (Test-Path -LiteralPath $rceditExe)) {
        $archive = Join-Path $cacheRoot "rcedit-x64.exe"
        if ($NoCache -or -not (Test-Path -LiteralPath $archive)) { Invoke-Download $rcedit.archive_url $archive }
        if ($rcedit.sha256) { if ((Get-Sha256 $archive) -ne $rcedit.sha256.ToLowerInvariant()) { throw "rcedit SHA-256 mismatch" } }
        Ensure-Dir $rceditDir
        Copy-Item -Force -LiteralPath $archive -Destination $rceditExe
    }
    return @{ Godot = $godotExe; Deno = $denoExe; Ffmpeg = $ffmpegExe; Ffprobe = (Join-Path $ffmpegDir "ffprobe.exe"); Rcedit = $rceditExe; Templates = $templatesDir }
}

function New-PythonEnvironment([string]$platform, $lock) {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $python) { throw "Python 3.11 が見つかりません" }
    $version = (& $python.Source --version 2>&1 | Out-String).Trim()
    if ($version -notmatch "Python 3\.11\.") { throw "Python 3.11 が必要です: $version" }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $envName = "python-3.11-$($platform.ToLowerInvariant())-$stamp"
    $envDir = Join-Path $runtimeRoot ("python-envs\" + $envName)
    Ensure-Dir (Split-Path -Parent $envDir)
    & $python.Source -m venv $envDir
    if ($LASTEXITCODE -ne 0) { throw "venv作成に失敗しました" }
    $venvPython = Join-Path $envDir "Scripts\python.exe"
    $pipFlags = @()
    if ($NoCache) { $pipFlags += "--no-cache-dir" }
    & $venvPython -m pip install @pipFlags --upgrade pip setuptools wheel 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "pip bootstrapに失敗しました" }
    & $venvPython -m pip install @pipFlags -r (Join-Path $root "worker/requirements-analysis.lock") 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "音源依存関係の導入に失敗しました" }
    & $venvPython -m pip install @pipFlags -e (Join-Path $root "worker[dev,youtube,beat]") 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "worker依存関係の導入に失敗しました" }
    $torchIndex = if ($platform -eq "Cuda") { $lock.python_packages.torch_index_cuda } else { $lock.python_packages.torch_cpu_index }
    & $venvPython -m pip install @pipFlags `
        ("torch==" + $lock.python_packages.torch_cuda) `
        ("torchvision==" + $lock.python_packages.torchvision_cuda) `
        ("torchaudio==" + $lock.python_packages.torchaudio_cuda) `
        "--index-url" $torchIndex 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "PyTorch導入に失敗しました: $platform" }
    $stableYtdlp = [string]$lock.python_packages.'yt-dlp'.stable_fallback
    $ytArgs = @("-m", "pip", "install") + $pipFlags + @("yt-dlp[default]==$stableYtdlp", "-r", (Join-Path $root "worker/requirements-youtube.lock"))
    & $venvPython @ytArgs 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "yt-dlp導入に失敗しました" }
    $nightlyArgs = @("-m", "pip", "install") + $pipFlags + @("--pre", "--upgrade", "yt-dlp[default]")
    & $venvPython @nightlyArgs 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "yt-dlp nightlyが利用できないためstableへ戻します"
        & $venvPython @ytArgs 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "yt-dlp stable fallbackにも失敗しました" }
    }
    $env:TORCH_HOME = $modelsRoot
    & $venvPython (Join-Path $root "tools/prefetch_models.py") --models-root $modelsRoot --python-executable $venvPython 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Beat This!モデルのprefetchに失敗しました" }
    $ytdlpVersion = (& $venvPython -c "import yt_dlp; print(yt_dlp.version.__version__)" 2>$null | Select-Object -First 1)
    return @{ Name = $envName; Path = $envDir; Python = $venvPython; ComputePlatform = $platform; PythonVersion = $version; YtDlpVersion = [string]$ytdlpVersion }
}

function Write-Current($tools, $pythonEnvironment, [string]$mode) {
    Ensure-Dir $runtimeRoot
    $currentPath = Join-Path $runtimeRoot "current.json"
    $history = @()
    if (Test-Path -LiteralPath $currentPath) {
        $old = Get-Content -Raw -LiteralPath $currentPath | ConvertFrom-Json
        if ($old) { $history += $old }
    }
    $record = [ordered]@{
        schema_version = 1
        created_at = [DateTime]::UtcNow.ToString("o")
        mode = $mode
        root = $root
        compute_platform = $pythonEnvironment.ComputePlatform
        tools = $tools
        python = $pythonEnvironment
        models_root = $modelsRoot
        history = $history | Select-Object -First 3
    }
    $temporary = "$currentPath.$([guid]::NewGuid().ToString('N')).tmp"
    $record | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $temporary
    Move-Item -Force -LiteralPath $temporary -Destination $currentPath
}

function Invoke-Verify {
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot "verify_toolchain.ps1") -Quiet
    if ($LASTEXITCODE -ne 0) { throw "toolchain verify failed" }
}

$lock = Read-Lock
if ($Mode -eq "Verify") { Invoke-Verify; exit 0 }
if ($Mode -eq "Offline") {
    if (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot "current.json"))) { throw "Offline検証にはcurrent.jsonが必要です" }
    Invoke-Verify
    exit 0
}
$platform = Resolve-ComputePlatform $ComputePlatform
if ($Mode -eq "Full" -or $Mode -eq "Repair" -or $Mode -eq "Update") {
    $tools = Install-PortableTools $lock
    $pythonEnvironment = New-PythonEnvironment $platform $lock
    Write-Current $tools $pythonEnvironment $Mode
    Invoke-Verify
    Write-Host "ECHOLOOP toolchain ready: $platform"
}
