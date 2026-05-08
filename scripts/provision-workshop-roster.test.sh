#!/usr/bin/env bash
#
# Tests for provision-workshop-roster.sh
#
# Stubs `gcloud` and the inner provisioner via PATH injection + env override
# so we can assert behavior without touching real GCP.
#
# Run: ./scripts/provision-workshop-roster.test.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_ROOT/scripts/provision-workshop-roster.sh"

# Each test runs in a fresh tmpdir to keep output CSVs isolated.
new_tmp() {
  mktemp -d -t aflowtest-XXXX
}

# Build a fake gcloud + provision-gcp-project.sh in $tmp/bin and prepend to PATH.
#   $1: tmpdir
#   $2: behavior — "ok", "skip-first" (project exists for first row), or "fail"
make_stubs() {
  local tmp="$1"
  local behavior="$2"
  mkdir -p "$tmp/bin"

  # Fake gcloud
  cat > "$tmp/bin/gcloud" <<EOF
#!/usr/bin/env bash
# Log every invocation to a file so the test can assert on it.
echo "gcloud \$*" >> "$tmp/gcloud.log"

case "\$1" in
  projects)
    case "\$2" in
      describe)
        # describe <project_id>
        if [[ "$behavior" == "skip-first" && "\$3" == af-alice-* ]]; then
          exit 0  # alice's project "exists"
        fi
        exit 1    # default: project does not exist
        ;;
      add-iam-policy-binding)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF

  # Fake inner provisioner
  cat > "$tmp/bin/provision-gcp-project.sh" <<EOF
#!/usr/bin/env bash
# Log every invocation along with the env vars the wrapper is supposed
# to forward. Tests grep this log to verify per-row env passthrough.
echo "provision \$* GCP_PROJECT_ID=\${GCP_PROJECT_ID:-} GITHUB_USERNAME=\${GITHUB_USERNAME:-} GITHUB_OWNER=\${GITHUB_OWNER:-} GITHUB_REPO=\${GITHUB_REPO:-} GITHUB_REPOSITORY=\${GITHUB_REPOSITORY:-} WIF_ORG_TRUST_PATTERN=\${WIF_ORG_TRUST_PATTERN:-} NEON_BRANCH_NAME=\${NEON_BRANCH_NAME:-} NEON_PROJECT_ID=\${NEON_PROJECT_ID:-}" >> "$tmp/provision.log"

if [[ "$behavior" == "fail" ]]; then
  echo "fake provision failure" >&2
  exit 1
fi
exit 0
EOF

  chmod +x "$tmp/bin/gcloud" "$tmp/bin/provision-gcp-project.sh"
}

write_roster() {
  local path="$1"
  cat > "$path" <<'EOF'
handle,github_user,email,cohort
alice,alice-gh,alice@example.com,2026-05
bob,bob-gh,bob@example.com,2026-05
EOF
}

assert_contains() {
  local needle="$1"
  local haystack_file="$2"
  local label="$3"
  if grep -q "$needle" "$haystack_file"; then
    echo -e "  ${GREEN}✓${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $label  (looking for: $needle in $haystack_file)"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓${NC} $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $label  (expected: $expected; got: $actual)"
    FAIL=$((FAIL + 1))
  fi
}

# ── Test 1: Happy path — both rows attempted, output CSV correct ─────────

echo ""
echo "Test 1: Happy path with 2-row roster"

T1=$(new_tmp)
make_stubs "$T1" "ok"
write_roster "$T1/roster.csv"

set +e
PATH="$T1/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T1/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T1/roster-output.csv" \
  "$WRAPPER" "$T1/roster.csv" > "$T1/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0"
assert_eq "2" "$(grep -c '^provision' "$T1/provision.log")" "inner provisioner called twice"
assert_contains "alice,af-alice-2026-05,created" "$T1/roster-output.csv" "alice row recorded as created"
assert_contains "bob,af-bob-2026-05,created" "$T1/roster-output.csv" "bob row recorded as created"
assert_contains "Total rows processed:   2" "$T1/stdout.log" "summary shows 2 rows"

# ── Test 2: Idempotent re-run — both rows show "skipped" ─────────────────

echo ""
echo "Test 2: Idempotent re-run (project already exists for both rows)"

T2=$(new_tmp)
# Custom stub: gcloud projects describe always succeeds (project exists)
mkdir -p "$T2/bin"
cat > "$T2/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$T2/gcloud.log"
case "\$1 \$2" in
  "projects describe") exit 0 ;;  # always exists
  "projects add-iam-policy-binding") exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "$T2/bin/provision-gcp-project.sh" <<EOF
#!/usr/bin/env bash
echo "provision \$* GCP_PROJECT_ID=\${GCP_PROJECT_ID:-}" >> "$T2/provision.log"
exit 0
EOF
chmod +x "$T2/bin/gcloud" "$T2/bin/provision-gcp-project.sh"

write_roster "$T2/roster.csv"

set +e
PATH="$T2/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T2/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T2/roster-output.csv" \
  "$WRAPPER" "$T2/roster.csv" > "$T2/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 on re-run"
