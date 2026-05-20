# ADR-001: Use template-sync over upgrade.sh / pull-upstream.sh for template updates

- Status: accepted
- Date: 2026-05-14

## Context

The repository needed a reliable way to ingest upstream template changes while preserving local overrides and avoiding repeated manual conflict resolution. Three mechanisms were in active discussion and usage history:

- `scripts/template-sync.sh`
- `scripts/upgrade.sh`
- `scripts/pull-upstream.sh`

Consultant review #188 highlighted that this architectural decision existed in practice but was not explicitly documented as a durable rationale.

## Decision

Adopt `scripts/template-sync.sh` as the default and supported path for template update operations.

`upgrade.sh` and `pull-upstream.sh` remain implementation artifacts but are not the primary decision path for routine template-update workflows.

Rationale:

- `template-sync.sh` aligns with the repository's override model (`scripts/lib/overrides.sh`) and conflict handling expectations.
- It provides a consistent operator path and avoids fragmented update behavior across multiple scripts.
- It matches the implementation direction already validated in review #188.

## Consequences

- Documentation and reviews should treat `template-sync.sh` as the canonical mechanism.
- Architecture-level changes to sync behavior now require ADR references in PR context.
- Future decisions that supersede this strategy must be captured in a new ADR.

## References

- GitHub review #188 (template-sync decision context)
- [VIB-131] Wave 1 / Workstream B scope and acceptance
