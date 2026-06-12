# headroom-claude-rc.ps1 - launch Claude Code through the local Headroom
# compression proxy WHILE keeping /remote-control working.
#
# Unlike headroom-claude (reverse proxy via ANTHROPIC_BASE_URL, which disables
# Remote Control), this points Claude Code at a forward proxy via HTTPS_PROXY.
# Remote Control's "no base-URL override" guard stays satisfied, so it pairs
# normally - and inference still runs locally, so compression keeps working
# even during remote-driven turns.
#
# One-time setup (per user):
#   claude /login        # full-scope claude.ai login (NOT setup-token).
#                        # Remote Control AND subscription billing both require it.
#
# Plain `claude` and `headroom-claude` are both unaffected.

$ErrorActionPreference = 'Stop'
$ProxyAddr  = 'http://127.0.0.1:8080'                       # the mitm forward proxy
$CaFile     = Join-Path $HOME '.headroom\mitm\mitmproxy-ca-cert.pem'
# Stable runtime dir the installer materializes — NOT $PSScriptRoot, because this
# launcher is copied to the PATH bin dir away from the compose file.
$ComposeDir = Join-Path $HOME '.headroom\remote-control'
$Compose    = Join-Path $ComposeDir 'docker-compose.yml'

function Fail($msg) { Write-Host "[headroom-rc] $msg" -ForegroundColor Red; exit 1 }

# 1) Docker up?
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "Docker Desktop isn't running. Start it, then re-run." }

# 2) Ensure the stack is up (idempotent — starts what's missing, no-ops the rest).
#    Uses compose, not `docker ps --filter name`, so it can't be confused by a
#    separately-run standalone headroom-proxy container.
if (-not (Test-Path $Compose)) { Fail "Compose file not found: $Compose. Run peerstar\install-rc.ps1 first." }
# Suppress compose's chatty stderr without tripping Stop-on-native-stderr (PS 5.1).
$savedEAP = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
docker compose -f $Compose up -d *> $null
$composeRc = $LASTEXITCODE
$ErrorActionPreference = $savedEAP
if ($composeRc -ne 0) { Fail "Could not start the stack. Run peerstar\install-rc.ps1 first." }

# 3) Proxy reachable on the forward-proxy port?
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    $r = Test-NetConnection -ComputerName '127.0.0.1' -Port 8080 -WarningAction SilentlyContinue
    if ($r.TcpTestSucceeded) { $ready = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $ready) { Fail "Forward proxy not reachable at $ProxyAddr." }

# 4) CA present? (Claude Code must trust the mitmproxy CA to use the proxy)
if (-not (Test-Path $CaFile)) {
    Fail "mitmproxy CA missing: $CaFile`n   Run peerstar\install-rc.ps1 to (re)extract it."
}

# 5) Launch Claude Code through the forward proxy.
#    NOTE: we deliberately do NOT set ANTHROPIC_BASE_URL (would disable Remote
#    Control) and do NOT set CLAUDE_CODE_OAUTH_TOKEN (inference-only; use /login).
#    Env is scoped to this process tree only.
$env:HTTPS_PROXY         = $ProxyAddr
$env:HTTP_PROXY          = $ProxyAddr
$env:NO_PROXY            = '127.0.0.1,localhost'
$env:NODE_EXTRA_CA_CERTS = $CaFile
Write-Host "[headroom-rc] forward proxy active: $ProxyAddr  (compression on, Remote Control enabled)" -ForegroundColor Green
Write-Host "[headroom-rc] reminder: this only bills your subscription if you ran 'claude /login' (not setup-token)." -ForegroundColor DarkGray
& claude @args
exit $LASTEXITCODE
