# Changelog

All notable changes to Agile Flow will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Purged 44 stale `vibeacademy/agile-flow-gcp` references inherited from the v1.1.0-era platform rebrand (#234).** Spans 15 files: 6 docs (`docs/RELEASE-PROCESS.md`, `docs/LOCAL-DEV.md`, `docs/FACILITATOR-RUNBOOK.md`, `docs/PLATFORM-GUIDE.md`, `README.md`, `VERSIONING.md`), 1 helper script (`scripts/provision-workshop-roster.sh`), 5 BDD files (`features/conftest.py`, `features/*.feature` × 2, `features/step_defs/*.py` × 2), and 3 CI workflows (`.github/workflows/deploy.yml`, `.github/workflows/preview-cleanup.yml`, `.github/workflows/preview-deploy.yml`). The 2 historical session journals (`reports/session-journals/2026-04-29.md`, `2026-05-03.md`) were preserved verbatim as archived records. **Side-effect bug fix:** the 4 CI-workflow references were inside `if: github.repository != 'vibeacademy/agile-flow-gcp'` guards that have been silently broken since the rename — comparing against the OLD repo name meant the upstream-skip mechanism evaluated `true` on the renamed upstream, causing jobs intended to skip on upstream to run instead. After this PR, the guards correctly reference `vibeacademy/gembaflow-gcp` and the original skip behavior is restored. Full BDD test suite continues to pass 62/62 post-rewrite.
- Bumped `astral-sh/setup-uv` from `@v4` to `@v5` in `auto-fix.yml` and `ci.yml`
  to use the Node 24 runtime ahead of the GitHub-enforced June 2026 cutover (#54)

## [0.9.0] - 2025-12-07

Pre-upgrade baseline — the first tagged release of Agile Flow.

### Added

- Core agent definitions: Product Manager, Product Owner, Ticket Worker, PR Reviewer, Quality Engineer, System Architect, DevOps Engineer
- Structured agile workflow with progressive refinement (Product Definition → Technical Architecture → Agent Specialization → Workflow Activation)
- Trunk-based development workflow with feature branches and PR-based merges
- GitHub Project board integration with Icebox, Backlog, Ready, In Progress, Review, Done columns
- Slash commands for agent interactions (`/lock-scope`, `/work-ticket`, etc.)
- `bootstrap.sh` interactive wizard for project initialization
- CI pipeline with validation tests (`.github/workflows/ci.yml`)
- Bot permissions verification script (`scripts/verify-bot-permissions.sh`)
- Hardened agent policies with NON-NEGOTIABLE PROTOCOL and bot account identity
- Agent action logging and audit trail (`scripts/analyze-agent-actions.sh`)
- Weekly agent restriction verification workflow
- Agent instruction linter (`scripts/lint-agent-policies.sh`)
- Weekly audit workflows and maintenance documentation
- Comprehensive Agent Workflow Summary documentation
- Product documentation templates (PRD, Roadmap)
- Getting Started guide

[Unreleased]: https://github.com/vibeacademy/agile-flow/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/vibeacademy/agile-flow/releases/tag/v0.9.0
