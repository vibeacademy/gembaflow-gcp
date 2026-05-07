"""One-line opt-in for the per-PR evidence page.

Downstream forks integrate the evidence page by adding a single call:

    from app.evidence_integration import attach_evidence_routes
    attach_evidence_routes(app)

This module is safe to import in any environment — `attach_evidence_routes`
short-circuits to a no-op outside `ENVIRONMENT=preview`, and the heavy
`app.api.evidence` and `app.evidence` modules are imported lazily inside
the function body so production never executes those imports.

The helper handles route precedence: the evidence page's `/` route is
moved to the front of the route list so it claims the home URL ahead of
any pre-existing handler. That is what allows the same fork to keep its
own `/` (e.g. a dashboard) in production while serving the evidence page
on preview.
"""

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI

    from app.config import Settings


def attach_evidence_routes(
    app: "FastAPI",
    settings: "Settings | None" = None,
) -> None:
    """Mount evidence routes on `app` iff settings.environment == 'preview'.

    Idempotent: calling twice on the same app has no additional effect.

    `settings` is optional — when omitted, `app.config.get_settings()` is
    invoked lazily so this module stays cheap to import.
    """
    if settings is None:
        from app.config import get_settings

        settings = get_settings()

    if settings.environment != "preview":
        return

    from app.api.evidence import evidence_page, router

    for existing in app.router.routes:
        if getattr(existing, "endpoint", None) is evidence_page:
            return

    before = len(app.router.routes)
    app.include_router(router)
    new_routes = app.router.routes[before:]
    del app.router.routes[before:]
    app.router.routes[:0] = new_routes
