param(
  [string]$TargetDir = "_build_standalone",
  [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

moon --target-dir $TargetDir run examples/embed_assets
if ($LASTEXITCODE -ne 0) {
  throw "Asset embedding failed."
}

moon --target-dir $TargetDir build examples/web_agent/backend --target native --release
if ($LASTEXITCODE -ne 0) {
  throw "Release build failed."
}

$binary = Get-ChildItem -Path $TargetDir -Recurse -File -Filter "backend.exe" |
  Where-Object { $_.FullName -match "native.+release" } |
  Select-Object -First 1

if (-not $binary) {
  throw "Could not locate the release backend executable under $TargetDir."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$output = Join-Path $OutputDir "moonai-agent.exe"
Copy-Item -LiteralPath $binary.FullName -Destination $output -Force
Write-Host "Standalone MoonAI Agent: $((Resolve-Path $output).Path)"
