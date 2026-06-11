# Peerstar hardening fork

This branch (`feat/peerstar-hardening`) carries a small set of security patches on
top of upstream [`chopratejas/headroom`](https://github.com/chopratejas/headroom) so the
tool is safe to run on machines that handle PHI (HIPAA environment). It changes
**defaults and adds guardrails only** — no features are rewritten and the upstream
diff is intentionally tiny so it stays easy to rebase.

Origin: a pre-install security audit (red-team pass). The audit found **no malicious
code or backdoors** in upstream — these patches address default-on egress and a
supply-chain gap, plus they hard-disable an opt-in feature that would send prompt
content (PHI) to a third party.

## What changed

### 1. Network telemetry beacon is OFF by default
**File:** `headroom/telemetry/beacon.py`

Upstream sends anonymous aggregate stats (token counts, ratios, model *names*, a
hashed hostname — no prompt content) to a hardcoded Supabase endpoint every 5 minutes,
**on by default**. In a HIPAA shop, any unsolicited outbound connection to a non-BAA
third party is unwanted even when the payload is aggregate.

- The **network beacon** now requires explicit opt-in: `HEADROOM_TELEMETRY_BEACON=on`.
- **Local, filesystem-only stats collection** (the savings dashboard) is *unchanged* —
  it never made a network call, so disabling it would add no privacy benefit. It can
  still be turned off wholesale with `HEADROOM_TELEMETRY=off`.
- New predicate `is_network_beacon_enabled()` gates `TelemetryBeacon.start()`/`stop()`.

### 2. Binary downloads fail closed when unpinned
**File:** `headroom/binaries.py`

On proxy startup, headroom fetches `difft` and `scc` from upstream GitHub releases and
executes them. Every entry in `tools.json` ships `"sha256": null`, and the original
`_verify_sha256()` treated a missing pin as "HTTPS trust only" — i.e. it ran the binary
with no integrity check. A compromised upstream release would execute as code locally.

- `_verify_sha256()` now **raises `Sha256Mismatch`** when no pin is present, so the
  compression pipeline falls back to its non-accelerated path instead of running an
  unverified binary.
- Escape hatch for non-regulated use: `HEADROOM_ALLOW_UNPINNED_BINARIES=1`.
- Proper fix (follow-up): populate real SHA-256 pins in `tools.json` via the upstream
  weekly `tools-version-check` CI job, then this gate becomes a no-op.

### 3. Cloud compression mode is hard-blocked (PHI egress)
**Files:** `headroom/integrations/asgi.py`, `headroom/integrations/litellm_callback.py`

"Cloud mode" (`HEADROOM_API_KEY` set) POSTs **raw prompt content** to
`api.headroomlabs.ai/v1/saas/compress` — that content is PHI in our environment, and
headroomlabs is not a Peerstar BAA vendor. It is opt-in upstream, but a stray env var
would silently enable it.

- Constructing `CompressionMiddleware` / `HeadroomCallback` with an api_key (directly or
  via `HEADROOM_API_KEY`) now **raises `RuntimeError`** — fail loud, never silently send.
- `cloud_mode` always returns `False`; `_cloud_compress()` is removed (raises).
- Default **local, in-process compression is unaffected.**

## Recommended runtime env (defense in depth)

Even with these defaults baked in, set these so intent is explicit:

```
HEADROOM_TELEMETRY_BEACON   # leave UNSET (off). Set to "on" only to share aggregate stats.
HEADROOM_BINARIES_OFFLINE=1 # optional: forbid the difft/scc fetch entirely.
# Do NOT set HEADROOM_API_KEY — cloud mode is blocked, but don't tempt it.
```

## Not changed (audited, deemed acceptable)
- `PreToolUse` plugin hook runs `headroom init hook ensure` on every Bash/PowerShell
  call — benign (only restarts the local proxy; no network, no untrusted input).
- `headroom learn` rewrites `CLAUDE.md`/`AGENTS.md` — bounded to a marker block and
  dry-run by default.
- Proxy binds to `127.0.0.1` by default; the license/usage reporter is opt-in (license key).

See the full audit writeup for details and severity ratings.
