#!/usr/bin/env bash
#
# provision-workshop-roster.sh — multi-project provisioning from a CSV roster.
#
# Wraps scripts/provision-gcp-project.sh for workshop facilitators who need
# to provision N participant projects in one command.
#
# Usage:
#   BILLING_ACCOUNT_ID=XXX-XXXX-XXXX ./scripts/provision-workshop-roster.sh roster.csv
#   BILLING_ACCOUNT_ID=XXX ./scripts/provision-workshop-roster.sh roster.csv --force-shared-parent
#
# Required environment variables:
#   BILLING_ACCOUNT_ID   The GCP billing account to attach each project to
#
# Optional flags:
#   --force-shared-parent    Pass NEON_FORCE_SHARED_PARENT=true to the inner
#                            script. By default, an existing Neon branch with
#                            a roster handle's name causes the inner script
#                            to fail with an actionable error (#90 — prevents
#                            silent cross-contamination). Set this flag to
#                            opt back into the previous silent-reuse behavior
#                            for paired collaboration or re-running an existing
#                            cohort against a still-populated Neon project.
#   --workshop-org=<org>     (#107) When set, creates each attendee's repo
#                            under <org> via `gh repo create <org>/<handle>
#                            --template <WORKSHOP_TEMPLATE_REPO> --public`
#                            BEFORE calling the inner provisioner. Overrides
#                            each row's github_full_repo to <org>/<handle>
#                            (so WIF binding and secret pushes target the
#                            workshop-org repo, not the attendee's personal
#                            account). Also forwards WIF_ORG_TRUST_PATTERN=
#                            <org> to the inner script so a single WIF SA
#                            binding covers every attendee repo. Equivalent
#                            env var: WORKSHOP_ORG.
#
# Optional environment variables:
#   GCP_REGION           (default: us-central1) — passed through to inner script
#   ARTIFACT_REPO        (default: agile-flow)  — passed through to inner script
#   PROVISION_SCRIPT     (default: scripts/provision-gcp-project.sh) — for tests
#   NEON_API_KEY         optional; forwarded to inner script for branch creation
#   NEON_PROJECT_ID      optional; forwarded to inner script for branch creation
#   NEON_FORCE_SHARED_PARENT  same effect as --force-shared-parent above; the
#                            flag sets this env var on the inner script
#   BUDGET_CAP_USD       optional; forwarded to inner script for Step 5.6
#                        (per-project billing budget). Default for workshop
#                        usage is 25.
#   WORKSHOP_ORG         (#107) Same effect as --workshop-org=<org> above.
#                        When unset (default), the wrapper assumes attendee
#                        forks already exist on personal accounts (legacy
#                        behavior).
#   WORKSHOP_TEMPLATE_REPO (default: vibeacademy/agile-flow-gcp) The template
#                        repo `gh repo create --template` uses when
#                        WORKSHOP_ORG is set. Override for non-vibeacademy
#                        forks of the framework.
#   GH_REPO_CREATE       (default: gh) Path to the gh binary used for
#                        --workshop-org's `gh repo create` call. Tests
#                        override to a stub.
#
# CSV format (header required, accepts 4, 5, 6, or 7 columns):
#   handle,github_user,email,cohort
#   alice,alice-gh,alice@example.com,2026-05
#   bob,bob-gh,bob@example.com,2026-05
#
#   handle,github_user,email,cohort,neon_branch        (5-column variant)
#   alice,alice-gh,alice@example.com,2026-05,alice
#   bob,bob-gh,bob@example.com,2026-05,bob_personal    (explicit branch override)
#
#   handle,github_user,email,cohort,neon_branch,github_full_repo   (6-column)
#   alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice
#   bob,bob-gh,bob@acme.com,2026-05,bob,acme/widget-shop
#   carol,carol-gh,carol@example.com,2026-05,carol,                (defaults)
#
#   handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id (7)
#   alice,alice-gh,alice@acme.com,2026-05,alice,acme/agile-flow-alice,proj-alice-123
#   bob,bob-gh,bob@acme.com,2026-05,bob,acme/widget-shop,proj-bob-456
#
# In the 7-column variant, the per-row `neon_project_id` overrides the
# cohort-level NEON_PROJECT_ID env var. This enables the per-attendee
# Neon project model (#108) — populate the column via
# `scripts/create-workshop-neon-projects.sh` before running this wrapper.
# Empty `neon_project_id` falls back to the env var (cohort-shared model).
#
# When the optional `neon_branch` column is empty or absent, NEON_BRANCH_NAME
# defaults to the row's `handle`. Use the override when the same person needs
# a stable Neon branch across cohorts (different `cohort` value, same branch).
#
# When the optional `github_full_repo` column is empty or absent,
# defaults to `<github_user>/agile-flow-gcp`. Use the override when
# attendees fork into an org and rename the repo to fit their product.
# The wrapper splits the value at the slash and exports GITHUB_OWNER and
# GITHUB_REPO to the inner script.
#
# Project IDs follow the pattern  af-{handle}-{cohort}  and are globally
# unique. This is non-negotiable: the runbook, day-1 doc, and dry-run
# checklist all assume this shape.
#
# Side effects per row:
#   1. Calls provision-gcp-project.sh --create-project (idempotent)
#   2. Grants roles/editor on the new project to the participant's email
#   3. Appends a row to roster-output.csv with status + project ID
#
# This script is fail-fast: the loop stops on the first row that errors,
# so a half-provisioned classroom does not silently happen.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVISION_SCRIPT="${PROVISION_SCRIPT:-$REPO_ROOT/scripts/provision-gcp-project.sh}"
OUTPUT_CSV="${OUTPUT_CSV:-roster-output.csv}"

