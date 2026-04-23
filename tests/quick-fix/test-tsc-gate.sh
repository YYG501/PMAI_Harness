#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

_setup_failing_tsc() {
  echo '{"devDependencies":{"typescript":"test"}}' > "$FIXTURE_DIR/package.json"
  mkdir -p "$FIXTURE_DIR/node_modules/.bin"
  cat > "$FIXTURE_DIR/node_modules/.bin/tsc" <<'EOF'
#!/usr/bin/env bash
echo "fixture tsc failed" >&2
exit 2
EOF
  chmod +x "$FIXTURE_DIR/node_modules/.bin/tsc"
}

_ts_change_cmd() {
  echo "mkdir -p src && echo 'export const broken: number = \"x\"' > src/broken.ts"
}

test_tsc_failure_blocks_merge() {
  start_test "scenario 4 tsc failure blocks merge and keeps worktree"
  fixture_setup
  _setup_failing_tsc
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="$(_ts_change_cmd)" QUICK_FIX_APPROVE=1 bash "$QF" "tsc fail" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$); then
    _fail "quick-fix should fail on tsc"
  elif ! [ -f "$FIXTURE_DIR/src/broken.ts" ] && grep -q "tsc --noEmit 失败" /tmp/qf.err.$$; then
    pass_test
  else
    _fail "tsc failure did not block as expected"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_skip_tsc_allows_merge() {
  start_test "scenario 5 --skip-tsc skips failing tsc"
  fixture_setup
  _setup_failing_tsc
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="$(_ts_change_cmd)" QUICK_FIX_APPROVE=1 bash "$QF" --skip-tsc "skip tsc" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$) \
    && [ -f "$FIXTURE_DIR/src/broken.ts" ] \
    && grep -q "跳过 tsc" /tmp/qf.out.$$; then
    pass_test
  else
    _fail "--skip-tsc should merge"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_force_allows_merge() {
  start_test "scenario 6 --force merges despite failing tsc"
  fixture_setup
  _setup_failing_tsc
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="$(_ts_change_cmd)" QUICK_FIX_APPROVE=1 bash "$QF" --force "force tsc" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$) \
    && [ -f "$FIXTURE_DIR/src/broken.ts" ] \
    && grep -q -- "--force" /tmp/qf.err.$$; then
    pass_test
  else
    _fail "--force should merge"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_tsc_failure_blocks_merge
test_skip_tsc_allows_merge
test_force_allows_merge
report_results "quick-fix tsc gate"
