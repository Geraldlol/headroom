#Requires -Version 5.1
# Peerstar Headroom (Remote Control edition) installer.
#
# Brings up the two-container stack that gives Claude Code compression AND a
# working /remote-control at the same time, then installs the launcher and the
# mitmproxy CA the launcher needs.
#
#   git clone -b feat/remote-control-forward-proxy https://github.com/Geraldlol/headroom.git
#   cd headroom
#   powershell -ExecutionPolicy Bypass -File peerstar\install-rc.ps1
#
# Pass -Rebuild to force a fresh hardened-image build.
param([switch]$Rebuild)

$ErrorActionPreference = 'Stop'
$RepoRoot   = Split-Path -Parent $PSScriptRoot           # peerstar\ -> repo root
$SrcDir     = Join-Path $PSScriptRoot 'remote-control'   # compose + addon in the repo
$RuntimeDir = Join-Path $HOME '.headroom\remote-control' # stable dir the launcher uses
$Compose    = Join-Path $RuntimeDir 'docker-compose.yml'
$Image      = 'headroom-hardened:local'
$MitmSvc    = 'headroom-mitm'
$ProxySvc   = 'headroom-proxy'
$CaDir      = Join-Path $HOME '.headroom\mitm'
$CaFile     = Join-Path $CaDir 'mitmproxy-ca-cert.pem'

function Fail($m) { Write-Host "[install-rc] $m" -ForegroundColor Red; exit 1 }
Write-Host "== Peerstar Headroom (Remote Control) setup ==" -ForegroundColor Cyan

# 1) Docker daemon
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "Docker Desktop isn't running. Start it and re-run." }

# 2) Hardened image (reuse if present; build if missing or -Rebuild)
docker image inspect $Image *> $null
$imageExists = ($LASTEXITCODE -eq 0)
if ($imageExists -and -not $Rebuild) {
    Write-Host "Image $Image already present - reusing it (pass -Rebuild to force)." -ForegroundColor Green
} else {
    Write-Host "Building $Image (first build compiles the Rust core; ~10-15 min)..." -ForegroundColor Yellow
    docker build --target runtime -t $Image $RepoRoot
    if ($LASTEXITCODE -ne 0) { Fail "docker build failed." }
}

# 3) Materialize the runtime dir (compose + addon) so the launcher doesn't depend
#    on the repo checkout being present. The launcher reads from here too.
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
Copy-Item (Join-Path $SrcDir 'docker-compose.yml') (Join-Path $RuntimeDir 'docker-compose.yml') -Force
Copy-Item (Join-Path $SrcDir 'redirect_addon.py')  (Join-Path $RuntimeDir 'redirect_addon.py')  -Force
Write-Host "Runtime files staged in $RuntimeDir" -ForegroundColor Green

# 4) Bring the stack up (from the runtime dir, so the ./:/addon mount resolves here)
docker compose -f $Compose up -d
if ($LASTEXITCODE -ne 0) { Fail "docker compose up failed." }

# 4) Wait for the proxy to report healthy (cold start warms up tokenizers; ~60s)
$proxyId = (docker compose -f $Compose ps -q $ProxySvc).Trim()
if (-not $proxyId) { Fail "Proxy container not found after 'up'." }
Write-Host "Waiting for headroom-proxy to warm up (cold start can take ~1-2 min)..." -ForegroundColor Yellow
$healthy = $false
for ($i = 0; $i -lt 160; $i++) {
    $status = (docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $proxyId 2>$null)
    if ($status -eq 'healthy') { $healthy = $true; break }
    if ($status -eq 'none') {
        # No healthcheck on this image build - fall back to "running".
        $run = (docker inspect --format '{{.State.Running}}' $proxyId 2>$null)
        if ($run -eq 'true') { $healthy = $true; break }
    }
    Start-Sleep -Milliseconds 800
}
if (-not $healthy) { Fail "headroom-proxy did not become healthy. Check: docker compose -f `"$Compose`" logs $ProxySvc" }
Write-Host "headroom-proxy healthy." -ForegroundColor Green

# 5) Extract the mitmproxy CA to the host (the launcher trusts it via NODE_EXTRA_CA_CERTS)
New-Item -ItemType Directory -Force -Path $CaDir | Out-Null
$copied = $false
for ($i = 0; $i -lt 40; $i++) {
    # No PowerShell stream redirection here: `docker compose cp` writes progress
    # to stderr, which under $ErrorActionPreference='Stop' gets wrapped into a
    # terminating error when redirected. Let it print; gate on the exit code.
    docker compose -f $Compose cp "${MitmSvc}:/home/mitmproxy/.mitmproxy/mitmproxy-ca-cert.pem" $CaFile
    if ($LASTEXITCODE -eq 0 -and (Test-Path $CaFile)) { $copied = $true; break }
    Start-Sleep -Milliseconds 800
}
if (-not $copied) { Fail "Could not extract mitmproxy CA. Check: docker compose -f `"$Compose`" logs $MitmSvc" }
Write-Host "mitmproxy CA written to $CaFile" -ForegroundColor Green

# 6) Install the launcher next to `claude` (its dir is already on PATH)
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) { $bin = Split-Path -Parent $claudeCmd.Source } else { $bin = Join-Path $HOME '.local\bin' }
New-Item -ItemType Directory -Force -Path $bin | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'headroom-claude-rc.ps1') (Join-Path $bin 'headroom-claude-rc.ps1') -Force
Copy-Item (Join-Path $PSScriptRoot 'headroom-claude-rc.cmd') (Join-Path $bin 'headroom-claude-rc.cmd') -Force
Write-Host "Launcher installed to $bin" -ForegroundColor Green
if (($env:PATH -split ';') -notcontains $bin) {
    Write-Host "NOTE: add '$bin' to your PATH to run 'headroom-claude-rc' from anywhere." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "DONE. One manual step (per user):" -ForegroundColor Cyan
Write-Host "  1) claude /login            # full-scope claude.ai login (NOT setup-token)"
Write-Host "                              #   Remote Control + subscription billing both need this."
Write-Host "  2) run 'headroom-claude-rc' instead of 'claude', then use /remote-control as usual."
Write-Host ""
Write-Host "Plain 'claude' and 'headroom-claude' are both unchanged." -ForegroundColor Yellow
