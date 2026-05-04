---
description: Apply a small fix or content change without full ticket ceremony
---

Make a quick, targeted change (bug fix, content update, config tweak) using a
lightweight workflow that skips ticket creation and board management.

## Pre-Flight Verification (REQUIRED)

Before any work, verify the following. STOP and report if any check fails.

1. **GitHub account is correct** — Run `gh auth status` and confirm the active
   account is appropriate for the work being done.
   - **Solo mode** (`AGILE_FLOW_SOLO_MODE=true`, the framework default): the
     participant's personal account plays all roles. The personal-account-only
     state is EXPECTED, not a failure.
   - **Multi-bot mode**: verify the active account matches the configured
     worker bot. If only a personal account is active in multi-bot mode, STOP
     and instruct the user to run `.claude/hooks/ensure-github-account.sh`.
2. **GitHub access is reachable via `gh` CLI** — Confirm authentication works
   with a quick read-only call (e.g., `gh repo view`). If gh fails, STOP.
   (The framework uses `gh` as the primary GitHub mechanism per CLAUDE.md;
   an MCP GitHub server is optional and not part of the default `.mcp.json`.)

## When to Use This Command

- Bug fixes found during development (not from a ticket)
- Content or copy updates (data files, presets, text changes)
- Config tweaks (linter rules, CI fixes, dependency bumps)
- **Bootstrap-pipeline output PR #1** — after running `/research` →
  `/jtbd` → `/positioning` → `/bootstrap-product` → `/bootstrap-architecture` →
  `/bootstrap-agents` → `/bootstrap-workflow`, the accumulated config
  + docs land as a single Quick Fix PR. See
  `bootstrap-workflow.md` Step 7 for the exact `git`/`gh` sequence.
- Session journal commits — same Quick Fix shape, no linked ticket
- Any change the user explicitly requests without a ticket

**Do NOT use this for feature work.** If the change introduces new behavior,
touches more than 3 files, or takes longer than ~1 hour, create a ticket with
`/create-ticket` and use `/work-ticket` instead.

> **Note on the bootstrap exception:** the bootstrap-output PR routinely
> touches 10+ files (research artifacts, PRD, roadmap, architecture,
> agent specs, CLAUDE.md). That breaks the "≤3 files" guideline above
> on purpose — bootstrap is a one-shot project-creation event, not
> ongoing feature work. The "≤3 files" rule still holds for normal
> Quick Fixes.

## Workflow

1. **Confirm scope** — Describe the change to the user in 1-2 sentences. If
   the user hasn't specified what to fix, ask before proceeding.
2. **Create branch** — `fix/short-description` or `content/short-description`
3. **Implement** — Follow CLAUDE.md standards, write clean code
4. **Test locally** — Run lint and tests. Do NOT push if any fail.
5. **Push and create PR** — Include "Quick fix — no linked ticket" in the PR
   description body
6. **Skip board updates** — Do NOT move any board items. There is no linked
   ticket. Do NOT guess which ticket this corresponds to.

## What This Command Does NOT Skip

- Branch requirement (never commit to main)
- PR requirement (never merge without review)
- Test requirement (never push with failing tests)
- Account verification (still use worker bot account)
- Human merge (agent never merges)

## Usage

```
/quick-fix
/quick-fix Fix typo in footer component
/quick-fix Update API base URL in config
```