assert_contains "alice,af-alice-2026-05,skipped" "$T2/roster-output.csv" "alice row recorded as skipped"
assert_contains "bob,af-bob-2026-05,skipped" "$T2/roster-output.csv" "bob row recorded as skipped"
assert_contains "Already existed:        2" "$T2/stdout.log" "summary shows 2 skipped"

# ── Test 3: Fail-fast — first row fails, second row never attempted ─────

echo ""
echo "Test 3: Fail-fast on first-row error"

T3=$(new_tmp)
make_stubs "$T3" "fail"
write_roster "$T3/roster.csv"

set +e
PATH="$T3/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T3/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T3/roster-output.csv" \
  "$WRAPPER" "$T3/roster.csv" > "$T3/stdout.log" 2>&1
exit_code=$?
set -e

if [[ "$exit_code" -ne 0 ]]; then
  echo -e "  ${GREEN}✓${NC} wrapper exits non-zero on inner failure (got $exit_code)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} wrapper should fail on inner script failure (got 0)"
  FAIL=$((FAIL + 1))
fi
assert_eq "1" "$(grep -c '^provision' "$T3/provision.log")" "inner provisioner called only once before exit"

# ── Test 4: Bad CSV header rejected ──────────────────────────────────────

echo ""
echo "Test 4: Bad CSV header is rejected"

T4=$(new_tmp)
make_stubs "$T4" "ok"
cat > "$T4/roster.csv" <<EOF
name,email
alice,alice@example.com
EOF

set +e
PATH="$T4/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T4/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T4/roster-output.csv" \
  "$WRAPPER" "$T4/roster.csv" > "$T4/stdout.log" 2>&1
exit_code=$?
set -e

if [[ "$exit_code" -eq 2 ]]; then
  echo -e "  ${GREEN}✓${NC} wrapper exits 2 on bad header"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} wrapper should exit 2 on bad header (got $exit_code)"
  FAIL=$((FAIL + 1))
fi
assert_contains "header must be one of" "$T4/stdout.log" "error message mentions header format"

# ── Test 5: Missing BILLING_ACCOUNT_ID rejected ─────────────────────────

echo ""
echo "Test 5: Missing BILLING_ACCOUNT_ID is rejected"

T5=$(new_tmp)
make_stubs "$T5" "ok"
write_roster "$T5/roster.csv"

set +e
PATH="$T5/bin:$PATH" \
  PROVISION_SCRIPT="$T5/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T5/roster-output.csv" \
  "$WRAPPER" "$T5/roster.csv" > "$T5/stdout.log" 2>&1
exit_code=$?
set -e

if [[ "$exit_code" -eq 2 ]]; then
  echo -e "  ${GREEN}✓${NC} wrapper exits 2 when BILLING_ACCOUNT_ID is unset"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} wrapper should exit 2 when BILLING_ACCOUNT_ID is unset (got $exit_code)"
  FAIL=$((FAIL + 1))
fi

# ── Test 6: 5-column header + neon_branch column passes through ─────────
# Verifies that:
#   - 5-column header is accepted
#   - NEON_BRANCH_NAME is exported per row from the 5th column
#   - When the 5th column is empty for a row, defaults to handle

echo ""
echo "Test 6: 5-column header forwards NEON_BRANCH_NAME"

T6=$(new_tmp)
make_stubs "$T6" "ok"
cat > "$T6/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,
bob,bob-gh,bob@example.com,2026-05,bob_personal
EOF

set +e
PATH="$T6/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T6/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T6/roster-output.csv" \
  "$WRAPPER" "$T6/roster.csv" > "$T6/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 5-column header"
# alice row should default neon_branch to handle (empty 5th column → handle)
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*NEON_BRANCH_NAME=alice" "$T6/provision.log" "alice row defaults NEON_BRANCH_NAME to handle"
# bob row uses the explicit override
assert_contains "GCP_PROJECT_ID=af-bob-2026-05.*NEON_BRANCH_NAME=bob_personal" "$T6/provision.log" "bob row uses explicit neon_branch override"

# ── Test 7: 4-column header still works (NEON_BRANCH_NAME defaults) ─────

echo ""
echo "Test 7: 4-column header still works (defaults NEON_BRANCH_NAME to handle)"

T7=$(new_tmp)
make_stubs "$T7" "ok"
write_roster "$T7/roster.csv"

set +e
PATH="$T7/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T7/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T7/roster-output.csv" \
  "$WRAPPER" "$T7/roster.csv" > "$T7/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 4-column header"
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*NEON_BRANCH_NAME=alice" "$T7/provision.log" "alice defaults to handle (4-column)"
assert_contains "GCP_PROJECT_ID=af-bob-2026-05.*NEON_BRANCH_NAME=bob" "$T7/provision.log" "bob defaults to handle (4-column)"

# ── Test 8: invalid neon_branch value fails fast ────────────────────────

echo ""
echo "Test 8: invalid neon_branch fails the row fast"

T8=$(new_tmp)
make_stubs "$T8" "ok"
cat > "$T8/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,bad branch with spaces
EOF

set +e
PATH="$T8/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T8/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T8/roster-output.csv" \
  "$WRAPPER" "$T8/roster.csv" > "$T8/stdout.log" 2>&1
exit_code=$?
set -e

