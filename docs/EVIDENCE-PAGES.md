# Evidence Pages: Reviewer-Facing Verification on Preview Deploys

Non-technical reviewers cannot meaningfully review early infrastructure PRs
just by looking at the diff or clicking the preview URL — the work is real
but invisible (DB schema, auth plumbing, API scaffolding). The evidence
page makes the invisible work visible: every PR's preview deploy serves
a page at `/` that says, in reviewer-targeted prose, whether each
acceptance criterion of the ticket actually works against the
production-shaped infrastructure.

This document explains the model, the contract, and how to add a section
when you implement a ticket.

---

## Model

- One Python file: [app/evidence.py](../app/evidence.py).
- The file exports a list `SECTIONS: list[EvidenceSection]`.
- Each `EvidenceSection` has a `name`, a reviewer-targeted `explanation`,
  and a `probe` callable that runs live against the deploy's database
  and configuration.
- The worker agent **edits this file on every PR**, appending one section
  per acceptance criterion.

The evidence module is plain Python, not a DSL. Workshop attendees are
learning Python; another abstraction layer would defeat the pedagogy.

---

## Routes

The evidence routes are mounted **only when `ENVIRONMENT=preview`**.
The decision happens once at startup in [app/main.py](../app/main.py),
not per request — that way an accidental leak to production is a
deploy-time misconfiguration (catchable by smoke tests), not a runtime
code-path bug.

| Route | Audience | Returns |
|-------|----------|---------|
| `/` | Human reviewer | HTML evidence page with banners and sections |
| `/healthz/evidence` | Worker agent | JSON `{passed, sections: [...]}` |

`ENVIRONMENT=preview` is set by [.github/workflows/preview-deploy.yml](../.github/workflows/preview-deploy.yml).
Production sets `ENVIRONMENT=production` via [.github/workflows/deploy.yml](../.github/workflows/deploy.yml),
so the production home page is whatever [app/main.py](../app/main.py)
routes through `todos.router` say it is.

### `/healthz/evidence` JSON shape

This is a stable contract — the worker agent depends on it.

```json
{
  "passed": true,
  "sections": [
    {
      "name": "Preview is wired the same way production is",
      "passed": true,
      "observation": "ENVIRONMENT=preview, database is PostgreSQL, schema is at migration 7a8b9c.",
      "explanation": "Production runs on Cloud Run with a Neon-hosted PostgreSQL ..."
    }
  ]
}
```

`passed` at the top level is the AND of every section's `passed`.
A probe that crashes is reported as a failed section with the
exception class and message in `observation` — never propagates.

---

## How to add a section in your PR

1. Open [app/evidence.py](../app/evidence.py).
2. Write a probe function that takes a `ProbeContext` (which exposes
   `session: Session` and `settings: Settings`) and returns a
   `ProbeResult(passed: bool, observation: str)`.
3. Append an `EvidenceSection(name, explanation, probe)` to `SECTIONS`.
4. Push the branch and let the preview deploy. Hit `/healthz/evidence`
   on the preview URL to verify the section returns `passed: true`.

The `compose-evidence-page` skill (under `.claude/skills/`) turns a
ticket's acceptance criteria into proposed sections — invoke it from
the worker agent rather than composing sections from scratch.

### Probe rules

- **Read-only.** Every reviewer page-load runs every probe.
- **Fast.** Sub-second. This page is not for expensive checks.
- **Use the ORM or `sqlmodel`/`sqlalchemy.text(...)`** so the probe
  works against PostgreSQL (production and preview both run Neon).
- **Treat your own failures as evidence.** A probe that crashes is
  automatically reported as a failed section, but the reviewer would
  rather read a useful "what we expected vs. what we found" message
  than a stack trace.

### Explanation rules

The `explanation` is for the reviewer, not the engineer. Compare:

- Engineer-targeted (avoid): "the `email_verified_at` column was added
  per the migration in `versions/7a8b9c_add_email_verified_at.py`."
- Reviewer-targeted (do this): "If you can submit the form below and
  see a row with the new verification timestamp, the schema change is
  real and the column round-trips through the production-shaped database."

When in doubt, run the page past someone who would not read the diff.

---

## What the page looks like

Both descriptions below are taken on a preview deploy at the URL
`https://app-pr-N-<hash>-uc.a.run.app/`.

