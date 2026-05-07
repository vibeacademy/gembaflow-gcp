#!/usr/bin/env bash
#
# Tests for install-evidence-page.sh.
#
# Stubs `curl` via PATH injection so the installer fetches files from
# the current checkout instead of GitHub raw — this means the test runs
# offline and against the version of the runtime that's about to ship.
#
# Stubs `uv` so the installer's smoke test (`uv run python -c 'import
# app.main'`) does not need a real Python env with FastAPI installed
# during the test. We separately assert that the resulting app/main.py
# is at least syntactically valid via `python -m py_compile`.
#
# Run: ./scripts/install-evidence-page.test.sh

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/install-evidence-page.sh"
REF="feature/issue-170-evidence-pages"

new_tmp() {
    mktemp -d -t aflowinstallevidence-XXXX
}

# Build a fake `curl` in $tmp/bin that resolves the raw.githubusercontent.com
# URLs the installer constructs back to the local checkout. The installer
# constructs URLs as $RAW_BASE/$path; the stub strips the known prefix.
make_curl_stub() {
    local tmp="$1"
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/curl" <<STUB
#!/usr/bin/env bash
url=""
out=""
prev=""
for a in "\$@"; do
    case "\$prev" in -o) out="\$a"; prev=""; continue ;; esac
    case "\$a" in -o) prev="\$a" ;; -fsSL|-f|-s|-S|-L) ;; *) url="\$a" ;; esac
done
base="https://raw.githubusercontent.com/vibeacademy/agile-flow-gcp/${REF}/"
path="\${url#\$base}"
src="${REPO_ROOT}/\$path"
if [[ ! -f "\$src" ]]; then
    echo "stub-curl 404 \$url" >&2
    exit 22
fi
if [[ -n "\$out" ]]; then cp "\$src" "\$out"; else cat "\$src"; fi
STUB
    chmod +x "$tmp/bin/curl"
}

# Stub `uv` so the smoke test does not require a real venv during tests.
# Always exits 0 — we cover smoke-test-failure separately by testing the
# no-anchor abort path before the smoke test runs.
make_uv_stub() {
    local tmp="$1"
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/uv" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$tmp/bin/uv"
}

# Build a minimal pre-evidence agile-flow-gcp-shaped fork in $1.
# Two routers (health, todos), matching the framework template.
make_fork() {
    local dir="$1"
    (
        cd "$dir" || exit 1
        git init -q
        git checkout -q -b feature/install-evidence
        cat > pyproject.toml <<'EOF'
[project]
name = "agile-flow-gcp"
version = "0.0.0"
EOF
        mkdir -p app/api templates static tests
        cat > app/main.py <<'EOF'
"""FastAPI application entrypoint."""
from pathlib import Path
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from app.api import health, todos

app = FastAPI(title="Agile Flow GCP")
STATIC_DIR = Path(__file__).parent.parent / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.include_router(health.router)
app.include_router(todos.router)
EOF
        cat > static/style.css <<'EOF'
.todo-item { display: flex; }
EOF
        git add -A
        git commit -q -m "init"
    )
}

# Build a divergent fork with 4 routers + middleware (shannon-shaped).
# This is the case that broke before the helper refactor.
make_divergent_fork() {
    local dir="$1"
    (
        cd "$dir" || exit 1
        git init -q
        git checkout -q -b feature/install-evidence
        cat > pyproject.toml <<'EOF'
[project]
name = "shannon"
version = "0.0.0"
EOF
        mkdir -p app/api templates static tests
        cat > app/main.py <<'EOF'
"""FastAPI application entrypoint — shannon-shaped (more than 2 routers)."""
from pathlib import Path
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from starlette.middleware.cors import CORSMiddleware
from app.api import health, scheduler, flagged, dashboard

app = FastAPI(title="Shannon")
STATIC_DIR = Path(__file__).parent.parent / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.add_middleware(CORSMiddleware, allow_origins=["*"])
app.include_router(health.router)
app.include_router(scheduler.router)
app.include_router(flagged.router)
app.include_router(dashboard.router)
EOF
        cat > static/style.css <<'EOF'
.dashboard { display: grid; }
EOF
        git add -A
        git commit -q -m "init"
    )
}

# Build a fork whose main.py has no `app.include_router(...)` anchor.
# The installer should refuse rather than guess where to inject.
make_anchorless_fork() {
    local dir="$1"
    (
        cd "$dir" || exit 1
        git init -q
        git checkout -q -b feature/install-evidence
        cat > pyproject.toml <<'EOF'
[project]
name = "weird"
version = "0.0.0"
EOF
        mkdir -p app/api templates static tests
        cat > app/main.py <<'EOF'
"""FastAPI application entrypoint — exotic shape with no router anchor."""
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
def home():
    return {"hello": "world"}
EOF
        git add -A
        git commit -q -m "init"
    )
}

run_installer() {
    local fork="$1"
    (
        cd "$fork" || exit 1
        PATH="$fork/bin:$PATH" AGILE_FLOW_REF="$REF" bash "$SCRIPT" 2>&1
    )
}

assert() {
    local label="$1" condition="$2"
    if eval "$condition"; then
        printf "${GREEN}PASS${NC} %s\n" "$label"
        PASS=$((PASS+1))
    else
        printf "${RED}FAIL${NC} %s\n" "$label"
        FAIL=$((FAIL+1))
    fi
}

