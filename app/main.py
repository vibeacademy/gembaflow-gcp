"""FastAPI application entrypoint.

Run locally:
    uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8080

Production (Cloud Run) runs the same command — see Dockerfile.
"""

import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api import health, todos
from app.auth.firebase import init_firebase
from app.auth.middleware import FirebaseAuthMiddleware
from app.auth.routes import router as auth_router

init_firebase()

app = FastAPI(title="Agile Flow GCP")

# Mount static files (CSS, images, favicon).
# Pico.css is loaded via CDN in base.html so this directory is light.
STATIC_DIR = Path(__file__).parent.parent / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

# Auth middleware — enforces sign-in for non-allowlisted routes.
# No-ops when FIREBASE_PROJECT_ID is unset (local dev mode).
app.add_middleware(FirebaseAuthMiddleware)

# Routes
app.include_router(health.router)

# Auth routes: /login, /check-email, /auth/callback, /auth/session, /auth/logout
app.include_router(auth_router)

# Evidence page — preview deployments only.
# ENVIRONMENT=preview is set by preview-deploy.yml. Production either omits
# the var or sets ENVIRONMENT=production. The check at startup ensures the
# evidence router is never registered in production (avoids any runtime branch).
# Registered BEFORE todos so that GET / is handled by the evidence page in
# preview instead of the todo home route.
if os.environ.get("ENVIRONMENT") == "preview":
    from app.api import evidence  # noqa: PLC0415

    app.include_router(evidence.router)

app.include_router(todos.router)
