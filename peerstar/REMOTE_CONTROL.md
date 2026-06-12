# Headroom compression + Claude Code Remote Control, at the same time

The standard `headroom-claude` launcher points Claude Code at the compression
proxy with `ANTHROPIC_BASE_URL`. That single env var disables `/remote-control`
(Claude Code refuses Remote Control when a base-URL override is set), and the
`setup-token` it uses is inference-only, which Remote Control also rejects.

This setup gets you **both**. Instead of *configuring* Claude Code to talk to the
proxy, it *intercepts* the traffic underneath via a forward proxy reached through
`HTTPS_PROXY` — which Remote Control does **not** reject — and re-routes only the
inference calls into the existing hardened compression proxy.

```
claude  (HTTPS_PROXY=http://127.0.0.1:8080, NODE_EXTRA_CA_CERTS=<mitm CA>,
         NO ANTHROPIC_BASE_URL, logged in via `claude /login`)
  │
  ▼
headroom-mitm   mitmproxy, --allow-hosts '^api.anthropic.com(:443)?$'
  ├─ api.anthropic.com  POST /v1/messages  → redirected into headroom-proxy
  ├─ api.anthropic.com  other paths        → forwarded direct
  └─ every other host (Remote Control relay, telemetry) → blind tunnel, untouched
  ▼
headroom-proxy  (the existing hardened image — does ALL compression)
  ▼
real api.anthropic.com   (BAA-covered; your OAuth auth header forwarded as-is)
```

Because Remote Control runs the agent loop **locally**, the inference calls still
originate on this machine and still flow through the interceptor — so compression
keeps working even when you're driving the session from your phone or browser.

## Three launchers, pick per session

| Command | Compression | Remote Control | Billing |
|---|---|---|---|
| `claude` | none | yes | subscription (your login) |
| `headroom-claude` | full (auto) | **no** | subscription (setup-token) |
| `headroom-claude-rc` | full (auto) | **yes** | subscription **only if** you used `claude /login` |

## Install

```powershell
powershell -ExecutionPolicy Bypass -File peerstar\install-rc.ps1
```

Then, once per user:

```
claude /login          # full-scope claude.ai login — NOT `claude setup-token`
```

Run `headroom-claude-rc` instead of `claude`, and use `/remote-control` normally.

## Billing note

`headroom-claude-rc` only stays on your subscription if you authenticated with
`claude /login`. A `setup-token` won't enable Remote Control, and an API key
bills the API. The forward proxy forwards whatever auth header Claude Code sends
— it does not change how you're billed.

## HIPAA

Same local-only decryption as the existing proxy mode: TLS is terminated locally,
the inference body is compressed, and only the (compressed) request egresses to
`api.anthropic.com` under Anthropic's BAA. Remote Control traffic is **blind-
tunnelled** — never decrypted — so it's strictly less exposure than the inference
path. The one new artifact is the mitmproxy CA private key; it stays in a local
Docker volume and is never committed. Telemetry beacon and cloud compression
remain hardened off (inherited from the base image).

## Known caveats (verify on first interactive run)

These could not be settled by the repo's `claude -p` capture harness, because
`-p` never starts a Remote Control session:

1. **`HTTPS_PROXY` and the Remote Control guard.** Documented disqualifiers are
   `ANTHROPIC_BASE_URL` and provider-override vars; `HTTPS_PROXY` is not among
   them. Confirm `/remote-control` actually pairs.
2. **Remote Control transport host.** If it uses a host other than
   `api.anthropic.com`, `--allow-hosts` tunnels it cleanly. If it shares
   `api.anthropic.com:443` (especially a websocket), watch `docker compose -f
   peerstar/remote-control/docker-compose.yml logs headroom-mitm` while pairing
   and narrow interception if needed.
3. **mitmproxy v12 passthrough.** Some versions reportedly *close* non-allowed
   connections instead of tunnelling them. Confirm non-Anthropic hosts still work
   (i.e. the session functions normally) on the `mitmproxy/mitmproxy:12` image.

If Remote Control won't pair through `HTTPS_PROXY`, the guard is broader than
documented — fall back to plain `claude` for Remote Control and `headroom-claude`
for max compression, and report the finding.

## Verify compression is happening

The proxy isn't published to the host. Check its stats from inside the network:

```powershell
docker compose -f peerstar\remote-control\docker-compose.yml exec headroom-proxy `
  python -c "import urllib.request,sys; sys.stdout.write(urllib.request.urlopen('http://127.0.0.1:8787/stats').read().decode())"
```

Look for `tokens_before > tokens_after` after a turn that read a large file —
including a turn you drove remotely.
