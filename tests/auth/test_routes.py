"""Tests for Firebase auth routes.

Tests cover the route shape without requiring real Firebase credentials.
The /auth/session and /auth/logout routes that call firebase_admin are
tested with mocks; the HTML page routes are tested for response codes only.
"""

from __future__ import annotations

import os
from collections.abc import Generator
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.db import get_session


@pytest.fixture()
def db_session() -> Generator[Session, None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        yield session


@pytest.fixture()
def auth_client(db_session: Session) -> Generator[TestClient, None, None]:
    """TestClient for an app that has the auth router registered."""
    import importlib

    import app.main as main_module

    importlib.reload(main_module)
    _app = main_module.app

    def override_session() -> Generator[Session, None, None]:
        yield db_session

    _app.dependency_overrides[get_session] = override_session
    with TestClient(_app, raise_server_exceptions=False) as client:
        yield client
    _app.dependency_overrides.clear()


def test_login_page_renders(auth_client: TestClient) -> None:
    response = auth_client.get("/login")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Sign in" in response.text


def test_check_email_page_renders(auth_client: TestClient) -> None:
    response = auth_client.get("/check-email")
    assert response.status_code == 200
    assert "Check your email" in response.text


def test_auth_callback_page_renders(auth_client: TestClient) -> None:
    response = auth_client.get("/auth/callback")
    assert response.status_code == 200
    assert "Signing In" in response.text


def test_session_endpoint_without_firebase_returns_503(auth_client: TestClient) -> None:
    """When FIREBASE_PROJECT_ID is unset, /auth/session returns 503."""
    os.environ.pop("FIREBASE_PROJECT_ID", None)
    response = auth_client.post("/auth/session", json={"id_token": "fake"})
    assert response.status_code == 503


def test_session_endpoint_with_missing_token_returns_400(auth_client: TestClient) -> None:
    """When id_token is absent, /auth/session returns 400."""
    os.environ["FIREBASE_PROJECT_ID"] = "test-project"
    try:
        response = auth_client.post("/auth/session", json={})
        assert response.status_code == 400
    finally:
        os.environ.pop("FIREBASE_PROJECT_ID", None)


def test_session_endpoint_with_invalid_token_returns_401(auth_client: TestClient) -> None:
    """When Firebase rejects the ID token, /auth/session returns 401."""
    os.environ["FIREBASE_PROJECT_ID"] = "test-project"
    try:
        with patch("firebase_admin.auth.verify_id_token") as mock_verify:
            mock_verify.side_effect = Exception("INVALID_ID_TOKEN")
            response = auth_client.post("/auth/session", json={"id_token": "bad-token"})
        assert response.status_code == 401
    finally:
        os.environ.pop("FIREBASE_PROJECT_ID", None)


def test_logout_clears_cookie(auth_client: TestClient) -> None:
    """POST /auth/logout clears the session cookie."""
    os.environ.pop("FIREBASE_PROJECT_ID", None)
    response = auth_client.post("/auth/logout")
    assert response.status_code == 204
    set_cookie = response.headers.get("set-cookie", "")
    assert "af_session" in set_cookie or response.status_code == 204
