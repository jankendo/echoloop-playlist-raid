param(
    [ValidateSet("Auto", "Cpu", "Cu118", "Cu126", "Cu128")]
    [string]$ComputePlatform = "Auto",
    [string]$PythonPath = "python"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if ($ComputePlatform -eq "Auto") {
    $nvidia = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    $ComputePlatform = if ($nvidia) { "Cu128" } else { "Cpu" }
}

& $PythonPath -m pip install -r (Join-Path $root "worker/requirements-analysis.lock")
if ($LASTEXITCODE -ne 0) { throw "audio dependencies could not be installed" }

$torchSpec = @{
    Cpu = @{ Version = "2.9.0"; Vision = "0.24.0"; Audio = "2.9.0"; Index = "cpu" }
    Cu126 = @{ Version = "2.9.0"; Vision = "0.24.0"; Audio = "2.9.0"; Index = "cu126" }
    Cu128 = @{ Version = "2.9.0"; Vision = "0.24.0"; Audio = "2.9.0"; Index = "cu128" }
    Cu118 = @{ Version = "2.7.1"; Vision = "0.22.1"; Audio = "2.7.1"; Index = "cu118" }
}[$ComputePlatform]

$torchArgs = @(
    "-m", "pip", "install",
    "torch==$($torchSpec.Version)",
    "torchvision==$($torchSpec.Vision)",
    "torchaudio==$($torchSpec.Audio)",
    "--index-url", "https://download.pytorch.org/whl/$($torchSpec.Index)"
)
& $PythonPath @torchArgs
if ($LASTEXITCODE -ne 0) { throw "PyTorch installation failed for $ComputePlatform" }

Write-Output "Analysis environment ready: $ComputePlatform"