# ── Argument parsing ─────────────────────────────────────────────────────

ROSTER_CSV=""
FORCE_SHARED_PARENT="${NEON_FORCE_SHARED_PARENT:-false}"
WORKSHOP_ORG="${WORKSHOP_ORG:-}"
WORKSHOP_TEMPLATE_REPO="${WORKSHOP_TEMPLATE_REPO:-vibeacademy/agile-flow-gcp}"
GH_REPO_CREATE="${GH_REPO_CREATE:-gh}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-shared-parent)
      FORCE_SHARED_PARENT=true
      shift
      ;;
    --workshop-org=*)
      WORKSHOP_ORG="${1#--workshop-org=}"
      shift
      ;;
    --workshop-org)
      WORKSHOP_ORG="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '1,80p' "$0"
      exit 0
      ;;
    --*)
      echo "ERROR: unknown flag: $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$ROSTER_CSV" ]]; then
        echo "ERROR: multiple positional arguments; expected exactly one (the roster CSV)" >&2
        exit 2
      fi
      ROSTER_CSV="$1"
      shift
      ;;
  esac
done

if [[ -z "$ROSTER_CSV" ]]; then
  cat >&2 <<EOF
Usage: BILLING_ACCOUNT_ID=XXX ./scripts/provision-workshop-roster.sh <roster.csv> [--force-shared-parent]

See header of $0 for full documentation.
EOF
  exit 2
fi

if [[ ! -f "$ROSTER_CSV" ]]; then
  echo "ERROR: roster file not found: $ROSTER_CSV" >&2
  exit 2
fi

if [[ -z "${BILLING_ACCOUNT_ID:-}" ]]; then
  echo "ERROR: BILLING_ACCOUNT_ID is required" >&2
  exit 2
fi

if [[ ! -x "$PROVISION_SCRIPT" ]]; then
  echo "ERROR: inner provision script not executable: $PROVISION_SCRIPT" >&2
  exit 2
fi