# --- Test 1: vanilla install on a clean (template-shape) fork --------------

t1=$(new_tmp)
make_fork "$t1"
make_curl_stub "$t1"
make_uv_stub "$t1"
out1=$(run_installer "$t1")

assert "test1: installer reports success" "echo \"\$out1\" | grep -qF 'Evidence-page runtime installed.'"
assert "test1: app/evidence.py written" "[[ -f '$t1/app/evidence.py' ]]"
assert "test1: app/api/evidence.py written" "[[ -f '$t1/app/api/evidence.py' ]]"
assert "test1: app/evidence_integration.py written" "[[ -f '$t1/app/evidence_integration.py' ]]"
assert "test1: templates/evidence.html written" "[[ -f '$t1/templates/evidence.html' ]]"
assert "test1: tests/test_evidence.py written" "[[ -f '$t1/tests/test_evidence.py' ]]"
assert "test1: original app/main.py backed up" "ls '$t1'/app/main.py.bak.* >/dev/null 2>&1"
assert "test1: app/main.py imports the helper" "grep -qF 'from app.evidence_integration import attach_evidence_routes' '$t1/app/main.py'"
assert "test1: app/main.py calls the helper" "grep -qF 'attach_evidence_routes(app)' '$t1/app/main.py'"
assert "test1: app/main.py is syntactically valid" "python3 -m py_compile '$t1/app/main.py' 2>/dev/null"
assert "test1: static/style.css contains evidence-page block" "grep -qF 'Evidence page (preview-only)' '$t1/static/style.css'"
assert "test1: static/style.css preserves existing rules" "grep -qF '.todo-item' '$t1/static/style.css'"

# --- Test 2: idempotency (re-run is a noop) --------------------------------

before_main=$(shasum -a 256 "$t1/app/main.py" | awk '{print $1}')
out2=$(run_installer "$t1")
after_main=$(shasum -a 256 "$t1/app/main.py" | awk '{print $1}')

assert "test2: re-run reports already-installed" "echo \"\$out2\" | grep -qF 'already installed'"
assert "test2: app/main.py unchanged on re-run" "[[ '$before_main' == '$after_main' ]]"
backup_count=$(find "$t1/app" -maxdepth 1 -name 'main.py.bak.*' -type f 2>/dev/null | wc -l | tr -d ' ')
assert "test2: re-run does not create extra backup" "[[ '$backup_count' == '1' ]]"

# --- Test 3: divergent fork (shannon-shaped) — installer succeeds ----------

t3=$(new_tmp)
make_divergent_fork "$t3"
make_curl_stub "$t3"
make_uv_stub "$t3"
out3=$(run_installer "$t3")

assert "test3: installer reports success on divergent fork" "echo \"\$out3\" | grep -qF 'Evidence-page runtime installed.'"
assert "test3: divergent main.py keeps original middleware line" "grep -qF 'add_middleware(CORSMiddleware' '$t3/app/main.py'"
assert "test3: divergent main.py keeps all 4 routers" "[[ \"\$(grep -c 'include_router' '$t3/app/main.py')\" -eq 4 ]]"
assert "test3: divergent main.py imports the helper" "grep -qF 'from app.evidence_integration import attach_evidence_routes' '$t3/app/main.py'"
assert "test3: divergent main.py calls the helper" "grep -qF 'attach_evidence_routes(app)' '$t3/app/main.py'"
assert "test3: divergent main.py is syntactically valid" "python3 -m py_compile '$t3/app/main.py' 2>/dev/null"
assert "test3: no .evidence-template file written (no longer needed)" "[[ ! -f '$t3/app/main.py.evidence-template' ]]"

# --- Test 4: preflight refuses on main branch ------------------------------

t4=$(new_tmp)
make_fork "$t4"
(cd "$t4" && git checkout -q -b main)
make_curl_stub "$t4"
make_uv_stub "$t4"
out4=$(run_installer "$t4" || true)
assert "test4: refuses to run on main" "echo \"\$out4\" | grep -qF 'on main'"

# --- Test 5: preflight refuses outside an agile-flow-gcp-shaped repo -------

t5=$(new_tmp)
(cd "$t5" && git init -q && git checkout -q -b feature/anything)
make_curl_stub "$t5"
make_uv_stub "$t5"
out5=$(run_installer "$t5" || true)
assert "test5: refuses without pyproject.toml" "echo \"\$out5\" | grep -qF 'No pyproject.toml'"

# --- Test 6: anchorless main.py — installer aborts before mutating -----

t6=$(new_tmp)
make_anchorless_fork "$t6"
make_curl_stub "$t6"
make_uv_stub "$t6"
out6=$(run_installer "$t6" || true)

assert "test6: aborts when no include_router anchor is found" "echo \"\$out6\" | grep -qF 'no injection anchor'"
assert "test6: prints the manual-install one-liner" "echo \"\$out6\" | grep -qF 'attach_evidence_routes(app)'"
# A backup is created right before injection is attempted; that's fine —
# what matters is that app/main.py itself was not silently corrupted.
assert "test6: app/main.py left without the helper call" "! grep -qF 'attach_evidence_routes(app)' '$t6/app/main.py'"

# --- Cleanup ---------------------------------------------------------------

rm -rf "$t1" "$t3" "$t4" "$t5" "$t6"

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] || exit 1
