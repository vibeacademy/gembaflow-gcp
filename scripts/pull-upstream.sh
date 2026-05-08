#!/usr/bin/env bash
# pull-upstream.sh — Apply latest framework changes from vibeacademy/agile-flow.
#
# Safe to run mid-workshop from a Codespace. Only updates files that exist in
# the upstream repo AND are in the syncDirectories list. Files listed in
# .agile-flow-overrides are never touched.
#
# Usage:
#   bash scripts/pull-upstream.sh
#
# Exit codes:
#   0  — success (up to date or changes applied)
#   1  — error (clean tree required, gh auth required, fetch failure)

set -euo pipefail

UPSTREAM_REPO="https://github.com/vibeacademy/agile-flow.git"
UPSTREAM_REMOTE="upstream"
VERSION_FILE=".agile-flow-version"
OVERRIDES_FILE=".agile-flow-overrides"

# ── Pre-flight ────────────────────────────────────────────────────────────────

# 1. Clean working tree
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: Working tree has uncommitted changes." >&2
  echo "Stash or commit them first:" >&2
  echo "  git stash" >&2
  echo "  /pull-upstream" >&2
  exit 1
fi

# 2. Version file
if [ ! -f "$VERSION_FILE" ]; then
  echo "ERROR: $VERSION_FILE not found. Is this an Agile Flow fork?" >&2
  exit 1
fi

# ── Read config ───────────────────────────────────────────────────────────────

SYNC_DIRS=$(python3 -c "
import json
dirs = json.load(open('$VERSION_FILE')).get('syncDirectories', [])
print('\n'.join(dirs))
")

# Load overrides (one path per line; lines starting with # are comments)
declare -A OVERRIDE_MAP
if [ -f "$OVERRIDES_FILE" ]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    OVERRIDE_MAP["$line"]=1
  done < "$OVERRIDES_FILE"
fi

OVERRIDE_COUNT="${#OVERRIDE_MAP[@]}"
echo "Sync directories : $(echo "$SYNC_DIRS" | tr '\n' ' ')"
echo "Protected overrides: $OVERRIDE_COUNT file(s)"

# ── Add / fetch upstream remote ───────────────────────────────────────────────

if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
  echo "Adding upstream remote..."
  git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_REPO"
fi

echo "Fetching from upstream..."
if ! git fetch "$UPSTREAM_REMOTE" main --quiet 2>&1; then
  echo "ERROR: Could not fetch from upstream ($UPSTREAM_REPO)." >&2
  echo "Check your network connection and try again." >&2
  exit 1
fi

UPSTREAM_SHA=$(git rev-parse "$UPSTREAM_REMOTE/main")
echo "Upstream HEAD    : ${UPSTREAM_SHA:0:12}"

# ── Apply upstream files ──────────────────────────────────────────────────────

FILES_UPDATED=()
FILES_SKIPPED_OVERRIDE=()
FILES_ALREADY_CURRENT=0

while IFS= read -r sync_dir; do
  [ -z "$sync_dir" ] && continue

  # List every file that exists in this directory on upstream/main
  while IFS= read -r filepath; do
    [ -z "$filepath" ] && continue

    # Skip if this file is a local override
    if [[ -n "${OVERRIDE_MAP[$filepath]+_}" ]]; then
      FILES_SKIPPED_OVERRIDE+=("$filepath")
      continue
    fi

    # Get upstream content (as blob hash for fast comparison)
    upstream_blob=$(git ls-tree "$UPSTREAM_REMOTE/main" "$filepath" 2>/dev/null | awk '{print $3}')
    if [ -z "$upstream_blob" ]; then
      continue
    fi

    # Compare blob hash with local HEAD
    local_blob=$(git ls-tree HEAD "$filepath" 2>/dev/null | awk '{print $3}')

    if [ "$upstream_blob" = "$local_blob" ]; then
      FILES_ALREADY_CURRENT=$((FILES_ALREADY_CURRENT + 1))
      continue
    fi

    # File differs — apply upstream version
    mkdir -p "$(dirname "$filepath")"
    git show "$UPSTREAM_REMOTE/main:$filepath" > "$filepath"
    git add "$filepath"
    FILES_UPDATED+=("$filepath")

    if [ -n "$local_blob" ]; then
      echo "UPDATED : $filepath"
    else
      echo "ADDED   : $filepath"
    fi

  done < <(git ls-tree -r --name-only "$UPSTREAM_REMOTE/main" "$sync_dir" 2>/dev/null)

done <<< "$SYNC_DIRS"

# ── Summarise and commit ──────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "${#FILES_UPDATED[@]}" -eq 0 ]; then
  echo "Already up to date with upstream."
  echo "  Already current: $FILES_ALREADY_CURRENT file(s)"
  if [ "${#FILES_SKIPPED_OVERRIDE[@]}" -gt 0 ]; then
    echo "  Skipped (local overrides): ${#FILES_SKIPPED_OVERRIDE[@]} file(s)"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# Build commit body
BODY=""
for f in "${FILES_UPDATED[@]}"; do
  BODY+="- $f"$'\n'
done

git -c user.name="pull-upstream" \
    -c user.email="noreply@github.com" \
    commit -m "chore(upstream): sync framework files from agile-flow@${UPSTREAM_SHA:0:7}

${BODY}"

echo "Applied ${#FILES_UPDATED[@]} upstream change(s) — committed."
echo ""
echo "Updated files:"
for f in "${FILES_UPDATED[@]}"; do
  echo "  - $f"
done

if [ "${#FILES_SKIPPED_OVERRIDE[@]}" -gt 0 ]; then
  echo ""
  echo "Skipped (local overrides — intentionally GCP-customised):"
  for f in "${FILES_SKIPPED_OVERRIDE[@]}"; do
    echo "  - $f"
  done
fi

echo ""
echo "Next step: push to origin so Codespace participants get the update"
echo "  git push origin HEAD"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
