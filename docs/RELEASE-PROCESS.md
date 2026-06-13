# Release Process — `agile-flow-gcp`

Maintainer-facing guide for cutting GitHub Releases on
[`vibeacademy/gembaflow-gcp`](https://github.com/vibeacademy/gembaflow-gcp).

> **Audience:** the named release owner and anyone covering for them.
> Workshop participants do not run this process — they consume releases
> through `/upgrade` (see `docs/UPGRADING.md`).

## Owner

The **DevOps Engineer (GCP)** owns the release process for this repo.
That role is responsible for:

- Deciding when a release is warranted
- Following this document end-to-end
- Verifying the published release before announcing it
- Keeping this document current when the process changes

If the owner is unavailable, a second maintainer may cut a release —
but should still follow this document and add a note in the PR/release
description naming the substitute.

## Relationship to `agile-flow` (founder track)

`agile-flow-gcp` has its **own** upstream and its **own** release
cadence. It is **not** a strict mirror of `vibeacademy/agile-flow`.

| Concern | `agile-flow` (founder track) | `agile-flow-gcp` (this repo) |
|---------|------------------------------|------------------------------|
| Source of truth for releases | `vibeacademy/agile-flow` | `vibeacademy/gembaflow-gcp` |
| Stack | Next.js / TypeScript / Render / Supabase | FastAPI / Python / Cloud Run / Neon |
| Consumed by | Non-GCP workshop forks | GCP-track workshop forks |
| `template-sync.sh` `UPSTREAM_REPO` | `vibeacademy/agile-flow` | `vibeacademy/gembaflow-gcp` |

This separation is the operational outcome of [ADR-001](../UPSTREAM.md):
the GCP track has diverged enough from the founder track that a strict
mirror would either re-introduce platform churn (Render configs,
TypeScript build files) or block GCP-specific fixes behind the founder
release cycle. Keeping two upstreams costs us a small documented
cadence; the alternative cost more.

### When the GCP track must follow the founder track

A founder-track release is a **trigger to evaluate**, not an
auto-follow. After every founder-track release, the GCP owner reviews
the changes and decides which apply. Use `UPSTREAM.md`'s sync
procedure to cherry-pick framework-level fixes (agent prompts,
language-agnostic commands, lint rules, audit workflows) into
`agile-flow-gcp`'s `main`. Once those land, cut a GCP release that
incorporates them.

### When the GCP track should NOT follow the founder track

- Founder-track release only touches Render / Supabase / Next.js
  specifics — skip; the GCP track does not need a release.
- Founder-track release touches files listed in `UPSTREAM.md` under
  "Changed Files vs Upstream" — skip or hand-merge; do not blindly
  cherry-pick.
- Founder-track release reverts something the GCP track depends on
  — skip and note the divergence in `UPSTREAM.md`.

## Cadence Policy

Two triggers, neither on a fixed calendar:

1. **GCP-specific fixes — on demand.** Bug fixes, agent prompt
   corrections, workflow fixes, or new scripts targeting GCP/FastAPI
   land a release whenever the owner judges they should reach
   downstream workshop forks. There is no minimum batching window.
   Critical fixes (security, broken `/upgrade`, broken provisioning)
   should be released the same business day.
2. **After a founder-track release — within 10 business days.**
   When `vibeacademy/agile-flow` publishes a new release, the GCP
   owner has 10 business days to evaluate it, cherry-pick the
   applicable changes per `UPSTREAM.md`, and either cut a GCP
   release or record in `UPSTREAM.md` why no GCP release is
   warranted.

> **Why 10 business days, not "next day":** the owner has to read the
> founder-track diff, decide which commits apply, run the local
> smoke test (`uv sync --extra dev && uv run pytest && docker
> build`), and validate that the GCP-specific workflows still
> pass CI. A daily cadence would either degrade that validation
> step or burn out a single maintainer. A small lag is
> acceptable because the founder-track release does not block
> the GCP track — GCP workshop forks pull from `agile-flow-gcp`,
> not the founder track.

If a founder-track release is irrelevant to the GCP track, the owner
records this in the next routine `UPSTREAM.md` update (no separate
issue required) rather than forcing a no-op release.

## Versioning

This repo follows the policy in [`VERSIONING.md`](../VERSIONING.md)
(Semantic Versioning 2.0.0). The GCP track has its own version line
and does **not** need to match the founder track's version number.

- **Patch** — GCP-specific bug fixes, prompt corrections, doc-only
  changes that downstream forks should pick up
- **Minor** — new agent definitions, new slash commands, new
  scripts, additive workflow changes
- **Major** — breaking changes to `syncDirectories`, removal of an
  agent, restructured directories, bootstrap flow changes

## Pre-Publish Checklist

Run every item before pushing the tag. If any step fails, stop and
fix it on a regular PR before continuing.

- [ ] **Working tree clean** on `main` and `git pull` is current:
      `git status` shows nothing pending, `git log origin/main..HEAD`
      is empty.
- [ ] **CHANGELOG entry exists** for the new version under a
      `## [X.Y.Z] - YYYY-MM-DD` heading. The `[Unreleased]` section
      has been promoted (or the entries copied) into the new version
      heading. The bottom-of-file compare links have been updated.
- [ ] **`.gembaflow-version` `version` field matches** the tag you
      are about to cut (without the leading `v`). Bump and commit if
      not.
- [ ] **`scripts/template-sync.sh` `UPSTREAM_REPO` is
      `vibeacademy/gembaflow-gcp`** — not the founder track. This
      is the most common drift point because the GCP repo was forked
      from a founder-track tree that pointed at itself. Confirm with:
      ```bash
      grep '^UPSTREAM_REPO=' scripts/template-sync.sh
      # expected: UPSTREAM_REPO="vibeacademy/gembaflow-gcp"
      ```
- [ ] **CI is green on `main`** at the commit you are about to tag.
- [ ] **Key framework files differ from the prior release as
      expected.** Spot-check the diff against the previous tag for
      anything in `syncDirectories` (`.claude/agents/`,
      `.claude/commands/`, `.claude/hooks/`, `.claude/skills/`,
      `scripts/`, `starters/`):
      ```bash
      prev=$(gh release view --json tagName -q .tagName 2>/dev/null || echo "")
      if [ -n "$prev" ]; then
        git diff "$prev"..HEAD -- .claude/agents .claude/commands \
          .claude/hooks .claude/skills scripts starters
      else
        echo "No prior release — skip diff (this is the first release)."
      fi
      ```
      A release with no diff in `syncDirectories` is suspect —
      downstream `/upgrade` will see "nothing to update" and the
      release was wasted. Either include framework changes or
      cancel the release. (Skip this check for the very first
      release; there is nothing to compare against.)
- [ ] **Local smoke test passes:**
      ```bash
      uv sync --extra dev
      uv run ruff check .
      uv run mypy app/
      uv run pytest
      docker build -t agile-flow-gcp-test .
      ```
- [ ] **Tarball spot-check.** Build the same tarball the release
      will publish and confirm `syncDirectories` are present and
      non-empty:
      ```bash
      git archive --format=tar.gz --prefix=agile-flow-gcp/ HEAD \
        -o /tmp/release-preview.tar.gz
      tar -tzf /tmp/release-preview.tar.gz \
        | grep -E '^agile-flow-gcp/(\.claude/|scripts/|starters/)' \
        | head
      ```
      (GitHub's auto-generated tarball is the source of truth for
      `/upgrade`; this is a quick sanity check on equivalent content.)

## Cutting the Release

Once the checklist passes, cut the release with these exact steps.
The `release.yml` workflow picks it up on tag push.

1. Confirm you are on `main` with a clean tree and CI green:
   ```bash
   git checkout main
   git pull
   git status
   gh run list --branch main --limit 1
   ```
2. Create an annotated tag for the new version:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```
   Use the Semantic Versioning rules in `VERSIONING.md` to choose
   the bump.
3. Push the tag:
   ```bash
   git push origin vX.Y.Z
   ```
4. Watch the release workflow finish:
   ```bash
   gh run watch
   ```
   The workflow extracts the matching `CHANGELOG.md` section and
   publishes a GitHub Release at
   `https://github.com/vibeacademy/gembaflow-gcp/releases/tag/vX.Y.Z`.
   Source: [`.github/workflows/release.yml`](../.github/workflows/release.yml).

If the workflow fails:

- **Missing CHANGELOG section** — the workflow falls back to
  "Release vX.Y.Z" as the body. That is a sign you forgot the
  CHANGELOG; delete the GitHub Release (not the tag) with
  `gh release delete vX.Y.Z`, add the CHANGELOG entry on `main`,
  then re-run the workflow against the same tag via
  `gh workflow run release.yml --ref vX.Y.Z`.
- **Permission error** — the workflow needs `contents: write`,
  which is already set; failures here usually mean the repo's
  default `GITHUB_TOKEN` permission was tightened. Escalate to the
  org owner before retrying.

## Post-Publish Verification

After the workflow completes:

1. **Release is visible:**
   ```bash
   gh release view vX.Y.Z --repo vibeacademy/gembaflow-gcp
   ```
2. **`releases/latest` resolves to the new tag** — this is the
   endpoint `template-sync.sh` and `/upgrade` consume:
   ```bash
   curl -sf https://api.github.com/repos/vibeacademy/gembaflow-gcp/releases/latest \
     | grep '"tag_name"'
   ```
3. **End-to-end `/upgrade` smoke test** — in a throwaway clone of
   a downstream workshop fork, run `/upgrade` (or
   `bash scripts/template-sync.sh`) and confirm it picks up the
   new version cleanly.

## Rolling Back a Bad Release

If a release reaches downstream forks with a serious regression:

1. **Cut a patch release immediately** with the fix. Downstream
   forks discover updates by polling `releases/latest`, so a
   forward fix is faster than trying to retract.
2. If a forward fix is impossible (e.g., the release is so broken
   that `/upgrade` itself fails), retract the GitHub Release while
   leaving the tag in place:
   ```bash
   gh release delete vX.Y.Z --repo vibeacademy/gembaflow-gcp
   ```
   This removes the release from `releases/latest` and causes
   downstream `/upgrade` to fall back to the previous release. Open
   a follow-up issue to root-cause the regression.
3. **Do not delete the tag** unless you are certain no downstream
   fork has consumed it. Tag deletion breaks future `git diff
   vX.Y.Z..HEAD` checks and confuses anyone who has the tag
   cached locally.

## Related Documents

- [`VERSIONING.md`](../VERSIONING.md) — version-number policy
- [`UPSTREAM.md`](../UPSTREAM.md) — how to cherry-pick from the
  founder track before cutting a GCP release
- [`docs/UPGRADING.md`](./UPGRADING.md) — the downstream consumer
  side; how participants pick up a release
- [`docs/MAINTENANCE.md`](./MAINTENANCE.md) — weekly audit cadence
  the release owner should also be aware of
- [`docs/DISTRIBUTION.md`](./DISTRIBUTION.md) — framework vs.
  user-content boundary; informs what `syncDirectories` should and
  should not include
- [`.github/workflows/release.yml`](../.github/workflows/release.yml)
  — the workflow that publishes the release when a tag is pushed
