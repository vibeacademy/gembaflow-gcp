"""Firebase Admin SDK initialization.

Loaded once at app startup. Degrades gracefully when FIREBASE_PROJECT_ID is
unset (local dev without Firebase) — firebase_app() returns None and all
auth checks treat every request as unauthenticated.

Service account JSON is read from Google Secret Manager using the secret name
in FIREBASE_SERVICE_ACCOUNT_SECRET_NAME. Falls back to the env var
FIREBASE_SERVICE_ACCOUNT_JSON for local dev (not for production).
"""

from __future__ import annotations

import json
import logging
import os
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import firebase_admin

_app: firebase_admin.App | None = None
_init_attempted = False

logger = logging.getLogger(__name__)


def _load_service_account_json() -> dict | None:
    """Load Firebase service account JSON from Secret Manager or env var."""
    secret_name = os.environ.get("FIREBASE_SERVICE_ACCOUNT_SECRET_NAME", "")
    project_id = os.environ.get("FIREBASE_PROJECT_ID", "")

    if secret_name and project_id:
        try:
            from google.cloud import secretmanager  # type: ignore[import-untyped]

            client = secretmanager.SecretManagerServiceClient()
            name = f"projects/{project_id}/secrets/{secret_name}/versions/latest"
            response = client.access_secret_version(request={"name": name})
            return json.loads(response.payload.data.decode("utf-8"))
        except Exception:
            logger.warning(
                "Could not load Firebase service account from Secret Manager; "
                "falling back to FIREBASE_SERVICE_ACCOUNT_JSON env var."
            )

    raw = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "")
    if raw:
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON; ignoring.")

    return None


def init_firebase() -> None:
    """Initialize the Firebase Admin SDK. Safe to call multiple times (idempotent)."""
    global _app, _init_attempted
    if _init_attempted:
        return
    _init_attempted = True

    project_id = os.environ.get("FIREBASE_PROJECT_ID", "")
    if not project_id:
        logger.info("FIREBASE_PROJECT_ID not set — Firebase auth disabled (local dev mode).")
        return

    try:
        import firebase_admin
        from firebase_admin import credentials

        if firebase_admin._apps:  # noqa: SLF001
            _app = firebase_admin.get_app()
            return

        sa_json = _load_service_account_json()
        if sa_json:
            cred = credentials.Certificate(sa_json)
        else:
            # Application Default Credentials (works on Cloud Run with the runtime SA)
            cred = credentials.ApplicationDefault()

        _app = firebase_admin.initialize_app(cred, {"projectId": project_id})
        logger.info("Firebase Admin SDK initialized for project %s", project_id)
    except Exception as exc:
        logger.error("Firebase Admin SDK initialization failed: %s", exc)
        _app = None


def firebase_app() -> firebase_admin.App | None:
    """Return the initialized Firebase app, or None if Firebase is disabled."""
    return _app
