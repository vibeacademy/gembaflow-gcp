# Software Development Lifecycle

How Agile Flow is built, tested, released, and maintained — covering both
the base framework and its cloud-specific variants.

---

## System Map

```
vibeacademy/agile-flow          ← Base framework (Next.js + Render)
       │
       ├─ pull-upstream / upgrade
       │
       ▼
vibeacademy/agile-flow-gcp      ← GCP variant (FastAPI + Cloud Run + Neon)
vibeacademy/agile-flow-aws      ← AWS variant (same pattern, different platform)
```

The base repo is the source of truth for agent definitions, framework
documentation, CI structure, validation scripts, and slash commands. Cloud
variants fork the base and add platform-specific deployment, database, and
provisioning layers.

---

## 1. How Changes in Base Propagate to Cloud Variants

### Two sync strategies

**Safe incremental sync (`pull-upstream.sh` / `pull-upstream` workflow)**

Use this for routine framework updates — new agent definitions, updated
docs, improved validation scripts.

```bash
# Run locally (requires clean working tree)
scripts/pull-upstream.sh

# Or trigger via GitHub Actions (manual dispatch)
# .github/workflows/pull-upstream.yml
# Input: push_changes=true (direct to main) or false (opens a PR)
```

What it does:

- Fetches the upstream `agile-flow` repo
- Compares each file in `syncDirectories` against the upstream blob hash
- Copies changed files, skipping anything in `.agile-flow-overrides`
- Commits as `chore(upstream): sync framework files from agile-flow@{sha}`

**Full upgrade (`upgrade.sh` / `upgrade` workflow)**

Use this for major framework versions that require a three-way merge.

```bash
scripts/upgrade.sh --interactive         # Manual conflict resolution
scripts/upgrade.sh --accept-upstream     # Auto-take upstream (use with care)
scripts/upgrade.sh --abort-on-conflict   # Rollback if conflicts detected
scripts/upgrade.sh --continue            # Resume after manual resolution
```

What it does:

- Tags the current state as `pre-upgrade-{timestamp}` (rollback point)
- Attempts a three-way merge with upstream `main`
- Auto-applies `.agile-flow-overrides` to resolve conflicts in protected paths
- Records the upstream SHA in `.agile-flow-meta/version`

### What is and isn't synced

**`syncDirectories`** (defined in `.agile-flow-version`):

```
.claude/agents
.claude/commands
.claude/hooks
.claude/skills
scripts
starters
```

**`.agile-flow-overrides`** (files protected from upstream sync):

The overrides file lists paths that the cloud variant owns. Examples:

```
.agile-flow-meta/           # Local metadata, never synced
.claude/agents/github-ticket-worker.md   # GCP guardrails
.claude/agents/devops-engineer.md        # GCP guardrails
scripts/provision-gcp-project.sh         # GCP-specific
scripts/create-workshop-neon-projects.sh # GCP-specific
```

**Design principle:** If a file needs to diverge from the base, add it to
`.agile-flow-overrides`. If a diverged file no longer needs to differ,
remove it from `.agile-flow-overrides` and let the sync overwrite it.

### When to sync vs. upgrade

| Scenario | Use |
|----------|-----|
| New agent definition in base | `pull-upstream.sh` |
| Framework doc update | `pull-upstream.sh` |
| New slash command | `pull-upstream.sh` |
| Major base version bump | `upgrade.sh` |
| Breaking directory restructure | `upgrade.sh --interactive` |
| Emergency rollback needed | `git checkout pre-upgrade-{timestamp}` |

---

## 2. Conventional Commits and Releases

### Conventional commit format

All commits — human and agent — follow this structure:

```
<type>(<scope>): <subject>
```

Common types:

| Type | Use when |
|------|----------|
| `feat` | New capability added |
| `fix` | Bug corrected |
| `docs` | Documentation only |
| `refactor` | Code restructured, no behavior change |
| `test` | Tests added or modified |
| `ci` | Workflow or CI config changed |
| `chore` | Maintenance, dependency bumps |
| `build` | Build system changes |

Agent commit skills (`.claude/skills/commit.md`) enforce this automatically.
CLAUDE.md Rule 3 makes it mandatory for manual commits too.

### Changelogs