# ── Bot-account collaborator grants (#140) ───────────────────────────────
#
# When AGILE_FLOW_WORKER_ACCOUNT or AGILE_FLOW_REVIEWER_ACCOUNT are set
# (multi-bot mode) and WORKSHOP_ORG is also set, grant push access to
# each configured bot on every newly-provisioned attendee repo. Without
# this, /bootstrap-workflow blocks at the first push because the active
# bot account is read-only on freshly-created attendee repos under
# vibeacademy/<handle>.
#
# Idempotent: skips silently when the bot already has write or higher.
# Skipped entirely when env vars are unset (solo-mode compatibility).
# Fail-soft: a single failed grant does NOT abort the roster loop.
#
# Requires the bot account to be authenticated locally
# (`gh auth login --user <bot>` — what setup-accounts.sh sets up). If
# the bot is not authed, the invite is issued but not accepted; a clear
# WARN tells the facilitator how to recover manually.

grant_push_to_attendee() {
  local repo="$1" github_user="$2"

  if [[ -z "$github_user" ]]; then
    echo "  WARN: github_user is empty — skipping attendee push grant for $repo" >&2
    return 1
  fi

  # Idempotency check: already a collaborator with write or higher?
  local current_perm
  current_perm=$(gh api "repos/$repo/collaborators/$github_user/permission" --jq '.permission' 2>/dev/null || echo "none")
  if [[ "$current_perm" == "write" || "$current_perm" == "admin" || "$current_perm" == "maintain" ]]; then
    echo "  [skip] $github_user already has $current_perm on $repo"
    return 0
  fi

  # Issue the invite. The attendee must accept manually — we cannot auth
  # as them locally, and auto-accepting on their behalf would cross a
  # permission boundary. Attendee accepts via email link or from inside
  # their Codespace: gh api PATCH /user/repository_invitations/<id>
  if ! gh api -X PUT "repos/$repo/collaborators/$github_user" -f permission=push >/dev/null 2>&1; then
    echo "  WARN: failed to invite $github_user to $repo (continuing)"
    return 1
  fi
  echo "  [invite] $github_user invited to $repo with push (attendee must accept)"
}

