# Evidence Pages

Evidence pages solve a real workshop problem: non-technical reviewers cannot
meaningfully review early infrastructure or schema PRs. The work is real but
invisible — DB migrations, auth plumbing, API scaffolding have no UI to look at.

Evidence pages give reviewers something concrete: a page (visible on the PR
preview URL) that explains what changed, runs a live probe against the deployed
code, and reports pass or fail in plain language.

---

## How it works

### On every preview deploy

Cloud Run preview deployments set `ENVIRONMENT=preview`. The app detects this
at startup and registers two additional routes:

| Route | Purpose |
|---|---|
| `GET /` | HTML evidence page for reviewers |
| `GET /healthz/evidence` | JSON probe results for the agent |

Production deployments omit `ENVIRONMENT=preview`, so neither route is
registered and the production home page is unaffected.

### The evidence page

The page at `/` (preview only) shows:
- A green or red banner summarising whether all checks passed
- One section per `EvidenceSection` in `app/evidence.py`, each with:
  - A pass/fail indicator
  - What the live probe found (e.g. a SQL query result, an HTTP response)
  - A reviewer-targeted explanation of why this proves the work is real

Reviewers click the preview URL from the PR, read the page, and decide whether
to approve. They do not need to understand the code.

### The JSON endpoint

`GET /healthz/evidence` returns:

```json
{
  "passed": true,
  "sections": [
    {
      "name": "Section name",
      "passed": true,
      "observation": "What the probe found",
      "explanation": "Why this matters"
    }
  ]
}
```

The worker agent `curl`s this endpoint after the preview deploy to decide
whether to post a "green" or "red" PR comment before handing off to the
reviewer.

---

## Writing evidence sections

Edit `app/evidence.py` and add an `EvidenceSection` to the `SECTIONS` list.

```python
# app/evidence.py
from app.evidence import EvidenceSection

def _probe_users_table_has_email_verified_at() -> tuple[bool, str]:
    from app.db import get_sync_session
    from sqlalchemy import text
    with get_sync_session() as session:
        result = session.execute(
            text("SELECT column_name FROM information_schema.columns "
                 "WHERE table_name='users' AND column_name='email_verified_at'")
        ).fetchone()
    if result:
        return True, "Column email_verified_at exists in the users table"
    return False, "Column email_verified_at NOT found in users table"

SECTIONS = [
    EvidenceSection(
        name="users.email_verified_at column",
        probe=_probe_users_table_has_email_verified_at,
        explanation=(
            "The migration added an email_verified_at timestamp column to the users "
            "table. If this section is green, the column exists and the migration ran "
            "successfully on the preview database. This is the actual schema change "
            "this PR delivers."
        ),
    ),
]
```

**Rules for good sections:**
- One section per acceptance criterion, not per implementation detail
- `explanation` is for the reviewer, not for engineers. Use plain language.
  Describe what to look for and what it proves.
- Probes must be fast (< 2 seconds). Slow probes block the page load.
- Probes must be safe. No mutations (no INSERT/UPDATE/DELETE).
- Keep `app/evidence.py` minimal. It runs on every page load in preview.

---

## Worker agent workflow

After pushing a branch and the preview deploy succeeds:

1. `curl -s <preview-url>/healthz/evidence | jq .`
2. If `passed: true` → post PR description, move to In Review.
3. If `passed: false` → attempt **one repair** (fix the failing probe or its
   implementation, re-push). If still red after one attempt, post a PR comment
   with the failing sections and manual verification instructions, then hand off.
4. Never block PR creation on a red evidence page — the reviewer makes the call
   with full information.

---

## Production safety

The evidence router is only registered when the process sees `ENVIRONMENT=preview`
at startup. This is checked once at module import, not per-request. Production
Cloud Run services never set this variable, so the evidence routes are never
registered, and the production home page continues to render normally.

To verify: `curl https://<production-url>/healthz/evidence` should return 404.