# Note: 'bad branch with spaces' → after whitespace stripping → 'badbranchwithspaces'
# which actually IS valid alphanumeric. Use a value that's invalid even after stripping.
# Re-write with a value containing $ (definitely invalid).
cat > "$T8/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch
alice,alice-gh,alice@example.com,2026-05,bad\$value
EOF

set +e
PATH="$T8/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T8/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T8/roster-output.csv" \
  "$WRAPPER" "$T8/roster.csv" > "$T8/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "2" "$exit_code" "wrapper exits 2 on invalid neon_branch"
assert_contains "invalid neon_branch" "$T8/stdout.log" "error message names the field"

# ── Test 9: 6-column header + explicit github_full_repo passes through ──
#
# Verifies that:
#   - 6-column header is accepted
#   - github_full_repo splits at slash; owner+repo exported separately
#   - alice's row uses an org owner (acme); bob's row uses a different owner

echo ""
echo "Test 9: 6-column header forwards GITHUB_OWNER + GITHUB_REPO"

T9=$(new_tmp)
make_stubs "$T9" "ok"
cat > "$T9/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice
bob,bob-gh,bob@acme.com,2026-05,bob,acme/widget-shop
EOF

set +e
PATH="$T9/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T9/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T9/roster-output.csv" \
  "$WRAPPER" "$T9/roster.csv" > "$T9/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 6-column header"
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*GITHUB_OWNER=acme.*GITHUB_REPO=agile-flow-alice" "$T9/provision.log" "alice row exports acme owner + alice repo"
assert_contains "GCP_PROJECT_ID=af-bob-2026-05.*GITHUB_OWNER=acme.*GITHUB_REPO=widget-shop" "$T9/provision.log" "bob row exports acme owner + widget-shop repo"

# ── Test 10: empty github_full_repo defaults to <github_user>/agile-flow-gcp ──

echo ""
echo "Test 10: empty github_full_repo defaults to <github_user>/agile-flow-gcp"

T10=$(new_tmp)
make_stubs "$T10" "ok"
cat > "$T10/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
carol,carol-gh,carol@example.com,2026-05,carol,
EOF

set +e
PATH="$T10/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T10/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T10/roster-output.csv" \
  "$WRAPPER" "$T10/roster.csv" > "$T10/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with empty github_full_repo"
assert_contains "GITHUB_OWNER=carol-gh.*GITHUB_REPO=agile-flow-gcp" "$T10/provision.log" "defaults to <github_user>/agile-flow-gcp"

# ── Test 11: invalid github_full_repo fails fast ────────────────────────

echo ""
echo "Test 11: invalid github_full_repo fails the row fast"

T11=$(new_tmp)
make_stubs "$T11" "ok"
# Use a value with double slash, which the regex rejects.
cat > "$T11/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@acme.com,2026-05,alice,acme//bad-repo
EOF

set +e
PATH="$T11/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T11/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T11/roster-output.csv" \
  "$WRAPPER" "$T11/roster.csv" > "$T11/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "2" "$exit_code" "wrapper exits 2 on invalid github_full_repo"
assert_contains "invalid github_full_repo" "$T11/stdout.log" "error message names the field"

# ── Test 12: 4-column legacy roster — github_full_repo defaults work ────

echo ""
echo "Test 12: 4-column header still works (defaults github_full_repo)"

T12=$(new_tmp)
make_stubs "$T12" "ok"
write_roster "$T12/roster.csv"  # 4-column

set +e
PATH="$T12/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T12/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T12/roster-output.csv" \
  "$WRAPPER" "$T12/roster.csv" > "$T12/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 4-column header"
# alice/bob should both default to <user>/agile-flow-gcp
assert_contains "GITHUB_OWNER=alice-gh.*GITHUB_REPO=agile-flow-gcp" "$T12/provision.log" "alice defaults to alice-gh/agile-flow-gcp"
assert_contains "GITHUB_OWNER=bob-gh.*GITHUB_REPO=agile-flow-gcp" "$T12/provision.log" "bob defaults to bob-gh/agile-flow-gcp"

# ── Summary ──────────────────────────────────────────────────────────────

# ── Test 13: 7-column header accepted; per-row neon_project_id forwarded ──
#
# #108: workshop facilitators populate the 7th column via
# create-workshop-neon-projects.sh before running this wrapper. The
# wrapper must accept the 7-column header and forward each row's
# neon_project_id as NEON_PROJECT_ID to the inner script (per-row,
# not from cohort env).

echo ""
echo "Test 13: 7-column header forwards per-row NEON_PROJECT_ID"

T13=$(new_tmp)
make_stubs "$T13" "ok"
cat > "$T13/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id
alice,alice-gh,alice@x.com,2026-05,alice,vibeacademy/alice,proj-alice-aaa
bob,bob-gh,bob@x.com,2026-05,bob,vibeacademy/bob,proj-bob-bbb
EOF

set +e
PATH="$T13/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T13/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T13/roster-output.csv" \
  "$WRAPPER" "$T13/roster.csv" > "$T13/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 7-column header"
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*NEON_PROJECT_ID=proj-alice-aaa" "$T13/provision.log" "alice forwards her per-row project ID"
assert_contains "GCP_PROJECT_ID=af-bob-2026-05.*NEON_PROJECT_ID=proj-bob-bbb" "$T13/provision.log" "bob forwards his per-row project ID"

