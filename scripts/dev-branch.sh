#!/usr/bin/env bash
#
# dev-branch.sh — Neon dev-branch lifecycle helper for local Codespaces.
#
# Mints a per-developer ephemeral Neon branch off `main`, writes its
# pooled connection URL into `.env` (gitignored), and runs alembic
# migrations so the branch matches current schema. The companion
# `--teardown` flag deletes the branch and removes `.env`.
#
# Replaces the manual `neonctl branches create + connection-string`
# dance documented as the fallback in `docs/LOCAL-DEV.md`. See #157
# (epic) and #158 (LOCAL-DEV.md) for context.
#
# Usage:
#   bash scripts/dev-branch.sh           # create + migrate
#   bash scripts/dev-branch.sh --teardown # delete branch + restore .env
#   bash scripts/dev-branch.sh --help
#
# Required environment variables:
#   NEON_API_KEY     Neon API key with write access to the project
#   NEON_PROJECT_ID  The Neon project this fork uses (the parent project
#                    that CI preview branches from). Workshop attendees
#                    inherit this from a Codespaces org secret per #160.
#
# Optional environment variables:
#   NEON_API_BASE          (default: https://console.neon.tech/api/v2)
#   NEON_PARENT_BRANCH     (default: main) Branch to fork from.
#   DEV_BRANCH_PREFIX      (default: dev-${USER}) Prefix for the branch
#                          name. Full name becomes <prefix>-<epoch>.
#   ENV_FILE               (default: .env) Where to write DATABASE_URL.
#   SKIP_MIGRATE           (default: empty) When set, skip the
#                          `uv run alembic upgrade head` step. Useful
#                          for tests that don't have alembic installed.
#
# Side effects:
#   - Creates ONE Neon branch per invocation (default mode); name is
#     unique via the epoch suffix so concurrent invocations don't collide.
#   - Writes ENV_FILE with `DATABASE_URL=<pooled URL>`. If ENV_FILE
#     already exists with non-default content, backs it up to
#     ${ENV_FILE}.bak first and warns.
#   - Runs `uv run alembic upgrade head` against the new branch unless
#     SKIP_MIGRATE is set.
#
# Exit codes:
#   0 — branch created (or torn down) successfully
#   1 — Neon API call failed; ENV_FILE write failed; migration failed
#   2 — required env vars missing; invalid arguments
#
# Idempotency:
#   Default mode is intentionally non-idempotent — each invocation creates
#   a fresh branch with a unique epoch suffix. Repeated runs accumulate
#   branches; use `--teardown` (which deletes ALL branches matching the
#   user's prefix) to clean up.

set -euo pipefail

# ── Argument parsing ─────────────────────────────────────────────────────

MODE="create"
case "${1:-}" in
    --teardown) MODE="teardown" ;;
    -h|--help)
        sed -n '1,55p' "$0"
        exit 0
        ;;
    "") ;;  # no flag, default mode
    *)
        echo "ERROR: unknown flag: $1" >&2
        echo "Usage: $0 [--teardown | --help]" >&2
        exit 2
        ;;
esac

# ── Pre-flight ───────────────────────────────────────────────────────────

if [ -z "${NEON_API_KEY:-}" ] || [ -z "${NEON_PROJECT_ID:-}" ]; then
    echo "ERROR: NEON_API_KEY and NEON_PROJECT_ID must be set" >&2
    echo "" >&2
    echo "  In a Codespace, configure both as Codespaces secrets at" >&2
    echo "  https://github.com/settings/codespaces — or inherit from" >&2
    echo "  the workshop-org Codespaces secrets your facilitator set." >&2
    echo "" >&2
    echo "  See docs/LOCAL-DEV.md for the full setup story." >&2
    exit 2
fi

NEON_API_BASE="${NEON_API_BASE:-https://console.neon.tech/api/v2}"
NEON_PARENT_BRANCH="${NEON_PARENT_BRANCH:-main}"
DEV_BRANCH_PREFIX="${DEV_BRANCH_PREFIX:-dev-${USER:-dev}}"
ENV_FILE="${ENV_FILE:-.env}"

# ── Neon API helpers (pattern from create-workshop-neon-projects.sh) ────

# GET — echoes body to stdout, returns curl exit code
neon_get() {
    local path="$1"
    curl --silent --show-error --fail \
        -H "Authorization: Bearer $NEON_API_KEY" \
        -H "Accept: application/json" \
        "${NEON_API_BASE}${path}"
}

# POST — body to a tempfile, http_code to stdout, curl exit code returned
neon_post() {
    local path="$1"
    local body="$2"
    local out_file="$3"
    curl --silent --show-error \
        --output "$out_file" \
        --write-out '%{http_code}' \
        -X POST \
        -H "Authorization: Bearer $NEON_API_KEY" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "${NEON_API_BASE}${path}"
}

# DELETE — http_code to stdout, curl exit code returned
neon_delete() {
    local path="$1"
    curl --silent --show-error \
        --output /dev/null \
        --write-out '%{http_code}' \
        -X DELETE \
        -H "Authorization: Bearer $NEON_API_KEY" \
        "${NEON_API_BASE}${path}"
}

# ── Mode: teardown ──────────────────────────────────────────────────────

if [ "$MODE" = "teardown" ]; then
    echo "──────────────────────────────────────────────────"
    echo "  Tearing down dev branches matching prefix: ${DEV_BRANCH_PREFIX}-*"
    echo "──────────────────────────────────────────────────"

    # List all branches in the project, filter by prefix.
    branches_json="$(neon_get "/projects/${NEON_PROJECT_ID}/branches")" || {
        echo "ERROR: failed to list Neon branches" >&2
        exit 1
    }

    # Extract branch IDs whose name starts with our prefix.
    matching_ids="$(echo "$branches_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
