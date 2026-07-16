param([string]$OutputPath = ".runtime\reports\environment.json")
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$absolute = [IO.Path]::GetFullPath((Join-Path $root $OutputPath))
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $absolute) | Out-Null
$commands = @{}
foreach ($name in @("python", "nvidia-smi", "ffmpeg", "ffprobe", "pwsh", "git")) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { $commands[$name] = @{ path = $command.Source; version = ((& $command.Source --version 2>&1 | Select-Object -First 1) -join " ") } }
}
$report = [ordered]@{ schema_version = 1; generated_at = [DateTime]::UtcNow.ToString("o"); os = [Environment]::OSVersion.VersionString; architecture = [Environment]::Is64BitOperatingSystem; commands = $commands; gpu = @(); current = $null }
$nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidia) { $report.gpu = @(& $nvidia.Source --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>$null) }
$current = Join-Path $root ".runtime\current.json"
if (Test-Path -LiteralPath $current) { $report.current = Get-Content -Raw -LiteralPath $current | ConvertFrom-Json }
$report | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $absolute
Write-Host $absolute