# ── Test 14: empty per-row neon_project_id falls back to cohort env var ──
#
# Backwards-compat: rows with empty neon_project_id (or 5/6-column rosters)
# fall back to the cohort-level NEON_PROJECT_ID env var. This preserves
# the shared-project model for non-workshop-org-hosted setups.

echo ""
echo "Test 14: empty per-row neon_project_id falls back to NEON_PROJECT_ID env"

T14=$(new_tmp)
make_stubs "$T14" "ok"
cat > "$T14/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id
alice,alice-gh,alice@x.com,2026-05,alice,vibeacademy/alice,proj-alice-aaa
carol,carol-gh,carol@x.com,2026-05,carol,vibeacademy/carol,
EOF

set +e
PATH="$T14/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  NEON_PROJECT_ID="cohort-shared-proj-zzz" \
  PROVISION_SCRIPT="$T14/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T14/roster-output.csv" \
  "$WRAPPER" "$T14/roster.csv" > "$T14/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with mixed per-row IDs"
# alice: per-row value wins
assert_contains "GCP_PROJECT_ID=af-alice-2026-05.*NEON_PROJECT_ID=proj-alice-aaa" "$T14/provision.log" "alice's per-row ID overrides env var"
# carol: empty per-row → fallback to env var
assert_contains "GCP_PROJECT_ID=af-carol-2026-05.*NEON_PROJECT_ID=cohort-shared-proj-zzz" "$T14/provision.log" "carol's empty per-row falls back to env var"

# ── Test 15: 6-column roster + cohort env var still forwards env var ─────
#
# Backwards-compat regression guard: 4/5/6-column rosters never had a
# neon_project_id column. The wrapper must continue to forward the
# cohort env var for them, exactly as before.

echo ""
echo "Test 15: 6-column roster forwards cohort NEON_PROJECT_ID env var"

T15=$(new_tmp)
make_stubs "$T15" "ok"
cat > "$T15/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@x.com,2026-05,alice,vibeacademy/alice
EOF

set +e
PATH="$T15/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  NEON_PROJECT_ID="cohort-shared-proj-zzz" \
  PROVISION_SCRIPT="$T15/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T15/roster-output.csv" \
  "$WRAPPER" "$T15/roster.csv" > "$T15/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 6-column header (regression guard)"
assert_contains "NEON_PROJECT_ID=cohort-shared-proj-zzz" "$T15/provision.log" "6-column row forwards cohort env var unchanged"

# ── Test 16: --workshop-org creates repos under the org + overrides github_full_repo
#
# #107: when --workshop-org is set, the wrapper:
#   - calls `gh repo create $org/$handle --template ... --public` per row
#   - overrides github_full_repo to $org/$handle (regardless of CSV value)
#   - forwards WIF_ORG_TRUST_PATTERN=$org to the inner provisioner
#
# The gh stub here logs every call so we can assert on both the create
# call AND that the inner provisioner saw the right env vars.

echo ""
echo "Test 16: --workshop-org creates repos and overrides github_full_repo"

T16=$(new_tmp)
make_stubs "$T16" "ok"

# gh stub: log every call; `repo view` returns 1 (repo doesn't exist)
# so the wrapper falls through to `repo create`.
cat > "$T16/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T16/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T16/bin/gh"

cat > "$T16/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo
alice,alice-gh,alice@x.com,2026-05,alice,personal-acme/foo
bob,bob-gh,bob@x.com,2026-05,bob,
EOF

set +e
PATH="$T16/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T16/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T16/roster-output.csv" \
  GH_REPO_CREATE="$T16/bin/gh" \
  "$WRAPPER" "$T16/roster.csv" --workshop-org=vibeacademy > "$T16/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with --workshop-org"
# Each row should have a `gh repo create vibeacademy/<handle>` call
assert_contains "gh repo create vibeacademy/alice" "$T16/gh.log" "alice repo created under vibeacademy"
assert_contains "gh repo create vibeacademy/bob" "$T16/gh.log" "bob repo created under vibeacademy"
# Each create call must include --public (not --private). Use grep -F
# directly so the leading -- isn't interpreted as a grep flag.
if grep -qF -- "--public" "$T16/gh.log"; then
  echo -e "  ${GREEN}✓${NC} repo create includes --public flag"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} expected --public in repo create call"
  FAIL=$((FAIL + 1))
