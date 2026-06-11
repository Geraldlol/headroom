"""CORS and observability-route exposure guards for the local proxy."""

from __future__ import annotations

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("httpx")

from fastapi.testclient import TestClient

from headroom.proxy.server import ProxyConfig, create_app


@pytest.fixture(autouse=True)
def _allow_python_only_proxy_for_route_tests(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("HEADROOM_REQUIRE_RUST_CORE", "false")


def _app():
    return create_app(
        ProxyConfig(
            optimize=False,
            cache_enabled=False,
            rate_limit_enabled=False,
            cost_tracking_enabled=False,
            log_requests=False,
            ccr_inject_tool=False,
            ccr_handle_responses=False,
            ccr_context_tracking=False,
        )
    )


def test_dashboard_remains_available_to_loopback_callers() -> None:
    with TestClient(_app(), client=("127.0.0.1", 12345)) as client:
        response = client.get("/dashboard")

    assert response.status_code == 200
    assert "html" in response.text.lower()


def test_observability_routes_are_hidden_from_external_callers_without_admin_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("HEADROOM_ADMIN_TOKEN", raising=False)

    with TestClient(_app(), client=("10.0.0.10", 12345)) as client:
        for path in ("/dashboard", "/stats", "/v1/telemetry", "/v1/toin/stats"):
            response = client.get(path)
            assert response.status_code == 404, path


def test_observability_routes_accept_external_callers_with_admin_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("HEADROOM_ADMIN_TOKEN", "test-admin-token")

    with TestClient(_app(), client=("10.0.0.10", 12345)) as client:
        response = client.get(
            "/dashboard",
            headers={"X-Headroom-Admin-Token": "test-admin-token"},
        )

    assert response.status_code == 200


def test_wildcard_cors_does_not_allow_credentials() -> None:
    with TestClient(_app(), client=("127.0.0.1", 12345)) as client:
        response = client.options(
            "/stats",
            headers={
                "Origin": "https://example.invalid",
                "Access-Control-Request-Method": "GET",
            },
        )

    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "*"
    assert "access-control-allow-credentials" not in response.headers
