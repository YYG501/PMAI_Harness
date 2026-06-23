#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

_assert_redline_blocks() {
  local desc="$1"
  local cmd="$2"
  start_test "$desc"
  fixture_setup
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="$cmd" QUICK_FIX_APPROVE=1 bash "$QF" "$desc" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$); then
    _fail "redline should block"
  elif grep -q "命中红线" /tmp/qf.err.$$ && [ -z "$(git -C "$FIXTURE_DIR" log --grep '^\[quick-fix\]' --format=%h)" ]; then
    pass_test
  else
    _fail "redline output missing"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_task_file_redline() {
  _assert_redline_blocks "scenario 11 blocks module tasks md" "mkdir -p docs/modules/work-001/tasks && echo bad > docs/modules/work-001/tasks/task-001.md"
}

test_meta_redline() {
  _assert_redline_blocks "scenario 12 blocks work meta" "mkdir -p docs/modules/work-001 && echo '{}' > docs/modules/work-001/.work-meta.json"
}

test_claude_scripts_redline() {
  _assert_redline_blocks "scenario 13 blocks claude scripts" "rm .claude/scripts && mkdir -p .claude/scripts && echo bad > .claude/scripts/bad.sh"
}

test_task_file_redline
test_meta_redline
test_claude_scripts_redline
report_results "quick-fix redline enforcement"
