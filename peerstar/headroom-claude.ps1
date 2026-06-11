# headroom-claude.ps1 — launch Claude Code through the local hardened Headroom
# compression proxy (Docker), using YOUR subscription's long-lived OAuth token.
#
# Plain `claude` is unaffected. Run `headroom-claude` to get the compressed path.
# One-time setup (per user — use YOUR OWN token, never share):
#   1) claude setup-token        (browser login; copy the token it prints)
#   2) paste that token into:    $HOME\.headroom\claude-oauth-token.txt
#
# Nothing leaves your machine except the (compressed) request to api.anthropic.com:
# telemetry beacon off, cloud compression blocked, binaries offline.

$ErrorActionPreference = 'Stop'
$ProxyUrl   = 'http://127.0.0.1:8787'
$Container  = 'headroom-proxy'
$TokenFile  = Join-Path $HOME '.headroom\claude-oauth-token.txt'

function Fail($msg) { Write-Host "[headroom] $msg" -ForegroundColor Red; exit 1 }

# 1) Docker daemon up?
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "Docker Desktop isn't running. Start it, then re-run headroom-claude." }

# 2) Proxy container running? (start it if stopped)
$running = docker ps --filter "name=^/$Container$" --filter "status=running" -q
if (-not $running) {
    docker start $Container *> $null
    if ($LASTEXITCODE -ne 0) { Fail "Container '$Container' not found. Run peerstar\install.ps1 first." }
}

# 3) Wait for the proxy to report ready
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing "$ProxyUrl/readyz" -TimeoutSec 2
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { Start-Sleep -Milliseconds 700 }
}
if (-not $ready) { Fail "Proxy did not become ready at $ProxyUrl/readyz." }

# 4) Subscription OAuth token (kept out of global env; scoped to this launch only)
if (-not (Test-Path $TokenFile)) {
    Fail "Token file missing: $TokenFile`n   Run:  claude setup-token   then paste the token into that file."
}
$token = (Get-Content $TokenFile -Raw).Trim()
if (-not $token) {
    Fail "Token file is empty: $TokenFile`n   Run:  claude setup-token   then paste the token into that file."
}

# 5) Launch Claude Code through the proxy (env scoped to this process tree only)
$env:ANTHROPIC_BASE_URL      = $ProxyUrl
$env:CLAUDE_CODE_OAUTH_TOKEN = $token
Write-Host "[headroom] proxy active: $ProxyUrl  (subscription billing, telemetry off, cloud blocked)" -ForegroundColor Green
& claude @args
exit $LASTEXITCODE