fi
# Regression guard (#129): --include-all-branches must NOT be present.
# That flag copies template branches verbatim while gh squashes the
# template's main into a fresh single commit, leaving the template
# branches with no common ancestor — GitHub's compare view reports
# "entirely different commit histories" and PR creation fails.
if grep -q "include-all-branches" "$T16/gh.log"; then
  echo -e "  ${RED}✗${NC} --include-all-branches still present in gh repo create (#129 regression)"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} --include-all-branches correctly absent (only main is copied; #129)"
  PASS=$((PASS + 1))
fi
# github_full_repo was overridden — alice's CSV said personal-acme/foo
# but the inner script should see vibeacademy/alice
assert_contains "GITHUB_REPOSITORY=vibeacademy/alice" "$T16/provision.log" "alice's github_full_repo overridden to vibeacademy/alice"
assert_contains "GITHUB_REPOSITORY=vibeacademy/bob" "$T16/provision.log" "bob's github_full_repo overridden to vibeacademy/bob"
# WIF_ORG_TRUST_PATTERN forwarded
assert_contains "WIF_ORG_TRUST_PATTERN=vibeacademy" "$T16/provision.log" "WIF_ORG_TRUST_PATTERN forwarded"
# Personal-acme value from CSV is NOT used
if grep -q "GITHUB_REPOSITORY=personal-acme" "$T16/provision.log"; then
  echo -e "  ${RED}✗${NC} CSV's personal-acme/foo leaked despite --workshop-org override"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} CSV's personal-acme/foo correctly suppressed by --workshop-org"
  PASS=$((PASS + 1))
fi

# ── Test 17: --workshop-org skips create when repo already exists ──────
#
# Idempotency: facilitator re-runs the provisioner; each repo should
# be detected as existing (via `gh repo view`) and the create call
# skipped.

echo ""
echo "Test 17: --workshop-org skips repo create when repo already exists"

T17=$(new_tmp)
make_stubs "$T17" "ok"

# gh stub: `repo view` returns 0 (repo exists) → `repo create` should NOT be called
cat > "$T17/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T17/gh.log"
case "\$1 \$2" in
  "repo view") exit 0 ;;
  "repo create") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T17/bin/gh"

cat > "$T17/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T17/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T17/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T17/roster-output.csv" \
  GH_REPO_CREATE="$T17/bin/gh" \
  "$WRAPPER" "$T17/roster.csv" --workshop-org=vibeacademy > "$T17/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 on idempotent re-run"
assert_contains "gh repo view vibeacademy/alice" "$T17/gh.log" "repo view called"
assert_contains "repo vibeacademy/alice already exists" "$T17/stdout.log" "skip message printed"
# Critical: gh repo create must NOT have been called
if grep -q "repo create" "$T17/gh.log"; then
  echo -e "  ${RED}✗${NC} gh repo create called despite repo existing"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} gh repo create NOT called when repo exists (idempotent)"
  PASS=$((PASS + 1))
fi

# ── Test 18: WORKSHOP_ORG env var works (equivalent to --workshop-org=) ──

echo ""
echo "Test 18: WORKSHOP_ORG env var works (equivalent to --workshop-org=)"

T18=$(new_tmp)
make_stubs "$T18" "ok"

cat > "$T18/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T18/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T18/bin/gh"

cat > "$T18/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T18/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T18/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T18/roster-output.csv" \
  GH_REPO_CREATE="$T18/bin/gh" \
  WORKSHOP_ORG="my-workshop-org" \
  "$WRAPPER" "$T18/roster.csv" > "$T18/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with WORKSHOP_ORG env var"
assert_contains "gh repo create my-workshop-org/alice" "$T18/gh.log" "repo created under env var org"
assert_contains "GITHUB_REPOSITORY=my-workshop-org/alice" "$T18/provision.log" "github_full_repo overridden via env var"

# ── Test 19: Without --workshop-org, NO gh repo create call (regression guard)
#
# Backwards-compat: legacy mode (no --workshop-org, no WORKSHOP_ORG env)
# must NOT make any `gh repo create` calls. Attendee forks already
# exist on personal accounts.

echo ""
echo "Test 19: legacy mode (no --workshop-org) does not call gh repo create"

T19=$(new_tmp)
make_stubs "$T19" "ok"

cat > "$T19/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T19/gh.log"
exit 0
EOF
chmod +x "$T19/bin/gh"

cat > "$T19/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T19/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T19/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T19/roster-output.csv" \
  GH_REPO_CREATE="$T19/bin/gh" \
  "$WRAPPER" "$T19/roster.csv" > "$T19/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 in legacy mode"
# gh.log should be empty (no calls at all) since the wrapper doesn't use gh in legacy mode
if [[ -f "$T19/gh.log" ]] && grep -q "." "$T19/gh.log"; then
  echo -e "  ${RED}✗${NC} gh was called in legacy mode (regression — no calls expected)"
  cat "$T19/gh.log"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} gh not called in legacy mode (regression guard)"
  PASS=$((PASS + 1))
fi
# WIF_ORG_TRUST_PATTERN should be empty in legacy mode
assert_contains "WIF_ORG_TRUST_PATTERN= " "$T19/provision.log" "WIF_ORG_TRUST_PATTERN empty in legacy mode"

# ── Test 20: WORKSHOP_TEMPLATE_REPO override is forwarded ──────────────

echo ""
echo "Test 20: WORKSHOP_TEMPLATE_REPO override flows into gh repo create"

T20=$(new_tmp)
make_stubs "$T20" "ok"

cat > "$T20/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T20/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T20/bin/gh"

cat > "$T20/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T20/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T20/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T20/roster-output.csv" \
  GH_REPO_CREATE="$T20/bin/gh" \
  WORKSHOP_TEMPLATE_REPO="myfork/agile-flow-gcp" \
  "$WRAPPER" "$T20/roster.csv" --workshop-org=vibeacademy > "$T20/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0"
