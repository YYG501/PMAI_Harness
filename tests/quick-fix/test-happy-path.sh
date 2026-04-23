#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

_setup_tsc() {
  local rc="${1:-0}"
  echo '{"devDependencies":{"typescript":"test"}}' > "$FIXTURE_DIR/package.json"
  mkdir -p "$FIXTURE_DIR/node_modules/.bin"
  cat > "$FIXTURE_DIR/node_modules/.bin/tsc" <<EOF
#!/usr/bin/env bash
exit $rc
EOF
  chmod +x "$FIXTURE_DIR/node_modules/.bin/tsc"
}

_run_qf() {
  local desc="$1"
  local cmd="$2"
  (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="$cmd" QUICK_FIX_APPROVE=1 bash "$QF" "$desc" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$)
}

test_docs_only() {
  start_test "scenario 1 docs-only quick-fix merges"
  fixture_setup
  if _run_qf "docs only" "mkdir -p docs && echo doc > docs/qf-doc.md" \
    && [ -f "$FIXTURE_DIR/docs/qf-doc.md" ] \
    && git -C "$FIXTURE_DIR" log --grep '^\[quick-fix\]' --format=%s -1 | grep -q "docs only"; then
    pass_test
  else
    _fail "docs-only quick-fix failed"
    cat /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_code_only() {
  start_test "scenario 2 ts-only quick-fix runs tsc and merges"
  fixture_setup
  _setup_tsc 0
  if _run_qf "code only" "mkdir -p src && echo 'export const x: number = 1' > src/qf.ts" \
    && [ -f "$FIXTURE_DIR/src/qf.ts" ] \
    && grep -q "tsc --noEmit" /tmp/qf.out.$$; then
    pass_test
  else
    _fail "code-only quick-fix failed"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_mixed() {
  start_test "scenario 3 mixed docs and code quick-fix merges"
  fixture_setup
  _setup_tsc 0
  if _run_qf "mixed change" "mkdir -p docs src && echo doc > docs/mixed.md && echo 'export const y = 2' > src/mixed.ts" \
    && [ -f "$FIXTURE_DIR/docs/mixed.md" ] \
    && [ -f "$FIXTURE_DIR/src/mixed.ts" ]; then
    pass_test
  else
    _fail "mixed quick-fix failed"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_docs_only
test_code_only
test_mixed
report_results "quick-fix happy path"
