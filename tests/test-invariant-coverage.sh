#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/invariant-coverage.py"

test_coverage_index_is_complete() {
  start_test "invariant-coverage: 核心不变量都有护栏、测试和 session 状态"
  if python3 "$CHECKER" --repo-root "$REPO_ROOT" >/tmp/invariant-coverage.$$ 2>&1 && \
     grep -q 'scoped=22 mapped=22' /tmp/invariant-coverage.$$; then
    pass_test
  else
    _fail "coverage index should be complete"
    cat /tmp/invariant-coverage.$$ >&2
  fi
  rm -f /tmp/invariant-coverage.$$
}

test_unknown_mapping_fails_closed() {
  start_test "invariant-coverage: 未知不变量映射必须失败关闭"
  local t
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-invariant-coverage.XXXXXX")
  cp "$REPO_ROOT/INVARIANTS.md" "$t/INVARIANTS.md"
  sed 's/"I-TEST4"/"I-UNKNOWN4"/' "$t/INVARIANTS.md" > "$t/modified.md"
  if python3 "$CHECKER" --source "$t/modified.md" --repo-root "$REPO_ROOT" >/tmp/invariant-coverage-negative.$$ 2>&1; then
    _fail "unknown mapping should fail"
    cat /tmp/invariant-coverage-negative.$$ >&2
  elif grep -q '未知不变量' /tmp/invariant-coverage-negative.$$; then
    pass_test
  else
    _fail "failure should identify unknown mapping"
    cat /tmp/invariant-coverage-negative.$$ >&2
  fi
  rm -f /tmp/invariant-coverage-negative.$$
  rm -rf "$t"
}

test_coverage_index_is_complete
test_unknown_mapping_fails_closed
report_results "invariant-coverage"