assert_contains "template myfork/agile-flow-gcp" "$T20/gh.log" "custom template forwarded"

# ── Test 21: bot accounts get push grants when env vars are set (#140) ──
#
# When AGILE_FLOW_WORKER_ACCOUNT and AGILE_FLOW_REVIEWER_ACCOUNT are set
# AND --workshop-org is in use, the wrapper should:
#   - Check current permission for each bot (idempotency probe)
#   - Issue PUT collaborators invite for each bot (since stub returns "none")
#   - Switch to each bot to accept the invite
#   - PATCH /user/repository_invitations/<id> to accept
#   - Switch back to facilitator

echo ""
echo "Test 21: bot accounts get push grants when env vars are set (#140)"

T21=$(new_tmp)
make_stubs "$T21" "ok"

# gh stub: handles the full bot-grant flow.
#   - repo view returns 1 (doesn't exist, so create runs)
#   - permission probe returns "none" (so PUT runs)
#   - api user returns "facilitator"
#   - auth switch succeeds
#   - repository_invitations returns one invite ID
cat > "$T21/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T21/gh.log"
case "\$*" in
  "repo view "*) exit 1 ;;
  "repo create "*) exit 0 ;;
  *"collaborators/"*"/permission"*) echo "none" ;;
  *"-X PUT repos/"*"collaborators/"*) exit 0 ;;
  "api user "*) echo "facilitator" ;;
  "auth switch --user "*) exit 0 ;;
  *"repository_invitations"*"--jq"*) echo "98765" ;;
  *"-X PATCH /user/repository_invitations/"*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T21/bin/gh"

cat > "$T21/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T21/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T21/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T21/roster-output.csv" \
  GH_REPO_CREATE="$T21/bin/gh" \
  AGILE_FLOW_WORKER_ACCOUNT="va-worker" \
  AGILE_FLOW_REVIEWER_ACCOUNT="va-reviewer" \
  "$WRAPPER" "$T21/roster.csv" --workshop-org=vibeacademy > "$T21/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with bot-grant env vars set"
# Permission probe ran for both bots
assert_contains "collaborators/va-worker/permission" "$T21/gh.log" "worker permission probed"
assert_contains "collaborators/va-reviewer/permission" "$T21/gh.log" "reviewer permission probed"
# PUT invite issued for both bots
assert_contains "PUT repos/vibeacademy/alice/collaborators/va-worker" "$T21/gh.log" "worker invited via PUT"
assert_contains "PUT repos/vibeacademy/alice/collaborators/va-reviewer" "$T21/gh.log" "reviewer invited via PUT"
# Auth switch + PATCH invite-accept happened for each bot
assert_contains "auth switch --user va-worker" "$T21/gh.log" "switched to worker bot"
assert_contains "auth switch --user va-reviewer" "$T21/gh.log" "switched to reviewer bot"
assert_contains "PATCH /user/repository_invitations/98765" "$T21/gh.log" "invite accepted via PATCH"

# ── Test 22: bot-grant skipped silently when env vars unset (solo mode) ──
#
# Solo-mode compatibility: when AGILE_FLOW_WORKER_ACCOUNT and
# AGILE_FLOW_REVIEWER_ACCOUNT are both unset, the wrapper must NOT
# attempt any collaborator/invitation API calls — solo-mode users have
# no bot accounts to invite.

echo ""
echo "Test 22: bot-grant skipped silently when env vars unset (solo mode)"

T22=$(new_tmp)
make_stubs "$T22" "ok"

cat > "$T22/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T22/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T22/bin/gh"

cat > "$T22/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
# Explicitly UNSET bot env vars (override anything in the parent env)
PATH="$T22/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T22/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T22/roster-output.csv" \
  GH_REPO_CREATE="$T22/bin/gh" \
  AGILE_FLOW_WORKER_ACCOUNT="" \
  AGILE_FLOW_REVIEWER_ACCOUNT="" \
  "$WRAPPER" "$T22/roster.csv" --workshop-org=vibeacademy > "$T22/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with bot env vars unset"
# repo create still runs (this is the workshop-org path)
assert_contains "gh repo create vibeacademy/alice" "$T22/gh.log" "repo create still runs"
# Attendee collaborator invite DOES happen (grant_push_to_attendee fires for the attendee's github_user)
assert_contains "collaborators/alice-gh" "$T22/gh.log" "attendee collaborator invite issued"
# But no BOT-specific collaborator calls (worker/reviewer env vars are unset)
if grep -q "collaborators/va-worker\|collaborators/va-reviewer" "$T22/gh.log"; then
  echo -e "  ${RED}✗${NC} bot collaborator calls made despite bot env vars unset"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} no bot collaborator API calls when bot env vars unset (solo-mode OK)"
  PASS=$((PASS + 1))
fi
if grep -q "repository_invitations" "$T22/gh.log"; then
  echo -e "  ${RED}✗${NC} repository_invitations API called despite bot env vars unset"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} no repository_invitations API calls when bot env vars unset"
  PASS=$((PASS + 1))
fi