grant_project_writer_to_attendee() {
  local repo="$1" github_user="$2" project_node_id="$3"

  if [[ -z "$project_node_id" ]]; then
    return 0
  fi
  if [[ -z "$github_user" ]]; then
    echo "  WARN: github_user is empty — skipping project-board grant for $repo" >&2
    return 1
  fi

  # Resolve the attendee's GitHub user node ID (needed for the GraphQL mutation).
  local user_node_id
  user_node_id=$(gh api "users/$github_user" --jq '.node_id' 2>/dev/null || echo "")
  if [[ -z "$user_node_id" ]]; then
    echo "  WARN: could not resolve node_id for $github_user — skipping project grant"
    return 1
  fi

  # Grant WRITER on the project board. The mutation is idempotent — re-adding an
  # existing collaborator at the same role returns the project node without error.
  if ! gh api graphql -f query="
    mutation {
      updateProjectV2Collaborators(input: {
        projectId: \"$project_node_id\"
        collaborators: [{ userId: \"$user_node_id\", role: WRITER }]
      }) { project { id } }
    }" >/dev/null 2>&1; then
    echo "  WARN: failed to grant project WRITER to $github_user on project $project_node_id (continuing)"
    return 1
  fi
  echo "  [project] $github_user granted WRITER on project $project_node_id"
}

grant_push_to_bot() {
  local repo="$1" bot="$2"

  # Idempotency check: already a collaborator with write or higher?
  local current_perm
  current_perm=$(gh api "repos/$repo/collaborators/$bot/permission" --jq '.permission' 2>/dev/null || echo "none")
  if [[ "$current_perm" == "write" || "$current_perm" == "admin" || "$current_perm" == "maintain" ]]; then
    echo "  [skip] $bot already has $current_perm on $repo"
    return 0
  fi

  # Issue the invite. Facilitator's gh token must have admin write on the org.
  if ! gh api -X PUT "repos/$repo/collaborators/$bot" -f permission=push >/dev/null 2>&1; then
    echo "  WARN: failed to invite $bot to $repo (continuing)"
    return 1
  fi
  echo "  [invite] $bot invited to $repo with push"

  # Accept the invite as the bot. Requires the bot to be authenticated
  # locally — bot accounts get authed via setup-accounts.sh.
  local original_user
  original_user=$(gh api user --jq '.login' 2>/dev/null || echo "")

  if ! gh auth switch --user "$bot" >/dev/null 2>&1; then
    echo "  WARN: $bot not authenticated locally — invite issued but NOT accepted"
    echo "        Run 'gh auth login --user $bot' on the facilitator machine, then re-run this script"
    [[ -n "$original_user" ]] && gh auth switch --user "$original_user" >/dev/null 2>&1
    return 1
  fi

  local invite_id
  invite_id=$(gh api /user/repository_invitations --jq ".[] | select(.repository.full_name == \"$repo\") | .id" 2>/dev/null | head -1)
  if [[ -n "$invite_id" ]]; then
    if gh api -X PATCH "/user/repository_invitations/$invite_id" >/dev/null 2>&1; then
      echo "  [accept] $bot accepted invite to $repo"
    else
      echo "  WARN: $bot failed to accept invite $invite_id to $repo"
    fi
  fi

  [[ -n "$original_user" ]] && gh auth switch --user "$original_user" >/dev/null 2>&1
}

# ── CSV header validation ────────────────────────────────────────────────
#
# The roster format accepts two header shapes:
#   1. handle,github_user,email,cohort               (4 columns, original)
#   2. handle,github_user,email,cohort,neon_branch   (5 columns, with Neon
#                                                     branch override)
#
# When the 5th column is present and non-empty for a row, NEON_BRANCH_NAME
# takes that value. Otherwise it defaults to the row's `handle` — which
# matches the GCP project ID's handle component, so attendee branches are
# named alice / bob / etc. by default.

EXPECTED_HEADER_4="handle,github_user,email,cohort"
EXPECTED_HEADER_5="handle,github_user,email,cohort,neon_branch"
EXPECTED_HEADER_6="handle,github_user,email,cohort,neon_branch,github_full_repo"
EXPECTED_HEADER_7="handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id"
EXPECTED_HEADER_8="handle,github_user,email,cohort,neon_branch,github_full_repo,neon_project_id,project_id"
ACTUAL_HEADER="$(head -n 1 "$ROSTER_CSV" | tr -d '\r')"

if [[ "$ACTUAL_HEADER" != "$EXPECTED_HEADER_4" \
   && "$ACTUAL_HEADER" != "$EXPECTED_HEADER_5" \
   && "$ACTUAL_HEADER" != "$EXPECTED_HEADER_6" \
   && "$ACTUAL_HEADER" != "$EXPECTED_HEADER_7" \
   && "$ACTUAL_HEADER" != "$EXPECTED_HEADER_8" ]]; then
  echo "ERROR: roster CSV header must be one of:" >&2
  echo "       $EXPECTED_HEADER_4" >&2
  echo "       $EXPECTED_HEADER_5" >&2
  echo "       $EXPECTED_HEADER_6" >&2
  echo "       $EXPECTED_HEADER_7" >&2
  echo "       $EXPECTED_HEADER_8" >&2
  echo "       got: $ACTUAL_HEADER" >&2
  exit 2
fi

# ── Neon pre-flight: hard-fail before any GCP work if neon_project_id missing ──
#
# Enforce when the facilitator clearly intends Neon: NEON_API_KEY is set.
# In that case every 7-column row must have a non-empty neon_project_id so
# Step 5.7 can create the per-attendee branch secret. A missing ID means
# create-workshop-neon-projects.sh was not run yet; failing here (before any
# GCP projects are created) avoids half-provisioned classrooms that look green
# but fail on the first PR deploy. (Surfaced: 2026-05-05 dry run.)
#
# 4/5/6-column rosters are skipped by the check — they have no neon_project_id
# column and handle the missing-Neon case elsewhere.

if [[ -n "${NEON_API_KEY:-}" && "$ACTUAL_HEADER" == "$EXPECTED_HEADER_7" ]]; then
  neon_check_row=0
  while IFS=',' read -r _h _gu _em _co _nb _gfr _npid; do
    _h="$(echo "$_h" | tr -d '[:space:]\r')"
    _npid="$(echo "${_npid:-}" | tr -d '[:space:]\r')"
    [[ -z "$_h" ]] && continue
    neon_check_row=$((neon_check_row + 1))
    if [[ -z "$_npid" ]]; then
      echo "[fail] Row $neon_check_row (handle=$_h) has empty neon_project_id but NEON_API_KEY is set." >&2
      echo "       Run scripts/create-workshop-neon-projects.sh $ROSTER_CSV first to" >&2
      echo "       create per-attendee Neon projects, then re-run this script." >&2
      exit 2
    fi
  done < <(tail -n +2 "$ROSTER_CSV")
fi

# ── Output CSV setup ─────────────────────────────────────────────────────

if [[ ! -f "$OUTPUT_CSV" ]]; then
  echo "handle,project_id,status,wif_provider,timestamp" > "$OUTPUT_CSV"
fi

# ── Counters ─────────────────────────────────────────────────────────────

total=0
created=0
skipped=0

# ── Loop ─────────────────────────────────────────────────────────────────

# tail -n +2 skips header. Process substitution avoids subshell so counters
# survive into the summary block.
#
# We read 8 fields. 4–7-column rows leave the trailing fields empty;
# the default-fallback logic below covers them.
while IFS=',' read -r handle github_user email cohort neon_branch github_full_repo row_neon_project_id row_project_id; do
  # Strip whitespace and CR (Windows line endings)
  handle="$(echo "$handle" | tr -d '[:space:]\r')"
  github_user="$(echo "$github_user" | tr -d '[:space:]\r')"
  email="$(echo "$email" | tr -d '[:space:]\r')"
  cohort="$(echo "$cohort" | tr -d '[:space:]\r')"
  neon_branch="$(echo "${neon_branch:-}" | tr -d '[:space:]\r')"
  github_full_repo="$(echo "${github_full_repo:-}" | tr -d '[:space:]\r')"
  row_neon_project_id="$(echo "${row_neon_project_id:-}" | tr -d '[:space:]\r')"
  row_project_id="$(echo "${row_project_id:-}" | tr -d '[:space:]\r')"

  if [[ -z "$handle" || -z "$cohort" ]]; then
    continue
  fi

  # Default neon_branch to handle when not explicitly set per row.
  if [[ -z "$neon_branch" ]]; then
    neon_branch="$handle"
  fi

  # Validate Neon branch name: 1-63 chars, alphanumeric + hyphen + underscore.
  # Reject anything else fail-fast on this row, since the inner script's
  # Neon API call would error mid-loop with a less-clear message.
  if ! [[ "$neon_branch" =~ ^[A-Za-z0-9_-]{1,63}$ ]]; then
    echo "ERROR: invalid neon_branch '$neon_branch' for handle '$handle'" >&2
    echo "       must be 1-63 chars, alphanumeric + hyphen + underscore only" >&2
    exit 2
  fi

  # Workshop-org-hosted mode (#107): when WORKSHOP_ORG is set, override
  # github_full_repo to <org>/<handle> regardless of what the CSV said.
  # This is the canonical path for the May 2026 workshop architecture
  # — attendee repos live under the workshop org, not under personal
  # accounts. The CSV's github_full_repo field is preserved for non-
  # workshop-org modes (and for documentation purposes if the facilitator
  # wants to record it).
  if [[ -n "$WORKSHOP_ORG" ]]; then
    github_full_repo="${WORKSHOP_ORG}/${handle}"
  fi

  # Default github_full_repo to "<github_user>/agile-flow-gcp" when not set.
  # That preserves today's behavior for personal-fork participants.
  if [[ -z "$github_full_repo" ]]; then
    github_full_repo="${github_user}/agile-flow-gcp"
  fi

  # Validate <owner>/<repo> shape. GitHub owner: alphanumeric + hyphens
  # (1-39 chars). Repo: alphanumeric + dot + hyphen + underscore (1-100).
  # Strict check rejects empty fragments, double slashes, leading/trailing
  # whitespace (already stripped above), etc.
  if ! [[ "$github_full_repo" =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]]; then
    echo "ERROR: invalid github_full_repo '$github_full_repo' for handle '$handle'" >&2
    echo "       must be <owner>/<repo> with allowed chars only" >&2
    exit 2
  fi

  # Split into owner and repo for env-var passthrough.
  github_owner="${github_full_repo%%/*}"
  github_repo="${github_full_repo##*/}"

  total=$((total + 1))
  project_id="af-${handle}-${cohort}"
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  echo ""
  echo "──────────────────────────────────────────────────"
  echo "  [$total] $handle  ->  $project_id"
  echo "──────────────────────────────────────────────────"

  # Workshop-org-hosted mode (#107): create the attendee's repo under
  # the workshop org from the template. Idempotent — `gh repo create`
  # exits non-zero if the repo already exists; we check first via
  # `gh repo view` to label honestly. This step requires the facilitator's
  # gh token to have admin write on the workshop org.
  if [[ -n "$WORKSHOP_ORG" ]]; then
    if "$GH_REPO_CREATE" repo view "${github_full_repo}" >/dev/null 2>&1; then
      echo "[skip] repo ${github_full_repo} already exists"
    else
      echo "[create] repo ${github_full_repo} from template ${WORKSHOP_TEMPLATE_REPO}"
      # NOTE: --include-all-branches is intentionally OMITTED (#129).
      # gh repo create --template starts the new repo's main as a fresh
      # single commit (the template's main history is squashed). If we
      # also copy template branches, those branches retain their pre-
      # squash history and share ZERO commits with the new main —
      # GitHub's compare view reports "entirely different commit
      # histories" and any "create PR from this branch" attempt errors.
      # Default behavior (no --include-all-branches) creates only main,
      # which is what attendees actually need for a fresh workshop start.
      if ! "$GH_REPO_CREATE" repo create "${github_full_repo}" \
        --template "${WORKSHOP_TEMPLATE_REPO}" \
        --public >/dev/null; then
        echo "ERROR: failed to create repo ${github_full_repo}" >&2
        echo "       The facilitator's gh token must have admin write on the org." >&2
        exit 1
      fi
    fi

    # Grant push to bot accounts (#140). Skipped silently when env vars
    # are unset (solo-mode compatibility). Fail-soft per row.
    if [[ -n "${AGILE_FLOW_WORKER_ACCOUNT:-}" ]]; then
      grant_push_to_bot "$github_full_repo" "$AGILE_FLOW_WORKER_ACCOUNT" || true
    fi
    if [[ -n "${AGILE_FLOW_REVIEWER_ACCOUNT:-}" ]]; then
      grant_push_to_bot "$github_full_repo" "$AGILE_FLOW_REVIEWER_ACCOUNT" || true
    fi

    # Grant push to the attendee themselves (#165). Attendee must accept the
    # invite manually (email link or Codespace: gh api PATCH /user/repository_invitations/<id>).
    grant_push_to_attendee "$github_full_repo" "$github_user" || true

    # Grant project board WRITER to the attendee (#166). Only fires when the
    # 8-column roster has a non-empty project_id for this row. Fail-soft.
    grant_project_writer_to_attendee "$github_full_repo" "$github_user" "${row_project_id:-}" || true
  fi

  # Detect whether the project already exists, so we can label the output
  # row honestly. The inner script is idempotent either way, so this is
  # purely for the summary CSV.
  if gcloud projects describe "$project_id" >/dev/null 2>&1; then
    status="skipped"
    skipped=$((skipped + 1))
  else
    status="created"
    created=$((created + 1))
  fi

  # Run the inner provisioner. It handles "already exists" internally;
  # we just pass through the env it needs.
  #
  # GITHUB_OWNER + GITHUB_REPO together enable WIF setup (Step 5.5).
  # Together they identify the GitHub repo whose Actions runs are
  # trusted to impersonate the deployer SA. Empty owner skips the step.
  # GITHUB_USERNAME is also exported as a legacy alias of GITHUB_OWNER
  # for any external caller still relying on that env-var name.
  #
  # NEON_BRANCH_NAME enables the Neon-branch-per-attendee step (5.7).
  # NEON_API_KEY and NEON_PROJECT_ID are forwarded only if set; the
  # inner script skips Step 5.7 when either is missing.
  #
  # Per-row override (#108): when the 7-column roster has a non-empty
  # neon_project_id, use it for THIS attendee instead of the cohort
  # env var. Falls back to the env var when the cell is empty (5/6-col
  # rosters and 7-col rows with no project assigned yet). This is what
  # enables the per-attendee Neon project model — each attendee's
  # project ID is their own.
  effective_neon_project_id="${row_neon_project_id:-${NEON_PROJECT_ID:-}}"

  # Workshop-org-hosted mode (#107): forward WIF_ORG_TRUST_PATTERN=
  # $WORKSHOP_ORG so the inner script's Step 5.5 sets up an org-trusted
  # WIF binding (one binding for the whole org instead of per-repo).
  effective_wif_org_trust="${WIF_ORG_TRUST_PATTERN:-${WORKSHOP_ORG:-}}"

  GCP_PROJECT_ID="$project_id" \
  BILLING_ACCOUNT_ID="$BILLING_ACCOUNT_ID" \
  GCP_REGION="${GCP_REGION:-us-central1}" \
  ARTIFACT_REPO="${ARTIFACT_REPO:-agile-flow}" \
  GITHUB_OWNER="$github_owner" \
  GITHUB_REPO="$github_repo" \
  GITHUB_USERNAME="$github_user" \
  GITHUB_REPOSITORY="$github_full_repo" \
  WIF_ORG_TRUST_PATTERN="$effective_wif_org_trust" \
  NEON_BRANCH_NAME="$neon_branch" \
  NEON_API_KEY="${NEON_API_KEY:-}" \
  NEON_PROJECT_ID="$effective_neon_project_id" \
  NEON_FORCE_SHARED_PARENT="$FORCE_SHARED_PARENT" \
  BUDGET_CAP_USD="${BUDGET_CAP_USD:-}" \
    "$PROVISION_SCRIPT" --create-project

  # Grant the participant editor on their own project. Idempotent.
  echo ""
  echo "[bind] roles/editor -> user:$email"
  gcloud projects add-iam-policy-binding "$project_id" \
    --member="user:$email" \
    --role="roles/editor" \
    --condition=None \
    --quiet >/dev/null

  # WIF provider resource path. The inner script's Step 5.5 created the
  # pool + provider when GITHUB_USERNAME was non-empty; record the canonical
  # resource string for the summary CSV so the facilitator can paste it
  # straight into participant fork secrets.
  wif_provider=""
  if [[ -n "$github_user" ]]; then
    project_number="$(gcloud projects describe "$project_id" --format='value(projectNumber)' 2>/dev/null || true)"
    if [[ -n "$project_number" ]]; then
      wif_provider="projects/${project_number}/locations/global/workloadIdentityPools/github/providers/github"
    fi
  fi

  echo "$handle,$project_id,$status,$wif_provider,$timestamp" >> "$OUTPUT_CSV"
done < <(tail -n +2 "$ROSTER_CSV")

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "=================================="
echo "  Workshop provisioning summary"
echo "=================================="
echo "  Total rows processed:   $total"
echo "  Newly created:          $created"
echo "  Already existed:        $skipped"
echo "  Failed:                 0   (script is fail-fast — see above for any error)"
echo ""
echo "  Output: $OUTPUT_CSV"
echo "  Next:   set up WIF (manually or via #5) and send each participant"
echo "          their setup email per docs/PLATFORM-GUIDE.md."
