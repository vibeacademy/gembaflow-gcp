"""Starlette middleware that enforces auth for non-allowlisted routes.

When FIREBASE_PROJECT_ID is unset (local dev), this middleware is a no-op:
every request passes through unauthenticated. This avoids 500s or infinite
redirects when running without Firebase credentials.

Allowlisted paths (no auth required):
  /login, /check-email, /auth/*, /api/health*, /static/*, /healthz/*
  plus /api/error-events (crash reporter endpoint, unauthenticated by design)

Authenticated users visiting /login or /check-email are redirected to /.
"""

from __future__ import annotations

import logging
import os

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import RedirectResponse, Response
from starlette.types import ASGIApp

logger = logging.getLogger(__name__)

_ALLOWLIST_PREFIXES = (
    "/login",
    "/check-email",
    "/auth/",
    "/api/health",
    "/api/error-events",
    "/static/",
    "/healthz/",
    "/favicon.ico",
)

_AUTH_ONLY_PREFIXES = ("/login", "/check-email")


class FirebaseAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next: object) -> Response:
        project_id = os.environ.get("FIREBASE_PROJECT_ID", "")
        if not project_id:
            return await call_next(request)  # type: ignore[operator]

        path = request.url.path

        # Check if the request is for an allowlisted path
        is_allowed = any(path.startswith(prefix) for prefix in _ALLOWLIST_PREFIXES)

        user_claims = None
        if not is_allowed or any(path.startswith(prefix) for prefix in _AUTH_ONLY_PREFIXES):
            from app.auth.dependencies import SESSION_COOKIE_NAME

            cookie = request.cookies.get(SESSION_COOKIE_NAME)
            if cookie:
                try:
                    from firebase_admin import auth

                    user_claims = auth.verify_session_cookie(cookie, check_revoked=True)
                except Exception:
                    user_claims = None

        # Redirect authenticated users away from auth-only pages
        if any(path.startswith(prefix) for prefix in _AUTH_ONLY_PREFIXES) and user_claims:
            return RedirectResponse("/", status_code=303)

        # Block unauthenticated access to non-allowlisted routes
        if not is_allowed and user_claims is None:
            return RedirectResponse(f"/login?next={path}", status_code=303)

        return await call_next(request)  # type: ignore[operator]
