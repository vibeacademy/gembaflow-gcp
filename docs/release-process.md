# Agile Flow GCP Release Process

This runbook defines how maintainers cut releases for `vibeacademy/agile-flow-gcp`.

## Owner

- Primary owner: **DevOps Engineer (GCP)**

## Cadence Policy

Release `agile-flow-gcp` on two triggers:

1. **On-demand for GCP-track fixes** when the GCP template changes in a way that should be distributed immediately.
2. **Follow-up after founder-track releases** within **10 business days** when upstream founder-track changes should also be adopted here.

`agile-flow-gcp` is **not** a strict mirror of `agile-flow`. Only pull founder-track changes that are compatible with the GCP track and this repository's direction.

## Pre-Publish Checklist

Complete all checks before creating a tag:

- [ ] Working tree is clean on `main` (`git status --short` shows no changes).
- [ ] `CHANGELOG.md` includes release notes for the new version.
- [ ] `.agile-flow-version` matches the intended tag (for example `1.2.3` for `v1.2.3`).
- [ ] `scripts/template-sync.sh` references `UPSTREAM_REPO="vibeacademy/agile-flow-gcp"`.
- [ ] CI is green on the commit being tagged.
- [ ] Smoke-check key framework files versus prior release (`CLAUDE.md`, `.claude/agents/*`, `.claude/commands/*`, release workflows).
- [ ] Spot-check the generated release tarball after publish.

## Publish Steps (CLI)

1. Update local `main`.

```bash
git checkout main
git pull --ff-only origin main
```

2. Confirm version metadata and changelog are ready.

```bash
cat .agile-flow-version
rg '^## ' CHANGELOG.md | head
```

3. Create and push an annotated tag.

```bash
VERSION="v1.2.3"
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"
```

4. Wait for the release workflow to finish successfully.

```bash
GH_TOKEN="$GITHUB_TOKEN" gh run list --workflow "release.yml" --limit 5
GH_TOKEN="$GITHUB_TOKEN" gh run watch <run-id>
```

5. Verify the GitHub Release artifact exists and references the expected commit.

```bash
GH_TOKEN="$GITHUB_TOKEN" gh release view "$VERSION"
```

## Validation After Publish

- Confirm the newest release is visible at:
  - `https://github.com/vibeacademy/agile-flow-gcp/releases/latest`
- Confirm upgrade consumers resolve the expected latest version from the releases endpoint.
- Record the release link in project tracking notes or issue comments.
