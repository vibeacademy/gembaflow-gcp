---
description: "Phase 4: Activate the development workflow"
---

Set up GitHub project board, branch protection, and create initial backlog from PRD features.

## Bootstrap Phase 4: Workflow Activation

**Prerequisites**:
- Phase 1 (Product Definition) complete
- Phase 2 (Technical Architecture) complete
- Phase 3 (Agent Specialization) complete

This is the final bootstrap phase. It activates the full agent workflow.

## Ticket Format Requirement

Before creating any issues, read `docs/TICKET-FORMAT.md` in full. Every issue
created in this phase — epics and features alike — MUST follow the Agentic PRD
Lite format. Tickets without the 4 Power Sections (A. Environment Context,
B. Guardrails, C. Happy Path, D. Definition of Done) will not pass grooming
and will have to be rewritten.

## What This Phase Does

### 1. GitHub Project Board Setup

> **Order matters.** The board must be created at the right scope (org vs
> user) for your fork. User-scoped projects cannot natively discover
> org-owned repos, which silently breaks the bulk "Add items from a
> repository" flow AND the Step 2 auto-add workflow. Get this wrong and
> every issue requires manual paste-by-URL for the lifetime of the
> project. (#118)

**First, detect your fork's ownership type:**

```bash
gh repo view --json isInOrganization --jq '.isInOrganization'
# → true   (workshop default — vibeacademy/<handle>)
# → false  (personal-fork default — <username>/<repo>)
```

**Then create the board at the matching scope:**

| Detection output | Create board at | Board can natively discover repo? |
|------------------|-----------------|-----------------------------------|
| `true`  (org-owned)  | `https://github.com/orgs/<org>/projects/new` | Yes — bulk import + auto-add both work |
| `false` (user-owned) | `https://github.com/users/<user>/projects/new` | No for cross-account repos — manual URL-paste only |

**Permission fallback (org-owned fork without org-project-create permission):**

If your fork is at `<org>/<repo>` but the org's project-creation policy
restricts you (typical for workshop attendees on `vibeacademy/<handle>`
where only the facilitator has org-admin), you have three options:

1. **Ask the facilitator** to create the org-scoped project and grant
   you write on it (recommended for workshop — preserves bulk import
   + auto-add)
2. **Fall back to user-scoped** at `https://github.com/users/<you>/projects/new`
   and accept the limitation: the board will not discover your org repo
   for bulk import, and Step 2's auto-add workflow cannot be enabled
   for cross-account repos. Every new issue must be manually pasted
   into the Backlog column input row.
3. **Move the fork to your personal account** (`gh repo transfer`) and
   create the user-scoped board — only viable if the org doesn't need
   to retain ownership

**Verify or create the project board with these columns:**

- **Icebox** - Ideas not yet prioritized
- **Backlog** - Prioritized but not ready
- **Ready** - Well-defined, ready to work (2-5 items)
- **In Progress** - Currently being worked
- **In Review** - PR created, awaiting review
- **Done** - Merged and complete

### 2. Enable Project Board Workflows (manual UI — REQUIRED before creating issues)

> **Order matters.** Enable both built-in workflows **before** creating
> any issues in step 4. Both workflows apply only to issues created
> from the moment they're enabled forward — they do **not** backfill
> existing issues. Doing this in the wrong order strands every issue
> created before this step. (#120, #86)

Two workflows to enable in the same UI panel:

- **Auto-add to project** — automatically adds new repo issues to the
  board's `Backlog` column. Without this, every issue requires a
  manual board-add for the lifetime of the project.
- **Item closed → Status: Done** — auto-moves an issue to `Done` when
  its PR merges (PR body has `Closes #N` → GitHub auto-closes the
  issue → workflow bumps the Status column). Without this, every
  merged PR leaves its issue stuck in `In Review` until a human
  manually drags it. The framework's "only humans move to Done" rule
  is honored either way; this just removes the per-merge step.

**Manual UI toggle (recommended) — pick the path matching your Step 1 board scope:**

#### Path A: Org-scoped board (recommended — works fully)

1. Open the project: `https://github.com/orgs/<org>/projects/<N>`
2. Click **⋯** (top-right) → **Workflows**
3. **Enable Auto-add to project:**
   - Find **"Auto-add to project"**
   - Set **Repository** = the repo this board serves (the picker
     will show all repos in `<org>` you have access to)
   - Set **Filter** = `is:issue` (or leave empty to include PRs too)
   - Toggle **Enabled**
   - Click **Save and turn on workflow**
4. **Enable Item closed → Done:**
   - Find **"Item closed"**
   - Set **When** = `Issue is closed`
   - Set **Set Status** = `Done`
   - Toggle **Enabled**
   - Click **Save and turn on workflow**

#### Path B: User-scoped board with cross-account org-owned repo (limited)

If you fell back to a user-scoped board (Step 1, option 2 of the
permission fallback), the **Auto-add to project** workflow is NOT
configurable for cross-account repos — the **Repository** picker
only lists repos owned by the project owner (you). This is a
GitHub Projects v2 platform limitation, not a configuration mistake.

What still works:

1. Open the project: `https://github.com/users/<you>/projects/<N>`
2. Click **⋯** (top-right) → **Workflows**
3. **Enable Item closed → Done** (this one IS configurable for any
   linked issue, regardless of repo owner — same steps as Path A
   step 4 above)
4. **Auto-add: skip.** Every new issue from your org-owned fork
   must be manually pasted into the Backlog column input row.
   Step 4 below documents the workflow.

#### Path C: User-scoped board with same-owner repo (works fully)

If both the project and the repo are owned by the same personal
account (e.g. `<you>/<your-repo>` with a board at
`/users/<you>/projects/<N>`), follow Path A's steps but use the
user-scoped project URL.

**Why not via API:** GitHub's GraphQL exposes `projectV2.workflows`
for read and `deleteProjectV2Workflow` for removal, but no
`createProjectV2Workflow` or `updateProjectV2Workflow` mutation
exists. Built-in workflows can only be configured via the web UI.
See #86 for the API research.

If the user can't access the UI right now, document that the toggles
are pending. Step 4 below will need the explicit backfill step for
any issues created before this point.

### 3. Branch Protection Configuration

Branch protection on `main` requires admin write on the repo. Two paths
depending on who owns admin:

**Workshop-org-hosted setup (May 2026 architecture):** branch protection
should already be in place — the facilitator runs
`scripts/setup-repo-protection.sh` against each attendee repo at
provisioning time. Verify with:

```bash
gh api repos/<owner>/<repo>/branches/main/protection >/dev/null && \
  echo "✓ branch protection in place" || \
  echo "✗ branch protection NOT configured — see Manual UI fallback below"
```

If the verify command reports it's NOT configured and you have admin,
run `bash scripts/setup-repo-protection.sh` from the repo root. If you
don't have admin (typical for a workshop attendee on `vibeacademy/<handle>`),
the facilitator should re-run the provisioning script for your repo, OR
configure manually via the UI fallback below.

**Personal-account fork or self-hosted setup:** you have admin on your
own repo. Two ways to set protection:

```bash
# Recommended: scripted, idempotent, matches framework's expected state
bash scripts/setup-repo-protection.sh
```

Or via the GitHub Settings UI (if the script can't run for any reason):

**Manual UI fallback:**

1. Open `https://github.com/<owner>/<repo>/settings/branches`
2. Click **Add classic branch protection rule** (or **Add rule** — wording
   varies by org plan)
3. Branch name pattern: `main`
4. Check the following (matches `scripts/setup-repo-protection.sh`):
   - **Require a pull request before merging** → ✓ Required approvals: `1`
   - **Require linear history** ✓
   - **Do not allow bypassing the above settings** ✓
   - **Allow force pushes** ☐ (leave unchecked)
   - **Allow deletions** ☐ (leave unchecked)
5. Status checks: leave unchecked for now (configure per-cohort once
   CI check names are known)
6. Click **Create** / **Save changes**

### 4. Initial Backlog Creation

Convert PRD features into GitHub issues following `docs/TICKET-FORMAT.md`:
- Create epics for major feature areas (epics use Problem Statement + high-level scope)
- Create feature issues with ALL required fields:
  - Problem Statement, Parent Epic, Effort Estimate, Priority
  - A. Environment Context (from `docs/TECHNICAL-ARCHITECTURE.md`)
  - B. Guardrails (from `docs/AGENTIC-CONTROLS.md` + PRD constraints)
  - C. Happy Path (numbered steps: Input → Logic → Output)
  - D. Definition of Done (specific test assertions, lint commands, reviewer checks)
- Link issues to epics
- Add priority labels (P0/P1/P2/P3)

> **Backfill check:** if any issues were created **before** step 2
> (auto-add workflow enabled), they are NOT on the board. The
> auto-add workflow does not backfill. Manually add them: open the
> project's `Backlog` column, click the input row at the bottom of
> the column, and paste each orphaned issue's URL. Confirm with
> `/sprint-status` that all issues appear on the board before
> proceeding.

### 5. Ready Column Population

Move the highest-priority, well-defined tickets to Ready:
- Select 3-5 tickets for initial Ready column
- Ensure they meet Definition of Ready
- Add technical guidance and acceptance criteria

### 6. CLAUDE.md Finalization

Update CLAUDE.md with:
- Project board URL
- Repository URL
- Team/org information
- Any final configuration

### 7. Commit and ship the bootstrap output

By this point you've accumulated **a lot** of uncommitted output across
the bootstrap pipeline (`/research`, `/jtbd`, `/positioning`,
`/bootstrap-product`, `/bootstrap-architecture`, `/bootstrap-agents`,
plus this phase's CLAUDE.md edits). None of the bootstrap commands
commit on your behalf — that's intentional, so you can review the
output before it lands. But leaving it uncommitted creates two real
problems:

1. **`/work-ticket`'s pre-flight will catch it.** The first time you
   try to pick up a real ticket, the worker's pre-push hook trips on
   the dirty working tree. You then have to recover with a Quick Fix
   PR — exactly what this step is here to prevent you from having to
   discover the hard way.
2. **The bootstrap output gets entangled with your first feature
   commit.** Every `feature/issue-*` branch from `main` would carry
   the bootstrap diff alongside the actual feature code, making the
   review messy and the PR diff misleading.

**Ship the bootstrap output as a single Quick Fix PR (no linked ticket)
before starting any other work.** Quick Fix Protocol applies — branch
+ commit + PR, no ticket ceremony, since this is content/config not a
tracked feature. From your repo root:

```bash
# Make sure you're on main with no other in-flight changes
git status   # should show ONLY bootstrap-output files

# Branch with a clear name; date suffix avoids collisions on re-bootstrap
git checkout -b content/bootstrap-output-$(date +%Y-%m-%d)

# Stage everything bootstrap created — adjust if your stack diverged
git add CLAUDE.md docs/ .claude/agents/ .claude/PROJECT.md

# Conventional commit; replace <product-name> with what you locked in
# during /bootstrap-product (the value sitting in CLAUDE.md right now).
git commit -m "chore(config): initial <product-name> bootstrap"

# Push and open the PR. Mark it explicitly as Quick Fix.
git push -u origin HEAD
gh pr create \
    --title "chore(config): initial <product-name> bootstrap" \
    --body "Quick fix — no linked ticket. All bootstrap pipeline output (research, PRD, roadmap, architecture, agents, project config) in one commit." \
    --base main
```

A couple of details worth knowing:

- **Single commit vs phase-by-phase:** the framework prescribes a
  single commit for simplicity. If you want phase-by-phase attribution,
  you can split into multiple commits within the same PR — but keep
  the PR singular. Multi-PR bootstrap is rejected — see
  CLAUDE.md "Quick Fix Protocol" + the trunk-based development rule.
- **`Closes #N` is NOT applicable** — this is a Quick Fix PR with no
  linked ticket. Don't add a `Closes #` line; the PR body's "Quick fix
  — no linked ticket" sentence is the canonical marker.
- **Don't move any board items.** There's no ticket to move. The
  Quick Fix flow specifically says skip board moves (CLAUDE.md → Quick
  Fix Workflow step 5).
- **Branch protection (Step 3) means you cannot push directly to
  `main`.** This step's PR is how the bootstrap output reaches `main`
  — through the same review/merge gate every other change uses.

After this lands, `main` has a clean baseline: bootstrap output in
one PR, your first feature ticket starts from a tidy state, and
`/work-ticket`'s pre-flight passes on the first try.

## Pre-Flight Checklist

Before running this phase, ensure you have:

- [ ] GitHub repository created
- [ ] GitHub personal access token with repo, project, and workflow permissions
- [ ] Permission to create project boards
- [ ] Permission to configure branch protection

## Pre-Flight Verification (REQUIRED)

Before any board or ticket operations, verify the following. STOP and report
to the user if any check fails — do not continue with partial tooling.

1. **GitHub account is correct** — Run `gh auth status` and confirm the active
   account is appropriate for the work being done.
   - **Solo mode** (`AGILE_FLOW_SOLO_MODE=true`, the framework default per
     CLAUDE.md and the Codespaces devcontainer): the participant's personal
     account plays all roles — worker, reviewer, human merger. The
     personal-account-only state is EXPECTED, not a failure.
   - **Multi-bot mode**: verify the active account matches the configured
     worker bot (`$AGILE_FLOW_WORKER_ACCOUNT`, default `va-worker`). If only
     a personal account is active in multi-bot mode, STOP and instruct the
     user to run `.claude/hooks/ensure-github-account.sh`.
2. **GitHub access is reachable via `gh` CLI** — Confirm authentication works
   with a quick read-only call (e.g., `gh repo view`, `gh issue list --limit 1`).
   If gh fails, STOP. The framework uses `gh` as the primary GitHub mechanism
   (per CLAUDE.md "Agents use the `gh` CLI for all GitHub operations"); an
   MCP GitHub server is optional and not part of the default `.mcp.json`.
3. **Token scopes sufficient for board operations** — Run the probe:
   `gh api graphql -f query='{ viewer { projectsV2(first:1) { totalCount } } }'`
   If this fails with `Resource not accessible by integration`, the active
   token lacks the `project` scope. STOP with a clear remediation message
   matching the user's setup:

   **In a Codespace** — configure a `GH_TOKEN` Codespaces user secret. Two
   PAT-type paths:

   - **Classic PAT (recommended for workshop attendees on `vibeacademy/<handle>`)** —
     create at `https://github.com/settings/tokens` → "Generate new token (classic)"
     with scopes: `repo, project, workflow, read:org`. Works on org-level
     Project v2 boards immediately, no org-admin involvement needed.
   - **Fine-grained PAT (recommended for solo developers on their own orgs)** —
     create at `https://github.com/settings/personal-access-tokens` with
     `Repository access: <your fork>` and permissions `Contents: read/write,
     Pull requests: read/write, Workflows: read/write, Projects: read/write,
     Metadata: read`. **Org-admin allowlist required:** if your fork is
     under an org you don't admin (typical for workshop attendees on
     `vibeacademy`), the org's Settings → Personal access tokens policy
     must enable "Allow access via fine-grained personal access tokens"
     for your PAT to work. Without that allowlist, the same `Resource not
     accessible by integration` error fires even though your PAT lists the
     right permissions. Workshop attendees should use the classic-PAT path
     above to bypass this org-admin step entirely.

   See `docs/GETTING-STARTED.md` for the click-by-click and `docs/FAQ.md`
   for the "Resource not accessible by integration" symptom guide.

   **On a local clone** — run `gh auth refresh -h github.com -s project,read:project`.
4. **Claude hooks are registered** — Check that hook files referenced in
   `.claude/settings.local.json` exist and are executable. WARN if any hook is
   missing or not executable.
5. **Project board is accessible** — Attempt to read the project board. If
   access is denied or the board does not exist, STOP and report.

## Configuration Required

You'll be asked to provide:

```
GitHub Organization: [your-org]
Repository Name: [your-repo]
Project Board Name: [your-project-name]
```

## Process

The workflow activation agent will:

1. **Verify GitHub Access**
   - Test token permissions
   - Confirm org/repo access

2. **Create/Verify Project Board**
   - Check if board exists
   - Create columns if needed
   - Configure board settings

3. **Enable Project Board Workflows (REQUIRED before backlog creation)**
   - Walk the user through the manual UI toggle for both built-in
     workflows: "Auto-add to project" and "Item closed → Status: Done"
   - Verify both are enabled before proceeding
   - This MUST happen before issues are created — neither workflow
     backfills, so issues created earlier are stranded

4. **Configure Branch Protection**
   - Check current settings
   - Apply protection rules
   - Verify configuration

5. **Generate Backlog**
   - Read `docs/TICKET-FORMAT.md` for the canonical ticket format
   - Read PRD features from `docs/PRODUCT-REQUIREMENTS.md`
   - Read `docs/TECHNICAL-ARCHITECTURE.md` for Environment Context content
   - Read `docs/AGENTIC-CONTROLS.md` for Guardrails content
   - Create epic issues (Problem Statement + scope description)
   - Create feature issues with all 4 Power Sections populated
   - Set initial priorities (P0-P3)
   - Self-check: before creating each issue, verify it contains sections A through D
   - Backfill any issues created before step 3: paste their URLs into
     the Backlog column's add-item input row

6. **Populate Ready Column**
   - Select MVP tickets
   - Ensure Definition of Ready met
   - Move to Ready column

7. **Update Configuration**
   - Add URLs to CLAUDE.md
   - Verify agent configs reference correct board

## Example Backlog Generation

> Every issue MUST follow `docs/TICKET-FORMAT.md`. The example below shows the
> expected structure. Do NOT create bare-title issues without Power Sections.

From a PRD feature like:
```markdown
### MVP Features
- User authentication (email/password)
```

Create an epic:
```
Epic: User Authentication

Problem Statement:
The application has no way to identify users. All routes are public.
We need email/password authentication to gate access to user-specific data.

Scope: signup, login, password reset, session management.
Priority: P0
```

Then create feature issues with full Power Sections:
```
TICKET: Implement email/password signup

Problem Statement:
New users cannot create accounts. We need a signup endpoint that accepts
email + password, validates input, and creates a user record.

Parent Epic: #<epic-number>
Effort Estimate: M
Priority: P0

--- A. Environment Context ---
- Stack: (from TECHNICAL-ARCHITECTURE.md)
- Existing pattern: (reference a similar route in the codebase)
- Files to create/modify: (list explicitly)

--- B. Guardrails ---
- (from AGENTIC-CONTROLS.md + PRD constraints)
- Do NOT store plaintext passwords
- Do NOT modify existing auth middleware

--- C. Happy Path ---
1. Client sends POST /auth/signup with {email, password}
2. Server validates email format and password strength
3. Server hashes password, creates user record
4. Server returns 201 with {id, email}

--- D. Definition of Done ---
- Test asserts POST /auth/signup with valid data returns 201
- Test asserts duplicate email returns 409
- Test asserts weak password returns 422
- Lint and type checks pass with zero errors
- PR reviewer can run the signup flow manually
```

## What Gets Unlocked

After Phase 4, the full workflow is active:

```
/groom-backlog  →  Works with your project board
/work-ticket    →  Picks up tickets from your Ready column
/review-pr      →  Reviews PRs in your repository
/sprint-status  →  Shows your board status
```

## Verification

After this phase, verify the workflow:

1. **Check Project Board**
   - Visit the GitHub project board URL
   - Verify columns exist
   - Verify issues created

2. **Check Branch Protection**
   - Go to repo Settings → Branches
   - Verify `main` is protected

3. **Test Workflow**
   ```bash
   claude
   > /sprint-status
   ```
   Should show your board status

## Post-Bootstrap

Your project is now ready for development!

**Daily workflow:**
```bash
/sprint-status    # Morning check
/work-ticket      # Pick up work
/review-pr        # Review PRs
```

**Weekly planning:**
```bash
/check-milestone  # Track progress
/groom-backlog    # Maintain backlog
```

## Troubleshooting

**"GitHub token not authorized"**
- Ensure token has `repo`, `project`, and `workflow` scopes
- Check token isn't expired

**"Cannot create project board"**
- Verify org permissions
- Try creating manually, then link

**"Branch protection failed"**
- Verify you have admin access to repo
- Configure manually in GitHub settings

**"Issues not appearing on board"**
- Check issue labels match board filters
- Manually add issues to project

## Running This Command

1. Ensure Phases 1-3 are complete
2. Have GitHub credentials ready
3. Type `/bootstrap-workflow`
4. Provide org/repo information
5. Review proposed changes
6. Confirm to apply

When complete, your Agile Flow project is fully operational!

## Next Steps

After bootstrap:

1. **Review the backlog** - `/groom-backlog`
2. **Start first ticket** - `/work-ticket`
3. **Invite team members** - Share repo access
4. **Set up CI/CD** - Configure GitHub Actions
5. **Schedule standups** - Daily `/sprint-status`

### Output Format

Report each phase with a Progress Line, then end with a Result Block:

```
→ Configured GitHub project board
→ Set up branch protection rules
→ Generated backlog from PRD (12 issues)
→ Populated Ready column (4 tickets)

---

**Result:** Workflow setup complete
Project board: configured
Issues created: 12
Ready column: 4 tickets
Status: ready for development
```
