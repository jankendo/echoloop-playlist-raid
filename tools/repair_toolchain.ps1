param([ValidateSet("Auto", "Cpu", "Cuda")][string]$ComputePlatform = "Auto", [switch]$Force, [switch]$NoCache)
$args = @("-NoProfile", "-File", (Join-Path $PSScriptRoot "bootstrap_all.ps1"), "-Mode", "Repair", "-ComputePlatform", $ComputePlatform)
if ($Force) { $args += "-Force" }; if ($NoCache) { $args += "-NoCache" }
& pwsh @args
exit $LASTEXITCODE
