# Architecture Decision Records (ADRs)

This directory records architecture-level decisions for `agile-flow-gcp`.

## Scope policy

- Forward-only from 2026-05-12 onward.
- One approved retroactive backfill exists: ADR-001.
- Do not back-fill earlier historical decisions beyond ADR-001.

## When to write an ADR

Create or update an ADR when a pull request introduces or changes architectural behavior, especially around:

- template synchronization strategy
- upstream sync mechanics
- CI/workflow topology for repository automation

## Workflow

1. Copy [0000-template.md](./0000-template.md) to a new numbered file.
2. Name files with a zero-padded sequence and short slug, for example `0002-my-decision.md`.
3. Fill in all sections: Context, Decision, Status, Consequences.
4. Reference the ADR in the pull request description/checklist.

## Current ADRs

- [0001-template-sync-over-upgrade-sh.md](./0001-template-sync-over-upgrade-sh.md)
