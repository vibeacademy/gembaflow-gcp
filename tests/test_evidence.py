"""Tests for the evidence page routes.

The evidence router is only mounted when ENVIRONMENT=preview. Tests
create an isolated app instance with that env var set so the routes
are registered, without affecting the shared `client` fixture.
"""

import os

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.db import get_session


@pytest.fixture()
def preview_client(session: Session) -> TestClient:
    """TestClient for an app instance running in preview mode."""
    os.environ["ENVIRONMENT"] = "preview"
    try:
        import importlib

        import app.main as main_module

        importlib.reload(main_module)
        preview_app = main_module.app

        def get_session_override():
            yield session

        preview_app.dependency_overrides[get_session] = get_session_override
        client = TestClient(preview_app)
        yield client
        preview_app.dependency_overrides.clear()
    finally:
        del os.environ["ENVIRONMENT"]
        import app.main as main_module  # noqa: PLC0415

        importlib.reload(main_module)


def test_evidence_json_endpoint_returns_structured_result(
    preview_client: TestClient,
) -> None:
    response = preview_client.get("/healthz/evidence")
    assert response.status_code == 200
    body = response.json()
    assert "passed" in body
    assert "sections" in body
    assert isinstance(body["sections"], list)
    assert len(body["sections"]) >= 1
    section = body["sections"][0]
    assert "name" in section
    assert "passed" in section
    assert "observation" in section
    assert "explanation" in section


def test_evidence_page_renders_html(preview_client: TestClient) -> None:
    response = preview_client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "PR Verification" in response.text
    assert "Preview environment" in response.text


def test_evidence_json_all_passed_reflects_sections(
    preview_client: TestClient,
) -> None:
    response = preview_client.get("/healthz/evidence")
    body = response.json()
    computed_all_passed = all(s["passed"] for s in body["sections"])
    assert body["passed"] == computed_all_passed


def test_evidence_routes_not_mounted_in_production(session: Session) -> None:
    """Without ENVIRONMENT=preview the evidence routes must not exist."""
    os.environ.pop("ENVIRONMENT", None)
    import importlib

    import app.main as main_module

    importlib.reload(main_module)
    prod_app = main_module.app

    def get_session_override():
        yield session

    prod_app.dependency_overrides[get_session] = get_session_override
    try:
        client = TestClient(prod_app)
        response = client.get("/healthz/evidence")
        assert response.status_code == 404
    finally:
        prod_app.dependency_overrides.clear()
        importlib.reload(main_module)
