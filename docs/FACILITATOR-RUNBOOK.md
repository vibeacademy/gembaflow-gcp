# Workshop Facilitator Runbook

Operational procedures for facilitators running live Agile Flow workshops
on the GCP edition.

This repo ships **two** distinct framework-sync flows, and they are not
interchangeable:

| Flow | Script | Audience | Honors `.agile-flow-overrides`? | Upstream |
|------|--------|----------|---------------------------------|----------|
| `/pull-upstream` | `scripts/pull-upstream.sh` | Maintainer of `agile-flow-gcp` | **Yes** | `vibeacademy/agile-flow` |
| `/upgrade` | `scripts/template-sync.sh` | Participants in their own forks | **No** | `vibeacademy/agile-flow` (hard-coded) |

Sections 1–4 below cover the **maintainer flow** you use to keep
`agile-flow-gcp` itself in sync with `agile-flow`. Sections 5–7 cover the
**participant flow** that cohorts run in their own forks. The two flows
have important asymmetries — see §7 before recommending one path or the
other.

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

---

## 5. Participant Flow: `/upgrade` In a Cohort Fork

Each workshop participant forks `agile-flow-gcp` into their own GitHub
account. When they want their fork to pick up a newer framework release,
they run `/upgrade` in their fork. This is a different mechanism from
`/pull-upstream` and lives in a different script.

### What `/upgrade` does in a participant fork

`/upgrade` is a Claude Code wrapper around `scripts/template-sync.sh`. In
a participant's fork the script:

1. Reads the local version from `.agile-flow-version`.
2. Calls the public GitHub API for
   `vibeacademy/agile-flow/releases/latest` to find the latest release tag.
   The upstream repo is hard-coded inside `scripts/template-sync.sh`; see
   §7 for the implication.
3. If the local version matches the tag, exits with `Already up to date`.
4. Otherwise, downloads the release tarball and **copies** every file in
   each path listed in `syncDirectories` (in `.agile-flow-version`) into
   the participant's working tree, overwriting any local file that
   differs.
5. Bumps `version` in `.agile-flow-version`, creates a branch
   `agile-flow-sync/v{LATEST_VERSION}`, commits as `github-actions[bot]`,
   pushes, and runs `gh pr create` to open a sync PR against the
   participant's `main`.
6. Exits. The upgrade is **not** applied to the participant's `main` until
   they review and merge the sync PR.

There is no git merge, no three-way conflict resolution, and no interactive
prompt. The script takes no flags.

### Pre-flight checks the participant must pass

`/upgrade` refuses to run unless both are true:

- **Clean working tree.** `git status --porcelain` produces no output. If
  the participant has uncommitted work:

  ```bash
  git stash
  /upgrade
  # After the sync PR is merged:
  git stash pop
  ```

- **Authenticated `gh`.** `gh auth status` reports a logged-in account
  with push + PR permission on the participant's fork. If not:

  ```bash
  gh auth login
  ```

### Two ways the participant can trigger `/upgrade`

| Method | Where they run it |
|--------|-------------------|
| Claude Code slash command | `/upgrade` in a Claude Code session inside the participant's Codespace or local checkout |
| GitHub Actions | Their fork → **Actions → Template Sync → Run workflow → Run workflow** (runs `bash scripts/template-sync.sh` with the workflow-scoped `GITHUB_TOKEN`) |

Both paths produce the same sync PR. The Actions path is the fallback
when Claude Code is not available (no terminal access, rate-limited
Anthropic API, etc.).

### Reviewing the sync PR

The PR is titled `chore(sync): update Agile Flow framework to v{VERSION}`
on branch `agile-flow-sync/v{VERSION}`. The body lists every file that
was added or updated, plus a link to the upstream release notes. The
participant reviews the diff and squash-merges if it looks right; if not,
they close it (their fork's `main` is unaffected because the changes
only live on the sync branch).

---

## 6. The Two-Hop Model: How Updates Actually Reach Participants

Framework updates published as releases on `vibeacademy/agile-flow` reach
a workshop participant via **two independent hops**:

```
vibeacademy/agile-flow                (release published)
        │
        │  Hop 1 — maintainer-driven, optional
        │  scripts/pull-upstream.sh   (§§1–4 above)
        │  Honors .agile-flow-overrides
        ▼
vibeacademy/agile-flow-gcp            (GCP edition, this repo)
        │
        │  Participant forks the GCP edition at some point in time.
        │  After that, the two hops are independent.
        ▼
{participant}/agile-flow-gcp          (participant's fork)
        ▲
        │  Hop 2 — participant-driven
        │  scripts/template-sync.sh via /upgrade  (§5 above)
        │  Does NOT honor .agile-flow-overrides
        │  Pulls from vibeacademy/agile-flow, NOT from
        │  vibeacademy/agile-flow-gcp
        │
vibeacademy/agile-flow                (release tarball — same source!)
```

The key thing: **hop 2 bypasses the GCP edition entirely.** A participant
running `/upgrade` reaches back to `vibeacademy/agile-flow` directly,
because that is the upstream hard-coded into `scripts/template-sync.sh`.
Hop 2 does not transit through `vibeacademy/agile-flow-gcp`.

### What this means in practice

- When you (the maintainer) merge a GCP-specific customisation into
  `agile-flow-gcp` `main`, that customisation **does not** ship to
  participants via `/upgrade`. Participants pulling with `/upgrade` get
  the upstream `agile-flow` version of those files.
