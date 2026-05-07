"""FastAPI application entrypoint.

Run locally:
    uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8080

Production (Cloud Run) runs the same command — see Dockerfile.

The `attach_evidence_routes(app)` call is preview-only: in any
environment other than `ENVIRONMENT=preview` it is a no-op. See
`docs/EVIDENCE-PAGES.md`.
"""

from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api import health, todos
from app.evidence_integration import attach_evidence_routes

app = FastAPI(title="Agile Flow GCP")

# Pico.css is loaded via CDN in base.html so this directory is light.
static_dir = Path(__file__).parent.parent / "static"
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

app.include_router(health.router)
app.include_router(todos.router)

attach_evidence_routes(app)
