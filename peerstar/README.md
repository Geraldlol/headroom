# Peerstar Headroom — Claude Code token compression (hardened)

Run Claude Code through a local [Headroom](https://github.com/chopratejas/headroom)
compression proxy so big file reads, tool outputs, and long history get shrunk
before they hit the model — you burn through your subscription usage limits
slower. This is a **security-hardened fork** vetted for our HIPAA environment.

## What's hardened (vs. upstream)
- **Telemetry network beacon OFF by default** (opt in: `HEADROOM_TELEMETRY_BEACON=on`).
- **Unverified binary downloads fail closed** (`sha256:null` assets are refused).
- **Cloud compression hard-blocked** — prompts (= PHI for us) can never be POSTed
  to a third party; all compression is local/in-process.

See `../PEERSTAR_HARDENING.md` for details. Nothing leaves your machine except the
(compressed) request to `api.anthropic.com`, which Anthropic already covers under BAA.

## Install (Windows + Docker Desktop)

1. Install **Docker Desktop** and start it.
2. Clone this fork's hardened branch and run the installer:
   ```powershell
   git clone -b feat/peerstar-hardening https://github.com/Geraldlol/headroom.git
   cd headroom
   powershell -ExecutionPolicy Bypass -File peerstar\install.ps1
   ```
   First build compiles the Rust core (~10–15 min); after that the container
   just restarts instantly.
3. Mint **your own** subscription token and store it:
   ```
   claude setup-token
   ```
   Paste the token it prints into `%USERPROFILE%\.headroom\claude-oauth-token.txt`.

## Use it

Run `headroom-claude` instead of `claude` (same arguments). Your plain `claude`
command is untouched — it's your fallback. Watch what it saves:
```
curl http://127.0.0.1:8787/stats
```

## Rules / notes
- **Use YOUR OWN token.** It's tied to your subscription and is a secret — never
  share it or commit it. `setup-token` again to rotate.
- **Docker Desktop must be running** (the container auto-restarts; you don't manage it).
- Billing stays on your **subscription** (no Anthropic API charges).
- First `headroom-claude` run is the live test. If Claude Code rejects the
  OAuth-token-over-proxy combo, the fallback is an Anthropic API key
  (`ANTHROPIC_API_KEY` + `ANTHROPIC_BASE_URL`) — ask Gerald.

## Faster image sharing (optional)
Skip the per-machine build by exporting the image from a machine that already
built it and importing on the new one:
```powershell
# on a machine that has headroom-hardened:local
docker save headroom-hardened:local | gzip > headroom-hardened.tar.gz
# on the new machine
docker load -i headroom-hardened.tar.gz
```
Then run `peerstar\install.ps1` — it reuses the loaded image instead of rebuilding.