prefix = sys.argv[1]
for b in data.get('branches', []):
    if b.get('name', '').startswith(prefix):
        print(b.get('id', ''))
" "$DEV_BRANCH_PREFIX-")"

    if [ -z "$matching_ids" ]; then
        echo "  No matching branches to delete."
    else
        deleted=0
        while IFS= read -r branch_id; do
            [ -z "$branch_id" ] && continue
            http_code="$(neon_delete "/projects/${NEON_PROJECT_ID}/branches/${branch_id}")"
            if [ "$http_code" = "200" ] || [ "$http_code" = "202" ] || [ "$http_code" = "204" ]; then
                echo "  [delete] $branch_id"
                deleted=$((deleted + 1))
            else
                echo "  WARN: delete returned HTTP $http_code for $branch_id" >&2
            fi
        done <<< "$matching_ids"
        echo "  Deleted $deleted branch(es)."
    fi

    # Restore .env.bak if present, else remove .env
    if [ -f "${ENV_FILE}.bak" ]; then
        mv "${ENV_FILE}.bak" "$ENV_FILE"
        echo "  [restore] ${ENV_FILE} (from ${ENV_FILE}.bak)"
    elif [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        echo "  [remove]  ${ENV_FILE}"
    fi

    echo "Teardown complete."
    exit 0
fi

# ── Mode: create (default) ──────────────────────────────────────────────

BRANCH_NAME="${DEV_BRANCH_PREFIX}-$(date +%s)"

echo "──────────────────────────────────────────────────"
echo "  Creating Neon dev branch: ${BRANCH_NAME}"
echo "  Project:  ${NEON_PROJECT_ID}"
echo "  Parent:   ${NEON_PARENT_BRANCH}"
echo "──────────────────────────────────────────────────"

# Resolve parent branch ID (Neon's API takes branch IDs, not names, for
# the parent-branch reference inside branch creation).
parent_id="$(neon_get "/projects/${NEON_PROJECT_ID}/branches" | python3 -c "
import json, sys
data = json.load(sys.stdin)
target = sys.argv[1]
for b in data.get('branches', []):
    if b.get('name', '') == target:
        print(b.get('id', ''))
        sys.exit(0)
sys.exit(1)
" "$NEON_PARENT_BRANCH")" || {
    echo "ERROR: could not resolve parent branch '$NEON_PARENT_BRANCH' in project $NEON_PROJECT_ID" >&2
    exit 1
}

# Build the request body.
# `endpoints: [{type: read_write}]` ensures a compute endpoint is created
# (without it the branch has no connection URL).
request_body=$(cat <<EOF
{
  "branch": {
    "name": "${BRANCH_NAME}",
    "parent_id": "${parent_id}"
  },
  "endpoints": [
    { "type": "read_write" }
  ]
}
EOF
)

response_file="$(mktemp -t aflow-devbranch-XXXX)"
trap 'rm -f "$response_file"' EXIT

http_code="$(neon_post "/projects/${NEON_PROJECT_ID}/branches" "$request_body" "$response_file")"
if [ "$http_code" != "201" ] && [ "$http_code" != "200" ]; then
    echo "ERROR: Neon branch creation returned HTTP $http_code" >&2
    cat "$response_file" >&2 || true
    exit 1
fi

# Extract the pooled connection URI. Neon's response includes
# `connection_uris[0].connection_uri` (direct) and
# `connection_uris[0].connection_uri_pooled` for the pgbouncer URL.
pooled_url="$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
uris = data.get('connection_uris') or []
if not uris:
    sys.exit('ERROR: response missing connection_uris')
# Prefer pooled URL when available; fall back to direct.
print(uris[0].get('connection_uri_pooled') or uris[0].get('connection_uri', ''))
" "$response_file")"

if [ -z "$pooled_url" ]; then
    echo "ERROR: could not extract connection URI from Neon response" >&2
    exit 1
fi

# Backup existing .env if it has non-default content
if [ -f "$ENV_FILE" ] && [ -s "$ENV_FILE" ]; then
    cp "$ENV_FILE" "${ENV_FILE}.bak"
    echo "  [backup] ${ENV_FILE} → ${ENV_FILE}.bak"
fi

# Write the new .env. Don't echo the URL to stdout.
{
    echo "# Generated by scripts/dev-branch.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "# Branch: ${BRANCH_NAME}"
    echo "# Teardown: bash scripts/dev-branch.sh --teardown"
    echo "DATABASE_URL=${pooled_url}"
} > "$ENV_FILE"
echo "  [write]  ${ENV_FILE} (DATABASE_URL configured)"

# Run migrations against the new branch unless SKIP_MIGRATE
if [ -z "${SKIP_MIGRATE:-}" ]; then
    echo ""
    echo "  [migrate] Running: uv run alembic upgrade head"
    if ! DATABASE_URL="$pooled_url" uv run alembic upgrade head; then
        echo "ERROR: migration failed against new branch" >&2
        echo "       Branch ${BRANCH_NAME} is created but in unknown schema state" >&2
        echo "       Run: bash scripts/dev-branch.sh --teardown" >&2
        exit 1
    fi
fi

echo ""
echo "──────────────────────────────────────────────────"
echo "Dev branch ready."
echo "  Run your app:    uv run uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload"
echo "  Tear down later: bash scripts/dev-branch.sh --teardown"
echo "──────────────────────────────────────────────────"