- To get a GCP-specific customisation onto a participant's fork through
  `/upgrade`, the customisation has to land in `vibeacademy/agile-flow`
  itself, then in a tagged release, then the participant runs `/upgrade`.
- `.agile-flow-overrides` does not protect the participant's fork from
  `/upgrade` either. That file is only consulted by `scripts/pull-upstream.sh`
  (hop 1).
- The "merge it in `agile-flow-gcp` and ask participants to pull" path
  works only if participants do a `git pull` from `origin` (their fork
  tracking `vibeacademy/agile-flow-gcp` via a remote you set up), not via
  `/upgrade`.

### Picking the right hop

| You want | Use |
|----------|-----|
| Get an upstream `agile-flow` fix into the GCP edition (this repo) | `/pull-upstream` (hop 1) |
| Get the GCP edition itself into a participant's fork | The participant `git pull`s from their fork's origin, or you re-fork |
| Get a fresh upstream `agile-flow` release into a participant's fork | The participant runs `/upgrade` (hop 2) |

---

## 7. Honest Caveats and Known Asymmetries

The two flows look symmetric — both bring "framework updates" — but they
behave differently. Surface these to your cohort proactively rather than
letting participants discover them on their own.

### `/upgrade` pulls from `agile-flow`, not `agile-flow-gcp`

`scripts/template-sync.sh` in this repo hard-codes
`UPSTREAM_REPO="vibeacademy/agile-flow"`. That means a participant in a
GCP-track fork running `/upgrade` pulls release tarballs from the
**non-GCP** upstream. Any GCP-specific files you maintain in
`agile-flow-gcp` (e.g. GCP-customised agents) are **not** delivered by
`/upgrade`.

This is the current behaviour. It may or may not be the intended
behaviour, but the docs must describe the world as it is. If your
workshop depends on participants having the GCP-customised agent
prompts, they need to either:

- Re-fork from `vibeacademy/agile-flow-gcp` after you push changes, or
- Pull from a remote that points at `vibeacademy/agile-flow-gcp` rather
  than relying on `/upgrade`.

### `/upgrade` does not honor `.agile-flow-overrides`

`.agile-flow-overrides` is read by `scripts/pull-upstream.sh` only. It is
**not** read by `scripts/template-sync.sh`. A participant running
`/upgrade` will receive every file inside `syncDirectories` exactly as it
appears in the upstream release, regardless of what is listed in
`.agile-flow-overrides`.

If a participant has hand-edited a file inside `syncDirectories`, the
sync PR diff will show the revert and they can choose not to merge.
There is no automatic protection.

### Releases vs. commits on `main`

`/upgrade` only sees what is in a **published GitHub release** on
`vibeacademy/agile-flow`. Commits that have landed on `agile-flow` `main`
but are not yet tagged in a release are invisible to `/upgrade`. If you
need participants to pick up a change immediately, confirm a release tag
exists that includes the change:

```bash
gh api repos/vibeacademy/agile-flow/releases/latest --jq .tag_name
```

`/pull-upstream`, in contrast, pulls from `upstream/main` directly and
sees every commit.

### Sync PR branches don't get cleaned up automatically

If a participant closes a sync PR without merging, the
`agile-flow-sync/v{VERSION}` branch remains on their fork's `origin`.
`template-sync.sh` checks the remote before re-creating the branch and
skips PR creation if it already exists. To recover:

```bash
git push origin --delete agile-flow-sync/v{VERSION}
/upgrade
```

### Common participant issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Working tree has uncommitted changes` | `/upgrade` pre-flight | `git stash; /upgrade; git stash pop` |
| `GitHub CLI is not authenticated` | `/upgrade` pre-flight | `gh auth login` as the fork owner |
| `Could not fetch latest release` | Hit GitHub's 60/hr unauthenticated API limit (shared Codespace IP) | Wait, or use Actions → Template Sync |
| `Branch agile-flow-sync/v{VERSION} already exists on remote` | Prior sync PR was closed without merging | `git push origin --delete agile-flow-sync/v{VERSION}` then re-run |
| Sync PR shows my GCP customisation being reverted | `/upgrade` always pulls upstream `agile-flow` (no override list) | Close the PR; move the customisation outside `syncDirectories` |

---

## Reference

| Path | Role |
|------|------|
| `.agile-flow-version` | Local version + `syncDirectories` whitelist (consumed by both scripts). |
| `.agile-flow-overrides` | Protected paths for `scripts/pull-upstream.sh` only (hop 1). Not read by `scripts/template-sync.sh`. |
| `scripts/pull-upstream.sh` | Maintainer-facing GCP-only script. Hop 1. |
| `scripts/template-sync.sh` | Participant-facing release-tarball sync. Hop 2. Hard-codes `vibeacademy/agile-flow` as upstream. |
| `.claude/commands/pull-upstream.md` | The `/pull-upstream` Claude Code wrapper. |
| `.claude/commands/upgrade.md` | The `/upgrade` Claude Code wrapper. |
| `.github/workflows/pull-upstream.yml` | The `workflow_dispatch` path for hop 1. |
| `.github/workflows/template-sync.yml` | The `workflow_dispatch` path for hop 2. |
| `docs/UPGRADING.md` | Reference for the release-tarball mechanism. |
