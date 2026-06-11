#Requires -Version 5.1
# Peerstar Headroom installer — turnkey setup of the hardened Claude Code
# compression proxy on a Windows machine with Docker Desktop.
#
# Run from a clone of the fork:
#   git clone -b feat/peerstar-hardening https://github.com/Geraldlol/headroom.git
#   cd headroom
#   powershell -ExecutionPolicy Bypass -File peerstar\install.ps1
#
# It builds the hardened image (or reuses a loaded one), runs the proxy
# container, installs the `headroom-claude` launcher, and tells you the one
# manual step (your token). Pass -Rebuild to force a fresh image build.
param([switch]$Rebuild)

$ErrorActionPreference = 'Stop'
$RepoRoot  = Split-Path -Parent $PSScriptRoot   # peerstar\ -> repo root
$Image     = 'headroom-hardened:local'
$Container = 'headroom-proxy'
$ProxyUrl  = 'http://127.0.0.1:8787'

function Fail($m) { Write-Host "[install] $m" -ForegroundColor Red; exit 1 }
Write-Host "== Peerstar Headroom setup ==" -ForegroundColor Cyan

# 1) Docker daemon
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "Docker Desktop isn't running. Start it and re-run." }

# 2) Build the hardened image (skip if it already exists, e.g. docker-loaded)
docker image inspect $Image *> $null
$imageExists = ($LASTEXITCODE -eq 0)
if ($imageExists -and -not $Rebuild) {
    Write-Host "Image $Image already present — reusing it (pass -Rebuild to force)." -ForegroundColor Green
} else {
    Write-Host "Building $Image from $RepoRoot (first build compiles the Rust core; ~10-15 min)..." -ForegroundColor Yellow
    docker build --target runtime -t $Image $RepoRoot
    if ($LASTEXITCODE -ne 0) { Fail "docker build failed." }
}

# 3) (Re)create the proxy container with the safe flags + auto-restart
docker rm -f $Container *> $null
docker run -d --name $Container --restart unless-stopped -p 127.0.0.1:8787:8787 `
    -e HEADROOM_BINARIES_OFFLINE=1 $Image `
    --host 0.0.0.0 --port 8787 --backend anthropic --no-telemetry | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "docker run failed." }

# 4) Wait for readiness
$ready = $false
for ($i = 0; $i -lt 40; $i++) {
    try { if ((Invoke-WebRequest -UseBasicParsing "$ProxyUrl/readyz" -TimeoutSec 2).StatusCode -eq 200) { $ready = $true; break } }
    catch { Start-Sleep -Milliseconds 800 }
}
if (-not $ready) { Fail "Proxy did not become healthy at $ProxyUrl." }
Write-Host "Proxy healthy at $ProxyUrl" -ForegroundColor Green

# 5) Install the launcher next to `claude` (its dir is already on PATH)
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) { $bin = Split-Path -Parent $claudeCmd.Source } else { $bin = Join-Path $HOME '.local\bin' }
New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'headroom-claude.ps1') (Join-Path $bin 'headroom-claude.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'headroom-claude.cmd') (Join-Path $bin 'headroom-claude.cmd') -Force
Write-Host "Launcher installed to $bin" -ForegroundColor Green
if (($env:PATH -split ';') -notcontains $bin) {
    Write-Host "NOTE: add '$bin' to your PATH to run 'headroom-claude' from anywhere." -ForegroundColor Yellow
}

# 6) Token store
$tokDir  = Join-Path $HOME '.headroom'
$tokFile = Join-Path $tokDir 'claude-oauth-token.txt'
New-Item -ItemType Directory -Force -Path $tokDir | Out-Null
if (-not (Test-Path $tokFile)) { New-Item -ItemType File -Path $tokFile | Out-Null }

Write-Host ""
Write-Host "DONE. One manual step (per user):" -ForegroundColor Cyan
Write-Host "  1) claude setup-token        # browser login; copy the token it prints"
Write-Host "  2) paste it into:  $tokFile"
Write-Host "  3) run 'headroom-claude' instead of 'claude'."
Write-Host ""
Write-Host "Use YOUR OWN token — never share someone else's. Plain 'claude' stays unchanged." -ForegroundColor Yellow