# ── Test 23: bot-grant idempotent when bot already has push (#140) ──────
#
# Re-running provisioning on a roster row whose attendee repo already
# exists AND already has the bot as a write collaborator must be a
# no-op for the grant step — no duplicate PUT, no duplicate PATCH.

echo ""
echo "Test 23: bot-grant idempotent — skip PUT/PATCH when bot already has write"

T23=$(new_tmp)
make_stubs "$T23" "ok"

# gh stub: permission probe returns "write" → grant_push_to_bot returns early
cat > "$T23/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T23/gh.log"
case "\$*" in
  "repo view "*) exit 1 ;;
  "repo create "*) exit 0 ;;
  *"collaborators/"*"/permission"*) echo "write" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T23/bin/gh"

cat > "$T23/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T23/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T23/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T23/roster-output.csv" \
  GH_REPO_CREATE="$T23/bin/gh" \
  AGILE_FLOW_WORKER_ACCOUNT="va-worker" \
  AGILE_FLOW_REVIEWER_ACCOUNT="va-reviewer" \
  "$WRAPPER" "$T23/roster.csv" --workshop-org=vibeacademy > "$T23/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 on idempotent re-run"
# Permission probe DID run (that's how we detected the existing grant)
assert_contains "collaborators/va-worker/permission" "$T23/gh.log" "worker permission probed"
# But NO PUT or PATCH (those would mean we re-issued the invite)
if grep -q "PUT repos/.*collaborators" "$T23/gh.log"; then
  echo -e "  ${RED}✗${NC} PUT collaborators called despite existing write grant (not idempotent)"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} no PUT collaborators call when bot already has write (idempotent)"
  PASS=$((PASS + 1))
fi
if grep -q "PATCH /user/repository_invitations" "$T23/gh.log"; then
  echo -e "  ${RED}✗${NC} PATCH invitation called despite existing write grant"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} no PATCH invitation call when bot already has write"
  PASS=$((PASS + 1))
fi
# auth switch should also be skipped (no need to switch when we already returned 0 from grant)
if grep -q "auth switch --user va-" "$T23/gh.log"; then
  echo -e "  ${RED}✗${NC} auth switch called despite existing write grant"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} no auth switch when bot already has write (idempotent path early-returns)"
  PASS=$((PASS + 1))
fi

# ── Test 24: hard-fail when neon_project_id missing and NEON_API_KEY set ──
#
# #167: facilitator forgot to run create-workshop-neon-projects.sh first.
# The wrapper must exit 2 BEFORE creating any GCP projects, with a message
# pointing to the fix. Verified: no provision-gcp-project.sh is called.

echo ""
echo "Test 24: hard-fail when 7-column roster has empty neon_project_id and NEON_API_KEY set"

T24=$(new_tmp)
make_stubs "$T24" "ok"
cat > "$T24/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id
alice,alice-gh,alice@x.com,2026-05,alice,vibeacademy/alice,
bob,bob-gh,bob@x.com,2026-05,bob,vibeacademy/bob,proj-bob-bbb
EOF

set +e
PATH="$T24/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  NEON_API_KEY="neon-fake-key" \
  PROVISION_SCRIPT="$T24/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T24/roster-output.csv" \
  "$WRAPPER" "$T24/roster.csv" > "$T24/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "2" "$exit_code" "exits 2 on empty neon_project_id with NEON_API_KEY set"
assert_contains "empty neon_project_id" "$T24/stdout.log" "error message mentions empty neon_project_id"
assert_contains "create-workshop-neon-projects.sh" "$T24/stdout.log" "error message points to fix"
# Must not have called the provisioner (no GCP project creation)
if [[ ! -f "$T24/provision.log" ]]; then
  echo -e "  ${GREEN}✓${NC} no GCP provisioning attempted before failing"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}✗${NC} provisioner was called despite pre-flight failure"
  FAIL=$((FAIL + 1))
fi

# ── Test 25: legitimate skip — no NEON_API_KEY, no neon_project_id ────────
#
# #167: a cohort not using Neon at all. The 7-column roster has empty
# neon_project_id, but NEON_API_KEY is unset, so the pre-flight should
# pass silently and provisioning should succeed.

echo ""
echo "Test 25: no NEON_API_KEY set — empty neon_project_id is a legitimate skip"

T25=$(new_tmp)
make_stubs "$T25" "ok"
cat > "$T25/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id
alice,alice-gh,alice@x.com,2026-05,alice,vibeacademy/alice,
EOF

set +e
PATH="$T25/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T25/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T25/roster-output.csv" \
  "$WRAPPER" "$T25/roster.csv" > "$T25/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "exits 0 when NEON_API_KEY unset (no Neon intent)"
assert_contains "af-alice-2026-05" "$T25/stdout.log" "provisioning proceeds for alice"

# ── Test 26: attendee push-grant fires in workshop-org mode (#165) ────────
#
# grant_push_to_attendee() should be called for each row's github_user when
# WORKSHOP_ORG is set, issuing a PUT collaborators invite.

echo ""
echo "Test 26: attendee push-grant fires in workshop-org mode"

T26=$(new_tmp)
make_stubs "$T26" "ok"

