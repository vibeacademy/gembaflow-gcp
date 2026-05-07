#!/usr/bin/env bash
#
# Tests for install-evidence-page.sh.
#
# Stubs `curl` via PATH injection so the installer fetches files from
# the current checkout instead of GitHub raw — this means the test runs
# offline and against the version of the runtime that's about to ship.
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

# Build a minimal pre-evidence agile-flow-gcp-shaped fork in $1.
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

# --- Test 1: vanilla install on a clean fork --------------------------------

t1=$(new_tmp)
make_fork "$t1"
make_curl_stub "$t1"
out1=$(run_installer "$t1")

assert "test1: app/evidence.py written" "[[ -f '$t1/app/evidence.py' ]]"
assert "test1: app/api/evidence.py written" "[[ -f '$t1/app/api/evidence.py' ]]"
assert "test1: templates/evidence.html written" "[[ -f '$t1/templates/evidence.html' ]]"
assert "test1: tests/test_evidence.py written" "[[ -f '$t1/tests/test_evidence.py' ]]"
assert "test1: original app/main.py backed up" "ls '$t1'/app/main.py.bak.* >/dev/null 2>&1"
assert "test1: app/main.py uses create_app factory" "grep -q 'def create_app' '$t1/app/main.py'"
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

# --- Test 3: customized main.py is preserved -------------------------------

t3=$(new_tmp)
make_fork "$t3"
make_curl_stub "$t3"
cat >> "$t3/app/main.py" <<'EOF'
app.add_middleware(SomeMiddleware)
EOF
(cd "$t3" && git add -A && git commit -q -m "customize")

out3=$(run_installer "$t3")
assert "test3: customized main.py is NOT overwritten" "grep -qF 'add_middleware(SomeMiddleware)' '$t3/app/main.py'"
assert "test3: evidence-template written next to main.py" "[[ -f '$t3/app/main.py.evidence-template' ]]"
assert "test3: warning printed about manual merge" "echo \"\$out3\" | grep -qiF 'merge it into app/main.py by hand'"

# --- Test 4: preflight refuses on main branch ------------------------------

t4=$(new_tmp)
make_fork "$t4"
(cd "$t4" && git checkout -q -b main)
make_curl_stub "$t4"
out4=$(run_installer "$t4" || true)
assert "test4: refuses to run on main" "echo \"\$out4\" | grep -qF 'on main'"

# --- Test 5: preflight refuses outside an agile-flow-gcp-shaped repo -------

t5=$(new_tmp)
(cd "$t5" && git init -q && git checkout -q -b feature/anything)
make_curl_stub "$t5"
out5=$(run_installer "$t5" || true)
assert "test5: refuses without pyproject.toml" "echo \"\$out5\" | grep -qF 'No pyproject.toml'"

# --- Cleanup ---------------------------------------------------------------

rm -rf "$t1" "$t3" "$t4" "$t5"

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] || exit 1
