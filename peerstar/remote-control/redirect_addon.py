r"""mitmproxy addon — route Claude Code's Anthropic inference calls through the
hardened Headroom compression proxy, and leave everything else untouched.

Loaded by:
    mitmdump --mode regular \
        --allow-hosts '^api\.anthropic\.com:443$' \
        -s /addon/redirect_addon.py

How it fits together
--------------------
Claude Code is pointed here with ``HTTPS_PROXY`` (NOT ``ANTHROPIC_BASE_URL``),
so Remote Control's "no base-URL override" guard is satisfied. ``--allow-hosts``
means only the HTTPS CONNECT to api.anthropic.com is intercepted; every other
host (the Remote Control relay, telemetry, etc.) is blind-tunnelled and never
reaches this addon.

For the one host we do intercept, only ``POST /v1/messages`` (the inference
endpoint) is redirected into the local Headroom reverse proxy, which performs
all compression and forwards to the real API. Other api.anthropic.com paths
(token refresh, ``/v1/messages/count_tokens``, ``/v1/messages/batches``) are
forwarded direct. The client's Authorization header is preserved end-to-end, so
subscription billing is unaffected.

``route()`` is deliberately free of any mitmproxy import so it can be unit-tested
on the host, where mitmproxy is only present inside the container.
"""

from __future__ import annotations

import logging
import os

logger = logging.getLogger("headroom-rc")

# The only host we intercept (kept in sync with mitmdump --allow-hosts).
PROXY_HOST = "api.anthropic.com"

# Where the hardened Headroom reverse proxy is reachable on the compose network.
HEADROOM_SCHEME = os.environ.get("HEADROOM_RC_SCHEME", "http")
HEADROOM_HOST = os.environ.get("HEADROOM_RC_HOST", "headroom-proxy")
HEADROOM_PORT = int(os.environ.get("HEADROOM_RC_PORT", "8787"))

# Exact inference endpoint — NOT subpaths like /count_tokens or /batches.
MESSAGES_PATH = "/v1/messages"


def route(method, host, path):
    """Decide where a request should go.

    Returns ``(scheme, host, port)`` to redirect the flow into the Headroom
    proxy, or ``None`` to leave the request untouched (forward direct).
    """
    if not host or host.lower() != PROXY_HOST:
        return None
    if not method or method.upper() != "POST":
        return None
    base = (path or "").split("?", 1)[0].rstrip("/")
    if base != MESSAGES_PATH:
        return None
    return (HEADROOM_SCHEME, HEADROOM_HOST, HEADROOM_PORT)


# --- mitmproxy runtime glue (absent during host-side unit tests) -------------
try:
    from mitmproxy.connection import Server

    _HAVE_MITM = True
except Exception:  # pragma: no cover - exercised only inside the container
    Server = None  # type: ignore[assignment]
    _HAVE_MITM = False


def request(flow) -> None:  # pragma: no cover - requires a live mitmproxy flow
    """mitmproxy request hook: redirect inference, fail open on any error."""
    try:
        target = route(
            flow.request.method,
            flow.request.pretty_host,
            flow.request.path,
        )
        if target is None:
            return
        scheme, host, port = target

        # Preserve the original Host header so the upstream still sees
        # api.anthropic.com after we re-point the TCP destination.
        original_host_header = flow.request.host_header

        # Drop any pooled upstream socket so the new destination is actually
        # used instead of reusing the api.anthropic.com connection
        # (mitmproxy/mitmproxy#4840).
        if _HAVE_MITM and flow.server_conn.timestamp_start is not None:
            flow.server_conn = Server(address=(host, port))

        flow.request.scheme = scheme
        flow.request.host = host
        flow.request.port = port
        if original_host_header:
            flow.request.host_header = original_host_header
    except Exception as exc:
        # Never block a turn because routing errored — forward as-is.
        logger.warning("[headroom-rc] routing error, forwarding direct: %s", exc)