### Green path

> **Preview verification — all green**
>
> This page only renders on preview deploys. Production looks different —
> see the linked PR for the actual product change. Each section below
> tells you whether one piece of the work was done correctly. Read the
> explanation, check the result, and merge when you are satisfied.
>
> **All sections pass.** The preview is wired the same way production
> is, and the change appears to function in that configuration.
>
> ---
>
> **PASS — Preview is wired the same way production is**
> Production runs on Cloud Run with a Neon-hosted PostgreSQL database
> and an Alembic-managed schema. This section checks all three on this
> preview revision. *What this probe saw:* ENVIRONMENT=preview,
> database is PostgreSQL, schema is at migration 7a8b9c.
>
> **PASS — The todo list is reachable through the database**
> Reads the todos table from the database. If green, the read path is
> live: connection works, schema has the table the code expects, ORM
> is wired correctly. *What this probe saw:* Todos table is queryable
> on this deploy (currently has 3 row(s)).

### Red path

> **Preview verification — needs review**
>
> **One or more sections failed.** Read the failures below before
> approving — the preview may not match production, or the change may
> not function in the production configuration.
>
> ---
>
> **FAIL — Preview is wired the same way production is**
> *What this probe saw:* Mismatch: database is at migration 'a3f1d2';
> code expects '7a8b9c' (migrations did not run before this revision
> started serving).
>
> **PASS — The todo list is reachable through the database**
> *What this probe saw:* Todos table is queryable on this deploy.

A red evidence page **does not block PR creation.** The reviewer
needs to see the red page to make an informed call. The worker agent
posts a PR comment with a checklist describing what could not be
auto-verified, then hands off.

---

## Auto-repair budget

The worker agent gets **exactly one repair attempt** per PR after
seeing a red probe. Subsequent reds → handoff comment, no further
auto-fix. This prevents infinite loops on probe-vs-implementation
drift.

If you find yourself wanting to relax this rule: don't. The repair
budget exists because a probe that needs three rewrites is a probe
that's wrong about its own acceptance criterion.

---

## Distributing this capability to existing forks

New forks of `agile-flow-gcp` get the evidence-page runtime for free —
it's part of the template's `app/` scaffolding. Forks that predate
this branch can catch up by running the bundled installer:

```bash
bash scripts/install-evidence-page.sh
```

The installer is idempotent: running it twice changes nothing. It
copies the runtime files (`app/evidence.py`, `app/api/evidence.py`,
`app/evidence_integration.py`, `templates/evidence.html`, the CSS
additions, and `tests/test_evidence.py`) and adds two lines to
`app/main.py`:

```python
from app.evidence_integration import attach_evidence_routes
attach_evidence_routes(app)
```

`attach_evidence_routes` is a no-op outside `ENVIRONMENT=preview`, so
production behavior is unchanged. The call is injected after the last
`app.include_router(...)` line; if the installer cannot find a safe
anchor (e.g. an unconventional `app/main.py` shape) it aborts with the
two-line snippet to add manually rather than guess. After injecting,
the installer runs a smoke test (`uv run python -c 'import app.main'`)
and aborts non-zero if the resulting module fails to import — the
install never silently leaves you in a worse state than it found you.
See the script's header for details.

---

## Out of scope

- **Visual / no-code evidence builder.** The agent writes Python.
  That's the model.
- **Cross-PR evidence aggregation.** Each PR's evidence page is what
  is in that PR's `app/evidence.py`. Merging replaces it.
- **History retention.** Preview revisions are torn down when the PR
  closes; evidence pages are tied to the revision and disappear with it.

---

## Related

- [app/evidence.py](../app/evidence.py) — section list and starter probes
- [app/api/evidence.py](../app/api/evidence.py) — route handlers
- [app/evidence_integration.py](../app/evidence_integration.py) — `attach_evidence_routes` opt-in helper
- [templates/evidence.html](../templates/evidence.html) — page template
- [docs/EPHEMERAL-PR-ENVIRONMENTS.md](EPHEMERAL-PR-ENVIRONMENTS.md) — how preview deploys work
- [.claude/skills/compose-evidence-page.md](../.claude/skills/compose-evidence-page.md) — turn ticket AC into probe sections
- Tracked in #170.
