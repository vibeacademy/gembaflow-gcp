"""Tests for the per-PR evidence page.

Three layers under test:

1. Helper wiring — `attach_evidence_routes` mounts evidence routes only
   when settings.environment == "preview", reorders so the evidence `/`
   wins against pre-existing `/` handlers, and is idempotent.

2. Runner contract — `evaluate_sections` returns the documented shape
   the worker agent consumes via /healthz/evidence.

3. Defensive runner behavior — a probe that crashes is reported as
   failed rather than propagating.

End-to-end validation that probes work against PostgreSQL happens on
the preview deploy itself (see docs/EVIDENCE-PAGES.md). The test DB is
SQLite, so the framework "preview matches production" probe is
*expected* to report failure on a dialect mismatch — that failure is
itself evidence that the probe inspects the live connection.
"""

from collections.abc import Generator

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlmodel import Session

from app.config import Settings, get_settings
from app.db import get_session
from app.evidence import (
    SECTIONS,
    EvidenceSection,
    ProbeContext,
    ProbeResult,
    evaluate_sections,
)
from app.evidence_integration import attach_evidence_routes


def _preview_settings() -> Settings:
    """Build a Settings instance flagged as preview, bypassing validators.

    Validators would refuse the SQLite default URL outside dev. Tests
    don't actually connect to Postgres — they exercise routing and
    runner shape, so model_construct is appropriate here.
    """
    return Settings.model_construct(
        environment="preview",
        database_url="sqlite://",
        app_url="http://testserver",
    )


def _development_settings() -> Settings:
    return Settings.model_construct(
        environment="development",
        database_url="sqlite://",
        app_url="http://testserver",
    )


# --- Helper wiring --------------------------------------------------------


def test_attach_mounts_routes_in_preview() -> None:
    app = FastAPI()
    attach_evidence_routes(app, _preview_settings())

    paths = {getattr(route, "path", None) for route in app.router.routes}
    assert "/" in paths
    assert "/healthz/evidence" in paths


def test_attach_is_noop_outside_preview() -> None:
    app = FastAPI()
    attach_evidence_routes(app, _development_settings())

    paths = {getattr(route, "path", None) for route in app.router.routes}
    assert "/" not in paths
    assert "/healthz/evidence" not in paths


def test_attach_is_idempotent() -> None:
    app = FastAPI()
    attach_evidence_routes(app, _preview_settings())
    n_after_first = len(app.router.routes)
    attach_evidence_routes(app, _preview_settings())
    assert len(app.router.routes) == n_after_first


def test_attach_reorders_so_evidence_root_wins_over_existing_home() -> None:
    """Pre-existing `/` handlers should not shadow the evidence page in preview."""
    from app.api.evidence import evidence_page

    app = FastAPI()

    @app.get("/")
    def existing_home() -> dict:
        return {"page": "user-home"}

    attach_evidence_routes(app, _preview_settings())

    evidence_idx = next(
        i
        for i, route in enumerate(app.router.routes)
        if getattr(route, "endpoint", None) is evidence_page
    )
    existing_idx = next(
        i
        for i, route in enumerate(app.router.routes)
        if getattr(route, "endpoint", None) is existing_home
    )
    assert evidence_idx < existing_idx


# --- Helper integration via TestClient ------------------------------------


@pytest.fixture(name="preview_client")
def preview_client_fixture(session: Session) -> Generator[TestClient, None, None]:
    """TestClient running an app with evidence routes attached in preview mode."""
    settings = _preview_settings()
    app = FastAPI()
    attach_evidence_routes(app, settings)

    def session_override() -> Generator[Session, None, None]:
        yield session

    app.dependency_overrides[get_session] = session_override
    app.dependency_overrides[get_settings] = lambda: settings

    with TestClient(app) as client:
        yield client


def test_evidence_page_renders_in_preview(preview_client: TestClient) -> None:
    response = preview_client.get("/")
    assert response.status_code == 200
    assert "Preview verification" in response.text


# --- Runner contract ------------------------------------------------------


def test_evidence_json_shape(preview_client: TestClient) -> None:
    """JSON contract is what the worker agent depends on."""
    body = preview_client.get("/healthz/evidence").json()
    assert set(body.keys()) == {"passed", "sections"}
    assert isinstance(body["passed"], bool)
    assert isinstance(body["sections"], list)
    assert len(body["sections"]) == len(SECTIONS)
    for section in body["sections"]:
        assert set(section.keys()) == {"name", "passed", "observation", "explanation"}
        assert isinstance(section["passed"], bool)


def test_aggregate_passed_reflects_section_results(preview_client: TestClient) -> None:
    """Top-level `passed` is the AND of every section's `passed`."""
    body = preview_client.get("/healthz/evidence").json()
    expected = all(section["passed"] for section in body["sections"])
    assert body["passed"] is expected


def test_todos_starter_probe_passes_against_test_db(session: Session) -> None:
    """The per-feature starter probe (todos read path) succeeds when the
    schema is present — which it is in the in-memory test DB."""
    settings = _preview_settings()
    results = evaluate_sections(ProbeContext(session=session, settings=settings))

    todos_section = next(
        (r for r in results if r["name"] == "The todo list is reachable through the database"),
        None,
    )
    assert todos_section is not None
    assert todos_section["passed"] is True
    assert "queryable" in todos_section["observation"]


def test_infra_probe_reports_dialect_mismatch_against_sqlite(session: Session) -> None:
    """The infra-sanity probe is supposed to fail when the database is not
    PostgreSQL — proving it actually inspects the live connection rather
    than always returning green. This test pins that contract."""
    settings = _preview_settings()
    results = evaluate_sections(ProbeContext(session=session, settings=settings))

    infra_section = next(
        (r for r in results if r["name"] == "Preview is wired the same way production is"),
        None,
    )
    assert infra_section is not None
    assert infra_section["passed"] is False
    assert "sqlite" in infra_section["observation"]


# --- Defensive runner behavior --------------------------------------------


def test_runner_treats_probe_crash_as_failure(
    session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A probe that raises is reported as failed — never propagates."""

    def boom(_ctx: ProbeContext) -> ProbeResult:
        raise RuntimeError("probe is broken")

    crashing = EvidenceSection(
        name="Intentionally broken probe",
        explanation="Tests the runner's exception handling.",
        probe=boom,
    )
    monkeypatch.setattr("app.evidence.SECTIONS", [crashing])

    settings = _preview_settings()
    results = evaluate_sections(ProbeContext(session=session, settings=settings))

    assert len(results) == 1
    assert results[0]["passed"] is False
    assert "RuntimeError" in results[0]["observation"]
    assert "probe is broken" in results[0]["observation"]
