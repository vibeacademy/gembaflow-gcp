#!/usr/bin/env bash
# install-evidence-page.sh — bring the per-PR evidence-page capability into
# an existing fork of agile-flow-gcp.
#
# New forks of the framework get this for free — the runtime ships in the
# template's app/ scaffolding. This script exists for forks that predate
# the evidence-page branch and need to catch up without waiting for an
# upstream rebase.
#
# What it does:
#   1. Verifies it's running in an agile-flow-gcp-shaped repo and not on
#      `main` (we never commit directly to main).
#   2. Skips cleanly if the runtime is already installed (idempotent).
#   3. Fetches the runtime files from this framework branch via curl:
#        - app/evidence.py
#        - app/api/evidence.py
#        - app/evidence_integration.py
#        - templates/evidence.html
#        - tests/test_evidence.py
#   4. Appends the evidence-page CSS block to static/style.css (only if
#      the marker comment is absent).
#   5. Adds a single-line opt-in to app/main.py:
#        from app.evidence_integration import attach_evidence_routes
#        attach_evidence_routes(app)
#      The call is injected after the last `app.include_router(...)`
#      line. It is preview-only at runtime, so production behavior is
#      unchanged.
#   6. Runs a smoke test (`uv run python -c 'import app.main'`) to
#      confirm app/main.py still imports cleanly. The installer exits
#      non-zero if it doesn't — installing into a state that breaks
#      `uvicorn app.main:app` would be worse than not installing.
#   7. Prints next-steps for testing and committing.
#
# Configuration (env vars):
#   AGILE_FLOW_REF  — git ref to fetch files from. Defaults to `main`,
#                     which is correct after #170 merges. During the
#                     transition window, set to
#                     `feature/issue-170-evidence-pages`.
#   AGILE_FLOW_REPO — owner/repo to fetch from. Default vibeacademy/agile-flow-gcp.
#
# Tracked in vibeacademy/agile-flow-gcp#170.

set -euo pipefail

REPO="${AGILE_FLOW_REPO:-vibeacademy/agile-flow-gcp}"
REF="${AGILE_FLOW_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${REF}"

color_red() { printf '\033[31m%s\033[0m\n' "$*"; }
color_green() { printf '\033[32m%s\033[0m\n' "$*"; }
color_yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
info() { printf '→ %s\n' "$*"; }
fail() { color_red "✗ $*" >&2; exit 1; }

# --- Preflight -----------------------------------------------------------

[[ -d .git ]] || fail "Run this from the root of your agile-flow-gcp fork (no .git here)."
[[ -f pyproject.toml ]] || fail "No pyproject.toml — does not look like an agile-flow-gcp fork."
[[ -f app/main.py ]] || fail "app/main.py missing — does not look like an agile-flow-gcp fork."

current_branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$current_branch" == "main" ]]; then
  fail "You're on main. Create a feature branch first:
    git checkout -b feature/install-evidence-page"
fi

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required."
fi

info "Fetching from ${REPO}@${REF}"

# --- Idempotency check ---------------------------------------------------

if [[ -f app/evidence.py && -f app/api/evidence.py && -f app/evidence_integration.py ]]; then
  if grep -q "attach_evidence_routes" app/main.py; then
    color_green "✓ Evidence runtime already installed (runtime files present and app/main.py wires them up)."
    info "Nothing to do. If you want to refresh files from upstream, delete them first."
    exit 0
  fi
fi

# --- Fetch helper --------------------------------------------------------

fetch() {
  # fetch <remote-relative-path> <local-path>
  local remote="$1" local_path="$2"
  mkdir -p "$(dirname "$local_path")"
  if ! curl -fsSL "${RAW_BASE}/${remote}" -o "$local_path"; then
    fail "Could not fetch ${remote} from ${REPO}@${REF}.
Check that AGILE_FLOW_REF is set correctly and that the branch exists."
  fi
  info "wrote $local_path"
}

# --- Copy runtime files --------------------------------------------------

fetch app/evidence.py app/evidence.py
fetch app/api/evidence.py app/api/evidence.py
fetch app/evidence_integration.py app/evidence_integration.py
fetch templates/evidence.html templates/evidence.html
fetch tests/test_evidence.py tests/test_evidence.py

# --- Append CSS block (idempotent) ---------------------------------------

CSS_MARKER="/* Evidence page (preview-only) */"
if [[ -f static/style.css ]] && grep -qF "$CSS_MARKER" static/style.css; then
  info "skipped static/style.css (already contains evidence-page block)"
else
  tmp_css=$(mktemp)
  curl -fsSL "${RAW_BASE}/static/style.css" -o "$tmp_css" || fail "Could not fetch static/style.css"
  if [[ -f static/style.css ]]; then
    # Append only the evidence-page section (everything from the marker onward).
    start_line=$(grep -nF "$CSS_MARKER" "$tmp_css" | head -1 | cut -d: -f1)
    if [[ -z "$start_line" ]]; then
      fail "Upstream static/style.css is missing the '${CSS_MARKER}' marker — installer needs an update."
    fi
    # Insert a leading blank line so the appended block doesn't run into existing rules.
    printf '\n' >> static/style.css
    tail -n "+${start_line}" "$tmp_css" >> static/style.css
    info "appended evidence-page block to static/style.css"
  else
    cp "$tmp_css" static/style.css
    info "wrote static/style.css"
  fi
  rm -f "$tmp_css"
