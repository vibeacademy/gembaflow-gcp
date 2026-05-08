# Workshop Facilitator Runbook

Operational procedures for facilitators running live Agile Flow workshops
on the GCP edition.

---

## Applying Upstream Framework Updates Mid-Workshop

If the upstream `vibeacademy/agile-flow` repo ships a fix or improvement
during an active workshop, you can pull it into the GCP fork immediately
without manual git surgery.

### Prerequisites

- You are running from a participant's Codespace (or your own).
- The Codespace has network access to GitHub (default: yes).
- The working tree has no uncommitted changes.

### Option A — Claude Code slash command (recommended)

Open Claude Code in the Codespace and run:

```
/pull-upstream
```

Claude will run `scripts/pull-upstream.sh`, report what changed, and push
the update to `origin`. Participants then pull:

```bash
git pull
```

### Option B — Shell script directly

```bash
bash scripts/pull-upstream.sh
git push origin HEAD
```

The script:

1. Adds `vibeacademy/agile-flow` as the `upstream` remote (idempotent).
2. Fetches `upstream/main`.
3. For every file in `syncDirectories` (`.agile-flow-version`) that exists
   in upstream, compares blob hashes.
4. Applies the upstream version for any file that differs.
5. Skips files listed in `.agile-flow-overrides` (intentional GCP overrides).
6. Commits the result.

### Option C — GitHub Actions (no Codespace required)

Trigger the workflow from the GitHub UI:

1. Go to **Actions → Pull Upstream → Run workflow**.
2. Choose `push_changes`:
   - `false` (default) — opens a PR for review before merging.
   - `true` — pushes directly to `main`.
3. Participants pull after the workflow completes:
   ```bash
   git pull
   ```

---

## What Gets Updated

Only files that are:
- Listed in `syncDirectories` in `.agile-flow-version`, AND
- Present in the upstream repo, AND
- **Not** listed in `.agile-flow-overrides`

are ever modified. Application code (`app/`, `alembic/`, `templates/`,
`static/`), infrastructure files (`Dockerfile`, `.github/workflows/deploy.yml`),
and GCP-specific scripts are never touched.

### GCP-override files (never overwritten)

| File | Reason |
|------|--------|
| `.claude/agents/github-ticket-worker.md` | FastAPI / SQLModel / Neon guardrails |
| `.claude/agents/devops-engineer.md` | GCP-only operations |
| `.claude/agents/system-architect.md` | GCP platform ecosystems |
| `.claude/commands/doctor.md` | GCP / Neon secret checks |
| `.claude/commands/bootstrap-architecture.md` | Hardcoded to Cloud Run |

---

## Conflict Handling

The script prefers **upstream** for all tracked files. There are no 3-way
merges — it takes the upstream blob directly. Files in `.agile-flow-overrides`
are protected and never touched, so true conflicts are prevented by design.

If a conflict cannot be resolved automatically (e.g. a tracked file was
hand-edited locally), the script will abort with a clear error. Fix:

```bash
git diff HEAD <file>          # See what changed locally
git checkout HEAD -- <file>   # Discard local change
bash scripts/pull-upstream.sh # Re-run
```

---

## Troubleshooting

### "Working tree has uncommitted changes"

```bash
git stash
bash scripts/pull-upstream.sh
git push origin HEAD
git stash pop   # restore local work if needed
```

### "Could not fetch from upstream"

Check network connectivity from the Codespace:

```bash
curl -sf https://api.github.com/repos/vibeacademy/agile-flow/commits/main | jq .sha
```

If the API is unreachable, use the GitHub Actions option (runs from GitHub's
network) or wait for connectivity to be restored.

### "Nothing changed but I expected updates"

Verify the upstream has newer commits than the files you're tracking:

```bash
git remote get-url upstream 2>/dev/null || echo "No upstream remote yet"
git fetch upstream main
git log --oneline upstream/main -- .claude/commands/ | head -5
```