`CHANGELOG.md` is maintained manually in [Keep a Changelog](https://keepachangelog.com)
format. Every PR that adds user-visible behavior should update the
`[Unreleased]` section.

```markdown
## [Unreleased]

### Added
- New `/pull-upstream` slash command for framework sync

## [0.9.0] - 2025-12-07
### Added
- Core agent definitions
```

**Important:** This project does not use the `semantic-release` tool.
Versions are bumped manually by a maintainer; the structure of conventional
commits is used for clarity and tooling compatibility, not for automated
version calculation.

### Release process

1. Changes land on `main` via pull request.
2. Maintainer updates `CHANGELOG.md` and bumps the version in
   `pyproject.toml` (GCP) or `package.json` (base).
3. Maintainer creates an annotated tag: `git tag -a vX.Y.Z -m "release vX.Y.Z"`.
4. Pushing the tag triggers `.github/workflows/release.yml`, which:
   - Extracts the CHANGELOG section for that version
   - Creates a GitHub Release with that section as the body

### Versioning rules

| Increment | When |
|-----------|------|
| Patch | Bug fixes, doc corrections, non-functional changes |
| Minor | New agents, commands, workflows, scripts (backward-compatible) |
| Major | Renamed/removed agents, restructured directories, changed bootstrap flow |

See `VERSIONING.md` for the full compatibility promise.

---

## 3. Testing the Workshop Flow

Workshop provisioning is tested through a combination of automated script
tests and manual facilitation walkthroughs.

### Automated provisioning tests

Key scripts have companion `.test.sh` files that verify provisioning logic:

```
scripts/provision-workshop-roster.sh
scripts/provision-workshop-roster.test.sh   ← bats-style shell tests

scripts/provision-gcp-project.sh
scripts/provision-gcp-project.test.sh
```

These run in CI alongside other shell validations.

### Manual workshop dry-run

Before each workshop delivery, the facilitator should run through
`docs/FACILITATOR-RUNBOOK.md`, which covers:

- Pre-event: roster CSV preparation, GCP project provisioning, Neon project
  creation, GitHub repo setup, secret injection
- During: attendee onboarding, environment verification with `scripts/doctor.sh`
- Post-event: teardown with `scripts/workshop-teardown.sh`

### Workshop smoke test checklist

1. Run `scripts/doctor.sh` on a freshly provisioned attendee repo — all
   checks should pass.
2. Confirm Cloud Run preview deploys on a test PR (`preview-deploy.yml`).
3. Verify Neon branch is created and migrations run successfully.
4. Confirm teardown removes Neon branches and Cloud Run revision tags.

**Gap:** End-to-end workshop flow testing is currently manual. An automated
smoke test suite that exercises the full provisioning → deploy → teardown
cycle against a real GCP project is a known gap.

---

## 4. Testing the Framework

### Application tests (GCP variant)

| Layer | Tool | Command | CI gate |
|-------|------|---------|---------|
| Unit + integration | pytest | `uv run pytest` | Required |
| Coverage | pytest-cov | `uv run pytest --cov=app --cov-fail-under=80` | 80% minimum |
| Type checking | mypy | `uv run mypy app/` | Informational (non-blocking) |
| Linting | ruff | `uv run ruff check .` | Required |

### Application tests (base template)

| Layer | Tool | Command | CI gate |
|-------|------|---------|---------|
| Unit | Vitest | `npm test` | Required |
| Linting | ESLint | `npm run lint` | Required |
| Type checking | tsc | `npm run typecheck` | Required |

### Agent and policy tests

| Check | Tool | CI job |
|-------|------|--------|
| Agent policy constraints | `scripts/lint-agent-policies.sh` | `lint-agent-policies` |
| Protocol block validation | `scripts/verify-agent-restrictions.sh --test protocol` | `lint-agent-policies` |
| Docs consistency | `scripts/verify-agent-restrictions.sh --test docs` | `lint-agent-policies` |
| Agent restriction tests | `docs/testing/agent-restriction-tests.md` | manual |

### Infrastructure checks

| Check | Tool | CI job |
|-------|------|--------|
| Markdown | markdownlint-cli2 | `lint` |
| Shell scripts | shellcheck | `build` |
| JSON files | custom validator | `typecheck` |
| GitHub Actions YAML | actionlint | `actionlint` (GCP only) |

### Pre-push gate

```bash
# Install hooks once
git config core.hooksPath scripts/hooks

# The pre-push hook auto-detects stack and runs:
# - Python stack: ruff check + mypy + pytest
# - Node stack: eslint + tsc + vitest
```

This runs the full local test suite before any push reaches GitHub, making
CI failures rare.

---

## 5. Keeping Up with Platform Updates

### GCP services

The GCP variant pins action versions and service configurations explicitly.
When GCP releases new Cloud Run features or Neon releases new branching APIs:

1. File a ticket with the change and its impact.
2. Update the relevant workflow (`deploy.yml`, `preview-deploy.yml`) or
   provisioning script.
3. Test in a dev environment before merging.

### GitHub Actions

`actionlint` catches deprecated or invalid action syntax on every CI run.
When GitHub deprecates an action, CI fails fast and the fix is targeted.

### Framework dependencies

**Python (GCP):** `uv` manages dependencies in `pyproject.toml`. Run
`uv sync` to install; bump versions in `pyproject.toml` directly.

**Node (base):** `npm` manages dependencies. Run `npm install`.

Dependency bumps follow the `chore(deps): bump X from Y to Z` commit
convention.

### Upstream framework

See [Section 1](#1-how-changes-in-base-propagate-to-cloud-variants).
The sync cadence should be at minimum monthly, and within one week of any
major base release.

---

## 6. How User Feedback Becomes Prioritized Work

```
Feedback source                  Who handles it
──────────────────────────────────────────────────────────────────
Workshop attendee observation    Facilitator captures → filed as GitHub issue
Board/stakeholder input          Product Manager evaluates → PRD update or ticket
Agent-detected bug               Agent files issue via report-issue.sh
Pull request review comment      PR Reviewer flags → ticket if scope exceeds PR

           ↓

Product Manager
 • Evaluates strategic fit against PRD and roadmap
 • Makes go/no-go decision on new capabilities
 • Updates PRODUCT-ROADMAP.md for accepted work

           ↓

Product Owner (backlog groomer)
 • Writes tickets in Agentic PRD Lite format (see docs/TICKET-FORMAT.md)
 • Sets effort estimate (S/M/L/XL) and priority label
 • Checks Definition of Ready before moving to the sprint backlog
 • Runs /groom-backlog slash command to batch-prepare tickets

           ↓

Sprint backlog → Ticket Worker
```

**Definition of Ready (DoR)** — a ticket must have:

- Clear title and description with context
- Testable acceptance criteria
- Effort estimate (S/M/L/XL)
- Priority label
- No open blockers

Tickets that don't meet DoR stay in the backlog until groomed.

---

## 7. Quality Standards

### Code

| Standard | Enforced by | Threshold |
|----------|-------------|-----------|
| Test coverage | pytest-cov / Vitest | 80% minimum |
| No lint errors | ruff / ESLint | Zero tolerance |
| Type safety | mypy / tsc | mypy informational; tsc blocks |
| Shell safety | shellcheck | CI required |
| Actions safety | actionlint | CI required (GCP) |
| Markdown | markdownlint-cli2 | CI required |

### Pull requests

- All CI checks must pass before merge.
- At least one approving review required (branch protection enforced).
- Agents create and review PRs; only humans merge.
- Preview environment must deploy successfully before merge consideration.

### Definition of Done (DoD) — a ticket is complete when:

- All acceptance criteria are met
- Tests written and passing
- Code reviewed and approved
- No lint errors
- Preview environment verified
- PR merged to `main`
- CHANGELOG.md updated if user-visible

### Documentation standards

- Every user-visible change updates the relevant `docs/` file.
- Agent instruction changes must pass `lint-agent-policies` and
  `verify-agent-restrictions`.
- One canonical location per fact — no duplication between docs.

---

## 8. How Product Artifacts Get Generated and Progressed

### Bootstrap artifacts (one-time)

These are generated during project initialization via `/research`, `/jtbd`,
`/positioning`, and the `bootstrap-agents` skill:

| Artifact | Owner | Location |
|----------|-------|---------|
| `MARKET-RESEARCH.md` | Product Manager | project root or `docs/` |
| `JOBS-TO-BE-DONE.md` | Product Manager | project root or `docs/` |
| `POSITIONING-ANALYSIS.md` | Product Manager | project root or `docs/` |
| `PRODUCT-REQUIREMENTS.md` | Product Manager | `docs/` |
| `PRODUCT-ROADMAP.md` | Product Manager | `docs/` |
| `TECHNICAL-ARCHITECTURE.md` | System Architect | `docs/` |
| Agent definitions | Bootstrap Agents | `.claude/agents/*.md` |

### Ongoing development cycle

```
Stage 1: Grooming
  Product Owner writes ticket → GitHub Issue (Agentic PRD Lite format)

Stage 2: Implementation
  Ticket Worker checks out branch → writes code + tests → opens PR

Stage 3: Review
  PR Reviewer reads PR + ticket → GO / NO-GO comment

Stage 4: Human decision
  Human reads review → checks preview URL → merges or requests changes

Stage 5: Deployment
  Push to main → CI → deploy.yml → Cloud Run production deploy
                                    (with Alembic migration before deploy)
```

### Preview environments

Every PR automatically gets:

- A Neon database branch (`pr-N`) with migrations applied
- A Cloud Run revision tag (`pr-N`) with zero production traffic
- A bot comment with the preview URL and smoke test result

Preview resources are cleaned up when the PR closes
(`preview-cleanup.yml`).

### Release artifacts

- `CHANGELOG.md` section for the version
- GitHub Release (created by `release.yml` on tag push)
- Docker image in Artifact Registry (tagged with commit SHA)
- Cloud Run revision (tagged with commit SHA, serving 100% traffic)

---

## 9. Roles and Responsibilities

| Role | Owns | Cannot Do |
|------|------|-----------|
| **Product Manager** | Vision, PRD, roadmap, go/no-go on features, `/research`, `/jtbd`, `/positioning` | Backlog management, implementation |
| **Product Owner** | Backlog, ticket authoring, sprint priorities, `/groom-backlog` | Strategic feature decisions |
| **Ticket Worker** | Implementation, tests, PRs, branch ownership | Merge PRs, approve own work |
| **PR Reviewer** | Code review, GO/NO-GO recommendations, `/review-pr` | Merge PRs (recommendation only) |
| **Quality Engineer** | Test plans, coverage reports, quality gates | Implementation |
| **System Architect** | Architecture decisions, `TECHNICAL-ARCHITECTURE.md`, `/architect-review` | Implementation |
| **Human (founder/facilitator)** | Merging PRs, final go/no-go, workshop delivery | Delegated to agents |
| **CTO (this role)** | Engineering team, technology vision, SDLC standards, agent hiring | Product strategy |

### Account model

**Solo mode (default):** One GitHub account plays all agent roles. For
individual learners and workshop attendees.

**Multi-bot mode:** Separate `va-worker` and `va-reviewer` GitHub accounts
with human merger. Provides audit trail and separation of duties for
production use. Switched automatically by `.claude/hooks/ensure-github-account.sh`
based on `AGILE_FLOW_WORKER_ACCOUNT` / `AGILE_FLOW_REVIEWER_ACCOUNT` env
vars.

---

## 10. Additional SDLC Considerations

### Agentic safety controls

Eight layers of controls prevent agent misbehavior (see
`docs/AGENTIC-CONTROLS.md`):

1. Agent definitions constrain role and tools
2. CLAUDE.md critical rules enforced at session start
3. Pre-push hook catches unsafe commits locally
4. CI validates agent policies on every PR
5. Branch protection requires human approval to merge
6. Preview environment gates production traffic
7. Alembic migrations run before deploy (schema safety)
8. Sentry captures runtime errors and surfaces them to agents

### Memory architecture

Agents maintain scoped memory across sessions. Memory sources (in priority
order): system prompt, CLAUDE.md, agent definition, session context, slash
commands. See `docs/MEMORY-ARCHITECTURE.md` for the full data flow.

### Ephemeral PR environments

Every PR gets a full isolated environment (Neon branch + Cloud Run
revision tag). This means:

- Migrations are always tested before they reach production
- Reviewers can test the actual deployment, not just the code
- Cleanup is automatic on PR close

See `docs/EPHEMERAL-PR-ENVIRONMENTS.md` for the full architecture.

### Known gaps

| Gap | Status |
|-----|--------|
| Automated end-to-end workshop provisioning test | Not yet built |
| AWS variant sync documentation | Pending (mirrors GCP pattern) |
| Automated version bump in CI | Intentionally manual for now |
| mypy as a blocking CI gate | Informational only; full type coverage TBD |

---

## Related Documents

| Document | Purpose |
|----------|---------|
| `docs/BRANCHING-STRATEGY.md` | Trunk-based dev, branch naming, PR workflow |
| `docs/CI-CD-GUIDE.md` | Workflow details, secrets management, troubleshooting |
| `docs/CONVENTIONAL-COMMITS.md` | Commit format guide (human-readable) |
| `docs/TICKET-FORMAT.md` | Agentic PRD Lite canonical ticket format |
| `docs/ARTIFACT-FLOW.md` | Full artifact lifecycle with Mermaid diagrams |
| `docs/AGENTIC-CONTROLS.md` | 8-layer agent safety controls |
| `docs/EPHEMERAL-PR-ENVIRONMENTS.md` | Cloud Run + Neon preview architecture |
| `docs/FACILITATOR-RUNBOOK.md` | Workshop delivery checklist |
| `VERSIONING.md` | Semver policy and compatibility promise |
| `UPSTREAM.md` | Fork relationship and changed-file inventory |