fi

# --- Wire app/main.py ----------------------------------------------------
#
# Add one import + one call to app/main.py. We inject after the last
# `app.include_router(...)` line so the helper sees the user's full
# router set when reordering routes. The call itself is preview-only at
# runtime, so production behavior is unchanged.

if grep -q "attach_evidence_routes" app/main.py; then
  info "skipped app/main.py (already calls attach_evidence_routes)"
else
  ts=$(date +%Y%m%d-%H%M%S)
  backup="app/main.py.bak.${ts}"
  cp app/main.py "$backup"
  info "backed up existing app/main.py → ${backup}"

  # Find the last "app.include_router(" line. Allow leading whitespace
  # (some forks indent under a factory) but require the variable to be
  # `app` — anything else is too custom for a one-line injection.
  last_router_line=$(grep -nE "^[[:space:]]*app\.include_router\(" app/main.py | tail -1 | cut -d: -f1 || true)

  if [[ -z "$last_router_line" ]]; then
    color_yellow "! Could not find an 'app.include_router(...)' call in app/main.py."
    info "The installer needs that anchor to know where to attach evidence routes."
    info "Add these two lines manually after your router setup, then re-run the installer:"
    echo
    echo "    from app.evidence_integration import attach_evidence_routes"
    echo "    attach_evidence_routes(app)"
    echo
    fail "Aborted: no injection anchor in app/main.py (backup at ${backup})."
  fi

  # Inject:
  #   - the import after the existing imports section (before any code)
  #   - the call after the last include_router line
  awk -v inject_line="$last_router_line" '
    BEGIN { import_done = 0 }
    {
      print
      # Insert import once, after the first non-import block ends.
      # Specifically: after the last "from app." or "import app." line at
      # the top of the file, the next non-comment, non-blank, non-import
      # line is where we slot it in. We approximate by injecting just
      # before the first non-import, non-blank, non-comment line.
    }
  ' app/main.py > /dev/null  # placeholder for awk syntax check

  # Build the new file in two passes: first add the call, then add the import.
  tmp_main=$(mktemp)
  awk -v inject_line="$last_router_line" '
    { print }
    NR == inject_line {
      print ""
      print "attach_evidence_routes(app)"
    }
  ' app/main.py > "$tmp_main"

  # Add the import. Find a sensible spot: after the last existing
  # `from app.` or `import` line in the top-of-file imports block. If we
  # cannot find one, prepend.
  last_import_line=$(awk '
    /^(from |import )/ { last = NR }
    !/^(from |import |#|[[:space:]]*$|""")/ && last { exit }
    END { print last }
  ' "$tmp_main")

  tmp_main2=$(mktemp)
  if [[ -n "$last_import_line" ]]; then
    awk -v line="$last_import_line" '
      { print }
      NR == line {
        print "from app.evidence_integration import attach_evidence_routes"
      }
    ' "$tmp_main" > "$tmp_main2"
  else
    {
      echo "from app.evidence_integration import attach_evidence_routes"
      cat "$tmp_main"
    } > "$tmp_main2"
  fi

  mv "$tmp_main2" app/main.py
  rm -f "$tmp_main"
  info "injected attach_evidence_routes import + call into app/main.py"
fi

# --- Smoke test ----------------------------------------------------------
#
# Confirm that app/main.py imports cleanly. If it doesn't, the install
# left the user in a worse state than it found them — refuse to declare
# success.

info "running post-install smoke test (importing app.main)..."
smoke_log=$(mktemp)
if uv run --quiet python -c "import app.main" 2>"$smoke_log"; then
  info "✓ app/main.py imports cleanly"
  rm -f "$smoke_log"
else
  echo
  color_red "✗ Smoke test failed — app/main.py does not import cleanly."
  echo "Output:"
  cat "$smoke_log"
  rm -f "$smoke_log"
  echo
  info "The most common cause is an unconventional app/main.py shape that"
  info "the installer's regex injection didn't handle. Inspect the diff:"
  echo
  echo "    git diff app/main.py"
  echo
  info "and adjust by hand. The two lines that must be present are:"
  echo
  echo "    from app.evidence_integration import attach_evidence_routes"
  echo "    attach_evidence_routes(app)"
  echo
  fail "Aborted: app/main.py does not import."
fi

# --- Done ----------------------------------------------------------------

echo
color_green "✓ Evidence-page runtime installed."
cat <<'NEXT'

Next steps:

  1. Run the test suite to confirm nothing regressed:

       uv run pytest

     You should see test_evidence.py contributing several new passing tests.

  2. Review the changes:

       git status
       git diff

  3. Commit and open a PR per your normal workflow:

       git add app/ templates/ static/ tests/
       git commit -m "feat(evidence): install per-PR evidence page"
       git push -u origin HEAD

  4. After the preview deploy succeeds, hit /healthz/evidence on the
     preview URL to confirm the framework starter sections probe green
     against PostgreSQL.

  See docs/EVIDENCE-PAGES.md for the full model and how to add a section
  per acceptance criterion in future PRs.

NEXT