cat > "$T26/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T26/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  "api graphql") echo '{"data":{"updateProjectV2Collaborators":{"project":{"id":"PVT_x"}}}}' ;;
  "api users/alice-gh") echo '{"node_id":"U_alice123"}' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T26/bin/gh"

cat > "$T26/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T26/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T26/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T26/roster-output.csv" \
  GH_REPO_CREATE="$T26/bin/gh" \
  "$WRAPPER" "$T26/roster.csv" --workshop-org=vibeacademy > "$T26/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0"
assert_contains "collaborators/alice-gh" "$T26/gh.log" "attendee invite PUT issued"
assert_contains "alice-gh invited" "$T26/stdout.log" "stdout confirms attendee invite"

# ── Test 27: attendee push-grant idempotent (#165) ────────────────────────
#
# When the attendee already has write/admin on the repo, the grant must be
# a no-op (no PUT issued).

echo ""
echo "Test 27: attendee push-grant idempotent — skip when already write"

T27=$(new_tmp)
make_stubs "$T27" "ok"

cat > "$T27/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T27/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  "api repos/vibeacademy/alice/collaborators/alice-gh/permission")
    echo "write"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T27/bin/gh"

cat > "$T27/roster.csv" <<EOF
handle,github_user,email,cohort
alice,alice-gh,alice@x.com,2026-05
EOF

set +e
PATH="$T27/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T27/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T27/roster-output.csv" \
  GH_REPO_CREATE="$T27/bin/gh" \
  "$WRAPPER" "$T27/roster.csv" --workshop-org=vibeacademy > "$T27/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 on idempotent run"
# idempotency: PUT collaborators must NOT be called when already write
if grep -q "PUT repos/vibeacademy/alice/collaborators/alice-gh" "$T27/gh.log"; then
  echo -e "  ${RED}✗${NC} PUT collaborators called despite attendee already having write"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} no PUT collaborators when attendee already has write (idempotent)"
  PASS=$((PASS + 1))
fi
assert_contains "alice-gh already has write" "$T27/stdout.log" "stdout confirms skip"

# ── Test 28: project board WRITER grant fires for 8-column roster (#166) ──
#
# When the roster includes a non-empty project_id column, the wrapper must
# call the GraphQL mutation to grant the attendee WRITER on their board.

echo ""
echo "Test 28: project-board WRITER grant fires for 8-column roster"

T28=$(new_tmp)
make_stubs "$T28" "ok"

cat > "$T28/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T28/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  "api graphql")
    echo '{"data":{"updateProjectV2Collaborators":{"project":{"id":"PVT_abc123"}}}}'
    ;;
  "api users/alice-gh") echo '{"node_id":"U_alice123"}' ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T28/bin/gh"

cat > "$T28/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id,project_id
alice,alice-gh,alice@x.com,2026-05,alice,vibeacademy/alice,proj-alice-aaa,PVT_abc123
EOF

set +e
PATH="$T28/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T28/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T28/roster-output.csv" \
  GH_REPO_CREATE="$T28/bin/gh" \
  "$WRAPPER" "$T28/roster.csv" --workshop-org=vibeacademy > "$T28/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 with 8-column roster"
assert_contains "api graphql" "$T28/gh.log" "GraphQL mutation invoked"
assert_contains "PVT_abc123" "$T28/gh.log" "project node ID appears in mutation"
assert_contains "granted WRITER" "$T28/stdout.log" "stdout confirms project WRITER grant"

# ── Test 29: project board grant skipped when project_id empty (#166) ─────
#
# Rows with empty project_id (7-column or 8-column with blank cell) must
# skip the GraphQL mutation — no API call, no error.

echo ""
echo "Test 29: project-board grant skipped when project_id empty"

T29=$(new_tmp)
make_stubs "$T29" "ok"

cat > "$T29/bin/gh" <<EOF
#!/usr/bin/env bash
echo "gh \$*" >> "$T29/gh.log"
case "\$1 \$2" in
  "repo view") exit 1 ;;
  "repo create") exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$T29/bin/gh"

cat > "$T29/roster.csv" <<EOF
handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id,project_id
alice,alice-gh,alice@x.com,2026-05,alice,vibeacademy/alice,proj-alice-aaa,
EOF

set +e
PATH="$T29/bin:$PATH" \
  BILLING_ACCOUNT_ID="FAKE-BILLING" \
  PROVISION_SCRIPT="$T29/bin/provision-gcp-project.sh" \
  OUTPUT_CSV="$T29/roster-output.csv" \
  GH_REPO_CREATE="$T29/bin/gh" \
  "$WRAPPER" "$T29/roster.csv" --workshop-org=vibeacademy > "$T29/stdout.log" 2>&1
exit_code=$?
set -e

assert_eq "0" "$exit_code" "wrapper exits 0 when project_id empty"
if grep -q "api graphql" "$T29/gh.log"; then
  echo -e "  ${RED}✗${NC} GraphQL mutation called despite empty project_id"
  FAIL=$((FAIL + 1))
else
  echo -e "  ${GREEN}✓${NC} no GraphQL mutation when project_id empty (legacy compat)"
  PASS=$((PASS + 1))
fi

echo ""
echo "─────────────────────────────────"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
