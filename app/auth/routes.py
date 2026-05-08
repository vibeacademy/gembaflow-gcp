"""Auth routes for Firebase email-link (magic link) sign-in.

GET  /login           — email input form
GET  /check-email     — "check your inbox" confirmation
GET  /auth/callback   — magic link landing; exchanges link for ID token (JS)
POST /auth/session    — exchanges ID token for HttpOnly session cookie
POST /auth/logout     — clears the session cookie, revokes refresh tokens
"""

from __future__ import annotations

import logging
import os
from datetime import timedelta

from fastapi import APIRouter, Depends, Request, Response, status
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlmodel import Session

from app.auth.dependencies import SESSION_COOKIE_NAME, optional_user
from app.db import get_session
from app.models.user import User
from app.templates import templates

router = APIRouter()
logger = logging.getLogger(__name__)

SESSION_MAX_AGE = int(os.environ.get("SESSION_COOKIE_MAX_AGE", str(5 * 24 * 3600)))
_SESSION_EXPIRES_IN = timedelta(seconds=SESSION_MAX_AGE)


def _is_production() -> bool:
    return os.environ.get("ENVIRONMENT", "development") == "production"


@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request, current_user: User | None = Depends(optional_user)):  # noqa: B008
    if current_user is not None:
        return RedirectResponse("/", status_code=status.HTTP_303_SEE_OTHER)
    firebase_project_id = os.environ.get("FIREBASE_PROJECT_ID", "")
    return templates.TemplateResponse(
        request,
        "auth/login.html",
        {"firebase_project_id": firebase_project_id},
    )


@router.get("/check-email", response_class=HTMLResponse)
async def check_email_page(request: Request):
    return templates.TemplateResponse(request, "auth/check_email.html", {})


@router.get("/auth/callback", response_class=HTMLResponse)
async def auth_callback_page(request: Request):
    firebase_project_id = os.environ.get("FIREBASE_PROJECT_ID", "")
    return templates.TemplateResponse(
        request,
        "auth/callback.html",
        {"firebase_project_id": firebase_project_id},
    )


@router.post("/auth/session", status_code=status.HTTP_204_NO_CONTENT)
async def create_session(
    request: Request,
    response: Response,
    db: Session = Depends(get_session),  # noqa: B008
):
    """Exchange an ID token for an HttpOnly session cookie.

    Body: JSON {"id_token": "<firebase-id-token>"}
    """
    project_id = os.environ.get("FIREBASE_PROJECT_ID", "")
    if not project_id:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return

    body = await request.json()
    id_token = body.get("id_token", "")
    if not id_token:
        response.status_code = status.HTTP_400_BAD_REQUEST
        return

    try:
        from firebase_admin import auth

        decoded = auth.verify_id_token(id_token)
        uid = decoded["uid"]
        email = decoded.get("email", "")

        session_cookie = auth.create_session_cookie(id_token, expires_in=_SESSION_EXPIRES_IN)

        user = db.get(User, uid)
        from datetime import datetime

        now = datetime.utcnow()
        if user is None:
            user = User(firebase_uid=uid, email=email, created_at=now, last_login_at=now)
            db.add(user)
        else:
            user.last_login_at = now
            db.add(user)
        db.commit()

        secure = _is_production()
        response.set_cookie(
            key=SESSION_COOKIE_NAME,
            value=session_cookie,
            max_age=SESSION_MAX_AGE,
            httponly=True,
            secure=secure,
            samesite="lax",
        )
    except Exception as exc:
        logger.warning("Session creation failed: %s", exc)
        response.status_code = status.HTTP_401_UNAUTHORIZED


@router.post("/auth/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    request: Request,
    response: Response,
    current_user: User | None = Depends(optional_user),  # noqa: B008
):
    """Clear the session cookie and revoke Firebase refresh tokens."""
    if current_user is not None:
        try:
            from firebase_admin import auth

            auth.revoke_refresh_tokens(current_user.firebase_uid)
        except Exception as exc:
            logger.warning("Token revocation failed for %s: %s", current_user.firebase_uid, exc)

    response.delete_cookie(key=SESSION_COOKIE_NAME, httponly=True, samesite="lax")
