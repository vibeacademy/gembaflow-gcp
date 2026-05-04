#!/usr/bin/env bash
#
# Tests for dev-branch.sh.
#
# Stubs `curl` via PATH injection — the script's only network surface
# is curl calls to the Neon API. Stub responds with deterministic
# JSON for the GET/POST/DELETE paths the script actually uses.
#
# Run: ./scripts/dev-branch.test.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/dev-branch.sh"

new_tmp() {
    mktemp -d -t aflowdevbranch-XXXX
}

# Build a fake `curl` in $tmp/bin that responds to the Neon API endpoints
# the script invokes. The stub:
#   - GET /projects/<id>/branches      → returns a JSON list including a
#                                         `main` branch with a known ID
#   - POST /projects/<id>/branches     → writes a fake creation response
#                                         to the --output file, echoes 201
#   - DELETE /projects/<id>/branches/X → echoes 204
make_stubs() {
    local tmp="$1"
    mkdir -p "$tmp/bin"

    cat > "$tmp/bin/curl" <<EOF
#!/usr/bin/env bash
# Log every call. Last arg is the URL.
echo "curl \$*" >> "$tmp/curl.log"

# Find --output and --write-out values + the URL (last positional)
out_file=""
write_out=""
method="GET"
url=""
data=""
prev=""
for arg in "\$@"; do
    case "\$prev" in
        --output) out_file="\$arg"; prev=""; continue ;;
        --write-out) write_out="\$arg"; prev=""; continue ;;
        -X) method="\$arg"; prev=""; continue ;;
        -d) data="\$arg"; prev=""; continue ;;
    esac
    case "\$arg" in
        --output|--write-out|-X|-d) prev="\$arg" ;;
        *) url="\$arg" ;;
    esac
done

# Route by method + URL pattern.
if [ "\$method" = "GET" ] && [[ "\$url" == *"/branches" ]]; then
    cat <<JSON
{"branches":[{"id":"br-main-fake","name":"main"},{"id":"br-existing-fake","name":"\${DEV_BRANCH_PREFIX:-dev-someuser}-prior"}]}
JSON
    exit 0
fi

if [ "\$method" = "POST" ] && [[ "\$url" == *"/branches" ]]; then
    cat > "\$out_file" <<JSON
{
  "branch": {"id": "br-new-fake", "name": "fake"},
  "connection_uris": [
    {
      "connection_uri": "postgresql://user:pass@host/db?sslmode=require",
      "connection_uri_pooled": "postgresql://user:pass@host-pooler/db?sslmode=require"
    }
  ]
}
JSON
    echo -n "201"
    exit 0
fi

if [ "\$method" = "DELETE" ] && [[ "\$url" == *"/branches/"* ]]; then
    echo -n "204"
    exit 0
fi

# Unhandled — fail loud
echo "TEST STUB: unhandled curl call: method=\$method url=\$url" >&2
exit 1
EOF
    chmod +x "$tmp/bin/curl"
}

assert_contains() {
    local needle="$1" file="$2" label="$3"
    if grep -q "$needle" "$file"; then
        echo -e "  ${GREEN}✓${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $label  (looking for: $needle)"
        FAIL=$((FAIL + 1))
    fi
}

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then
        echo -e "  ${GREEN}✓${NC} $label"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $label  (expected: $expected; got: $actual)"
        FAIL=$((FAIL + 1))
    fi
}

# ── Test 1: env vars missing → exits 2 with clear message ───────────────

echo ""
echo "Test 1: missing env vars rejected with helpful message"

T1=$(new_tmp)
make_stubs "$T1"

set +e
PATH="$T1/bin:$PATH" \
    NEON_API_KEY="" NEON_PROJECT_ID="" \
    bash "$SCRIPT" > "$T1/stdout.log" 2> "$T1/stderr.log"
exit_code=$?
set -e

assert_eq "2" "$exit_code" "exits 2 when env vars unset"
assert_contains "NEON_API_KEY and NEON_PROJECT_ID must be set" "$T1/stderr.log" "error names both required vars"
assert_contains "docs/LOCAL-DEV.md" "$T1/stderr.log" "error points at LOCAL-DEV.md"

# ── Test 2: create mode posts to branches endpoint with right body ──────

echo ""
echo "Test 2: create mode POSTs branch creation with parent_id resolved"

T2=$(new_tmp)
make_stubs "$T2"

