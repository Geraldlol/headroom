"""Unit tests for the redirect addon's pure routing decision.

`route()` is intentionally import-safe without mitmproxy installed, so these run
on the host (where mitmproxy lives only inside the Docker container).
"""

from redirect_addon import (
    HEADROOM_HOST,
    HEADROOM_PORT,
    HEADROOM_SCHEME,
    route,
)

REDIRECT = (HEADROOM_SCHEME, HEADROOM_HOST, HEADROOM_PORT)


def test_post_messages_is_redirected():
    assert route("POST", "api.anthropic.com", "/v1/messages") == REDIRECT


def test_query_string_is_ignored():
    assert route("POST", "api.anthropic.com", "/v1/messages?beta=true") == REDIRECT


def test_trailing_slash_is_redirected():
    assert route("POST", "api.anthropic.com", "/v1/messages/") == REDIRECT


def test_method_is_case_insensitive():
    assert route("post", "api.anthropic.com", "/v1/messages") == REDIRECT


def test_host_is_case_insensitive():
    assert route("POST", "API.Anthropic.com", "/v1/messages") == REDIRECT


def test_count_tokens_is_not_redirected():
    # Different endpoint — must forward direct, not through compression.
    assert route("POST", "api.anthropic.com", "/v1/messages/count_tokens") is None


def test_batches_is_not_redirected():
    assert route("POST", "api.anthropic.com", "/v1/messages/batches") is None


def test_get_messages_is_not_redirected():
    # Only the inference POST is compressed.
    assert route("GET", "api.anthropic.com", "/v1/messages") is None


def test_other_anthropic_path_is_not_redirected():
    assert route("POST", "api.anthropic.com", "/v1/organizations/usage") is None


def test_root_path_is_not_redirected():
    assert route("POST", "api.anthropic.com", "/") is None


def test_other_host_is_not_redirected():
    # Defensive: --allow-hosts should keep these out, but never redirect them.
    assert route("POST", "statsig.anthropic.com", "/v1/messages") is None


def test_empty_inputs_fail_safe():
    assert route("", "", "") is None
    assert route(None, None, None) is None
