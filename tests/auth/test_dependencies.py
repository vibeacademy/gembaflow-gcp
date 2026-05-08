"""Tests for Firebase auth FastAPI dependencies.

firebase-admin is not installed in the dev environment, so all tests
that would call Firebase APIs mock the verify_session_cookie call and
test the dependency's behavior around it.
"""

from __future__ import annotations

import os
from collections.abc import Generator
from unittest.mock import patch

import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.auth.dependencies import optional_user, require_user
from app.db import get_session
from app.models.user import User


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
def test_app(db_session: Session) -> TestClient:
    _app = FastAPI()

    @_app.get("/protected")
    def protected(user: User = Depends(require_user)):  # noqa: B008
        return {"uid": user.firebase_uid}

    @_app.get("/optional")
    def optional(user: User | None = Depends(optional_user)):  # noqa: B008
        return {"uid": user.firebase_uid if user else None}

    def override_session() -> Generator[Session, None, None]:
        yield db_session

    _app.dependency_overrides[get_session] = override_session
    return TestClient(_app, raise_server_exceptions=False)


def test_require_user_without_firebase_configured(test_app: TestClient) -> None:
    """When FIREBASE_PROJECT_ID is not set, require_user raises 401."""
    os.environ.pop("FIREBASE_PROJECT_ID", None)
    response = test_app.get("/protected")
    assert response.status_code == 401


def test_optional_user_without_firebase_configured(test_app: TestClient) -> None:
    """When FIREBASE_PROJECT_ID is not set, optional_user returns None."""
    os.environ.pop("FIREBASE_PROJECT_ID", None)
    response = test_app.get("/optional")
    assert response.status_code == 200
    assert response.json() == {"uid": None}


def test_require_user_with_valid_cookie(test_app: TestClient, db_session: Session) -> None:
    """When cookie is valid, require_user returns the User row."""
    from datetime import datetime

    user = User(firebase_uid="uid-123", email="alice@example.com",
                created_at=datetime.utcnow(), last_login_at=datetime.utcnow())
    db_session.add(user)
    db_session.commit()

    with patch.dict(os.environ, {"FIREBASE_PROJECT_ID": "test-project"}):
        with patch("firebase_admin.auth.verify_session_cookie") as mock_verify:
            mock_verify.return_value = {"uid": "uid-123", "email": "alice@example.com"}
            client = TestClient(test_app.app, raise_server_exceptions=False,
                                cookies={"af_session": "fake-cookie"})
            response = client.get("/protected")

    assert response.status_code == 200
    assert response.json()["uid"] == "uid-123"


def test_require_user_with_expired_cookie(test_app: TestClient) -> None:
    """When cookie is expired/revoked, require_user raises 401."""
    with patch.dict(os.environ, {"FIREBASE_PROJECT_ID": "test-project"}):
        with patch("firebase_admin.auth.verify_session_cookie") as mock_verify:
            mock_verify.side_effect = Exception("TOKEN_EXPIRED")
            client = TestClient(test_app.app, raise_server_exceptions=False,
                                cookies={"af_session": "expired-cookie"})
            response = client.get("/protected")

    assert response.status_code == 401
