"""Evidence page model for PR-level verification.

Each EvidenceSection represents one acceptance criterion from the PR.
The worker agent populates this file per-PR with probes that verify
the ticket work is real and visible.

Section anatomy:
  name        — human-readable label shown on the page
  probe       — callable() → (passed: bool, observation: str)
  explanation — reviewer-targeted prose: WHAT to look for and WHY
                it proves the work is real. Written for non-engineers.

Shipped as plain Python — no DSL, no magic. Workshop attendees read it
and learn the pattern.

Usage (from within the app):
    from app.evidence import SECTIONS

    results = [
        {
            "name": s.name,
            "passed": s.probe()[0],
            "observation": s.probe()[1],
            "explanation": s.explanation,
        }
        for s in SECTIONS
    ]
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass


@dataclass
class EvidenceSection:
    name: str
    probe: Callable[[], tuple[bool, str]]
    explanation: str


def _probe_framework_health() -> tuple[bool, str]:
    """Verify the app is running and responding to health checks."""
    try:
        import urllib.request

        req = urllib.request.urlopen("http://localhost:8080/api/health", timeout=2)
        body = req.read().decode()
        if '"ok"' in body:
            return True, 'GET /api/health returned {"status": "ok"}'
        return False, f"Unexpected response: {body[:80]}"
    except Exception as exc:
        return False, f"Health check failed: {exc}"


# ── Starter evidence section ─────────────────────────────────────────────────
#
# This section ships with the framework so PR-1 attendees see the pattern
# immediately. The worker agent adds sections per-ticket, then removes or
# replaces this one once the app has real acceptance criteria to verify.
SECTIONS: list[EvidenceSection] = [
    EvidenceSection(
        name="Framework health check",
        probe=_probe_framework_health,
        explanation=(
            "The app is running and its health endpoint returns OK. "
            "If this section is green, the deployment succeeded and the "
            "service is reachable. A red section means the deploy failed "
            "or the container is crashing — check the Cloud Run logs."
        ),
    ),
]
