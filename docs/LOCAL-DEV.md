# Local Development

This template runs against three different database contexts: **production**, **CI preview**, and **local Codespace**. Each derives `DATABASE_URL` differently. Knowing which context is which — and where to put which credential — prevents the most common day-1 footgun: pointing local development at the production database by accident.

If you're a workshop attendee and your facilitator already configured Codespaces org secrets per the workshop runbook, you can skip to **Recipe: bringing up local dev** below — your environment is already set up.

---

## The three contexts

| Context | Where `DATABASE_URL` comes from | Where the credential lives | When it's evaluated |
|---|---|---|---|
| **Production** (Cloud Run) | The `PRODUCTION_DATABASE_URL` Actions secret is passed as a plain env var to Cloud Run at deploy time (`--set-env-vars DATABASE_URL=...`). The Cloud Run revision reads `DATABASE_URL` from its env. | GitHub repo **Actions** secret named `PRODUCTION_DATABASE_URL`. Set automatically by `scripts/provision-gcp-project.sh` Step 7. | Set once per deploy. The deploy workflow at `.github/workflows/deploy.yml:93,162` pulls the secret value and forwards it. |
| **CI preview** (per-PR Cloud Run revision) | `neondatabase/create-branch-action@v5` mints an ephemeral Neon branch off `main` per PR. The branch's pooled URL becomes `DATABASE_URL` on the preview Cloud Run revision. | GitHub repo **Actions** secrets `NEON_API_KEY` + `NEON_PROJECT_ID`. Set automatically during `provision-gcp-project.sh` Step 7 (alongside `PRODUCTION_DATABASE_URL`). | Computed per-PR by `.github/workflows/preview-deploy.yml`. Branch is auto-suspended on inactivity and torn down when the PR closes. |
| **Local Codespace** | You run a Neon dev-branch helper (`scripts/dev-branch.sh` — see [#159](https://github.com/vibeacademy/gembaflow-gcp/issues/159)) which creates an ephemeral branch off `main` and writes its pooled URL into `.env`. Your dev server reads `DATABASE_URL` from `.env` via `app/config.py`. | **Codespaces** secrets `NEON_API_KEY` + `NEON_PROJECT_ID`. Distinct scope from Actions secrets — each store has its own UI and visibility model. | Per-session. Mint a dev branch when you start working, tear it down when you're done (or on a schedule via Neon's auto-suspend). |

GitHub has two completely independent secret stores:

- **Actions secrets** — visible to GitHub Actions workflow runs only. Cannot be read from a Codespace's terminal.
- **Codespaces secrets** — injected as env vars into running Codespaces. Cannot be read from a workflow run.

A secret with the same name in both stores is two different values; setting one does not populate the other.

---

## Critical: never set `PRODUCTION_DATABASE_URL` as a Codespaces secret

> ⚠️ **Footgun.** `PRODUCTION_DATABASE_URL` belongs in **Actions secrets only**. If you set it as a Codespaces secret, your local dev session will run migrations and writes against the production database. There is no rollback for that.

The natural assumption — "I have it as an Actions secret, why not also as a Codespaces secret?" — leads here. Don't. The recipe below uses `NEON_API_KEY` + `NEON_PROJECT_ID` to mint an ephemeral dev branch; that's the only Neon credential pair the Codespace needs.

If you accidentally created the Codespaces secret, delete it at `https://github.com/settings/codespaces` (or the org-secret equivalent) before opening any new Codespace.

---

## Recipe: bringing up local dev

### Prerequisites

You need two Codespaces secrets visible from inside the Codespace:

- `NEON_API_KEY` — your Neon API key
- `NEON_PROJECT_ID` — the Neon project ID this fork uses (the parent project, the same one CI preview branches from)

**For workshop attendees:** these are typically configured as Codespaces **org secrets** by the facilitator, scoped to your repo. Check `https://github.com/settings/codespaces` — if the secrets appear under "Organization secrets" with `vibeacademy` as the source, you're set. If not, ask your facilitator.

**For solo evaluators on personal forks:** add both as Codespaces **user secrets** at `https://github.com/settings/codespaces` and scope each to your fork. Restart the Codespace to pick them up.

### Mint a dev branch

> **Note:** The script referenced below ships in [#159](https://github.com/vibeacademy/gembaflow-gcp/issues/159) (sibling to this doc within the local-dev epic [#157](https://github.com/vibeacademy/gembaflow-gcp/issues/157)). Until #159 lands, the same flow works manually using `neonctl` directly — see "Manual fallback" at the bottom of this doc.

```bash
bash scripts/dev-branch.sh
# Creates a branch `dev-${USER}-${epoch}` off main
# Writes .env with DATABASE_URL=<pooled URL for the new branch>
# Runs `uv run alembic upgrade head` so the branch matches current schema
# Prints the teardown command
```

After this runs once, your dev server picks up `DATABASE_URL` from `.env` automatically:

```bash
uv run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

### Tear down when done

```bash
bash scripts/dev-branch.sh --teardown
# Deletes the dev branch from Neon (frees your auto-suspend quota)
# Removes .env (or restores .env.bak if one was created)
```

Closing a Codespace permanently without running teardown is a soft leak — Neon auto-suspends inactive branches but they accumulate in the project. Worth tearing down when you're done with a feature.

### Why not SQLite?

The test fixture (`tests/conftest.py`) uses SQLite `:memory:` for unit-test speed and isolation. **Do not generalize that to local dev.** SQLite hides Postgres-specific bugs:

- Type mismatches (e.g., the `sqlmodel.sql.sqltypes.GUID` incident — SQLite accepted it, Neon's CI run rejected it)
- JSON column dialect differences
- Migration files that fail on Postgres but pass on SQLite when tests bypass Alembic via `SQLModel.metadata.create_all()`

Running local dev against the same Neon flavor production uses catches these in seconds instead of after a CI deploy round-trip.

---

## Manual fallback (until `dev-branch.sh` lands)

If [#159](https://github.com/vibeacademy/gembaflow-gcp/issues/159) hasn't shipped yet, the same flow works with `neonctl`:

```bash
# Install neonctl if not already
npm install -g neonctl

# Authenticate (uses NEON_API_KEY from env)
neonctl auth

# Create the dev branch
BRANCH_NAME="dev-${USER}-$(date +%s)"
neonctl branches create --name "$BRANCH_NAME" --project-id "$NEON_PROJECT_ID"

# Get the pooled connection URL
DB_URL=$(neonctl connection-string "$BRANCH_NAME" --project-id "$NEON_PROJECT_ID" --pooled)
echo "DATABASE_URL=$DB_URL" >> .env

# Migrate
uv run alembic upgrade head

# Teardown later
neonctl branches delete "$BRANCH_NAME" --project-id "$NEON_PROJECT_ID"
rm .env
```

`scripts/dev-branch.sh` automates exactly this sequence with idempotency, error handling, and a `--teardown` flag. Track [#159](https://github.com/vibeacademy/gembaflow-gcp/issues/159) for the helper.

---

## Related

- `docs/PLATFORM-GUIDE.md` — production + CI-preview architecture in depth
- `docs/GETTING-STARTED.md` — first-time setup walkthrough (Codespace + GitHub PAT + Anthropic key)
- `docs/PATTERN-LIBRARY.md` — Neon-specific gotchas (cold-wake, region match, per-PR branching)
- [#159](https://github.com/vibeacademy/gembaflow-gcp/issues/159) — `scripts/dev-branch.sh` (sibling ticket)
- [#160](https://github.com/vibeacademy/gembaflow-gcp/issues/160) — Codespaces org-secrets runbook (the operational complement)
- [#157](https://github.com/vibeacademy/gembaflow-gcp/issues/157) — parent epic
