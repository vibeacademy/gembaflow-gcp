"""FastAPI dependencies for Firebase session-cookie auth.

require_user — raises 401/redirect if the session cookie is missing or invalid
optional_user — returns None if unauthenticated instead of raising

Both populate request.state.user with the User SQLModel row on success.
"""

from __future__ import annotations

import logging
import os

from fastapi import Depends, HTTPException, Request, status
from sqlmodel import Session

from app.db import get_session
from app.models.user import User

logger = logging.getLogger(__name__)

SESSION_COOKIE_NAME = os.environ.get("SESSION_COOKIE_NAME", "af_session")


def _verify_cookie(request: Request) -> dict | None:
    """Verify the session cookie and return the decoded token claims, or None."""
    project_id = os.environ.get("FIREBASE_PROJECT_ID", "")
    if not project_id:
        return None

    cookie = request.cookies.get(SESSION_COOKIE_NAME)
    if not cookie:
        return None

    try:
        from firebase_admin import auth

        claims = auth.verify_session_cookie(cookie, check_revoked=True)
        return claims
    except Exception as exc:
        logger.debug("Session cookie invalid: %s", exc)
        return None


def optional_user(
    request: Request,
    session: Session = Depends(get_session),  # noqa: B008
) -> User | None:
    """Return the authenticated User row, or None if not signed in."""
    claims = _verify_cookie(request)
    if not claims:
        return None

    uid = claims.get("uid") or claims.get("user_id")
    user = session.get(User, uid)
    if user:
        request.state.user = user
    return user


def require_user(
    request: Request,
    user: User | None = Depends(optional_user),  # noqa: B008
) -> User:
    """Return the authenticated User row; raise 401 if not signed in."""
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user