set +e
PATH="$T2/bin:$PATH" \
    NEON_API_KEY="fake-key" \
    NEON_PROJECT_ID="proj-test" \
    DEV_BRANCH_PREFIX="dev-tester" \
    ENV_FILE="$T2/.env" \
    SKIP_MIGRATE="1" \
    bash "$SCRIPT" > "$T2/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "exits 0 on successful create"
# Two curl invocations expected: GET parent-branch list + POST creation.
# Count via line-prefix since the stub logs each call as `curl <args>` and
# the POST body's multi-line JSON inflates a naive line count.
calls=$(grep -c '^curl ' "$T2/curl.log")
assert_eq "2" "$calls" "exactly 2 curl invocations (GET parent + POST create)"
assert_contains "POST" "$T2/curl.log" "POST called (branch creation)"
assert_contains "/projects/proj-test/branches" "$T2/curl.log" "URL targets the right project"

# ── Test 3: writes .env with DATABASE_URL extracted from response ───────

echo ""
echo "Test 3: writes ENV_FILE with DATABASE_URL=<pooled url from response>"

# T2 already ran; verify its .env
assert_contains "DATABASE_URL=postgresql://user:pass@host-pooler" "$T2/.env" "ENV_FILE contains pooled URL"
assert_contains "# Branch: dev-tester-" "$T2/.env" "ENV_FILE comment names the branch"
assert_contains "# Teardown:" "$T2/.env" "ENV_FILE comment includes teardown reminder"
# Verify the URL is NOT echoed to stdout
if grep -q "host-pooler" "$T2/stdout.log"; then
    echo -e "  ${RED}✗${NC} pooled URL leaked to stdout (security: don't log secrets)"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}✓${NC} pooled URL not echoed to stdout (secret hygiene)"
    PASS=$((PASS + 1))
fi

# ── Test 4: --teardown deletes matching branches ────────────────────────

echo ""
echo "Test 4: --teardown deletes branches matching DEV_BRANCH_PREFIX-*"

T4=$(new_tmp)
make_stubs "$T4"
# Pre-create a fake .env to verify teardown removes it
echo "DATABASE_URL=postgresql://stale" > "$T4/.env"

set +e
PATH="$T4/bin:$PATH" \
    NEON_API_KEY="fake-key" \
    NEON_PROJECT_ID="proj-test" \
    DEV_BRANCH_PREFIX="dev-someuser" \
    ENV_FILE="$T4/.env" \
    bash "$SCRIPT" --teardown > "$T4/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "teardown exits 0"
# Stub returns one branch named dev-someuser-prior matching the prefix
assert_contains "DELETE" "$T4/curl.log" "DELETE called for matching branch"
assert_contains "br-existing-fake" "$T4/curl.log" "deleted the right branch ID"
if [ -f "$T4/.env" ]; then
    echo -e "  ${RED}✗${NC} ENV_FILE still exists after teardown"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}✓${NC} ENV_FILE removed by teardown"
    PASS=$((PASS + 1))
fi

# ── Test 5: idempotent teardown — second run finds nothing, exits 0 ─────

echo ""
echo "Test 5: idempotent teardown — re-running with no matching branches exits 0"

T5=$(new_tmp)
mkdir -p "$T5/bin"
# Custom stub: GET returns ZERO matching branches (no prefix match)
cat > "$T5/bin/curl" <<EOF
#!/usr/bin/env bash
echo "curl \$*" >> "$T5/curl.log"
method="GET"
prev=""
for arg in "\$@"; do
    case "\$prev" in -X) method="\$arg"; prev="" ;; esac
    case "\$arg" in -X) prev="\$arg" ;; esac
done
if [ "\$method" = "GET" ]; then
    echo '{"branches":[{"id":"br-main","name":"main"},{"id":"br-other","name":"unrelated"}]}'
fi
exit 0
EOF
chmod +x "$T5/bin/curl"

set +e
PATH="$T5/bin:$PATH" \
    NEON_API_KEY="fake-key" \
    NEON_PROJECT_ID="proj-test" \
    DEV_BRANCH_PREFIX="dev-nonexistent" \
    ENV_FILE="$T5/.env" \
    bash "$SCRIPT" --teardown > "$T5/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "teardown exits 0 when no matching branches"
assert_contains "No matching branches to delete" "$T5/stdout.log" "reports nothing to delete cleanly"
# Verify NO DELETE call was made
if grep -q "DELETE" "$T5/curl.log"; then
    echo -e "  ${RED}✗${NC} DELETE called despite no matching branches"
    FAIL=$((FAIL + 1))
else
    echo -e "  ${GREEN}✓${NC} no DELETE call when nothing to delete"
    PASS=$((PASS + 1))
fi

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
