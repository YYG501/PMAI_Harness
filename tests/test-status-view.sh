#!/usr/bin/env bash
# Tests for status-view.py — enforce that /status reads from the req worktree
# when running from anywhere in the repo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

STATUS_VIEW="$FRAMEWORK_ROOT/scripts/status-view.py"

_run_status() {
  # cwd is where the user runs /status from
  (cd "$1" && python3 "$STATUS_VIEW" 2>&1)
}

# ---------------------------------------------------------------
# Active req only exists in req worktree; /status must find it.
# ---------------------------------------------------------------

test_status_from_main_sees_req_in_worktree() {
  start_test "status from main repo root sees req that only exists in req worktree"
  fixture_setup

  fixture_create_req "req-001" "test" 3 >/dev/null

  out=$(_run_status "$FIXTURE_DIR")
  if echo "$out" | grep -q "req-001"; then
    pass_test
  else
    _fail "status did not pick up req in req worktree. Output:"
    echo "$out" >&2
  fi
  fixture_teardown
}

test_status_from_req_worktree() {
  start_test "status run from req worktree sees its own req"
  fixture_setup

  fixture_create_req "req-001" "test" 3 >/dev/null
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"

  out=$(_run_status "$req_wt")
  if echo "$out" | grep -q "req-001"; then
    pass_test
  else
    _fail "status from req worktree did not find req. Output:"
    echo "$out" >&2
  fi
  fixture_teardown
}

test_status_from_task_worktree() {
  start_test "status run from task worktree sees parent req"
  fixture_setup

  fixture_create_req "req-001" "test" 6 >/dev/null
  req_dir_in_wt="$FIXTURE_DIR/.worktrees/req-001-test/requirements/active/req-001-test"
  task=$(fixture_create_task "$req_dir_in_wt" "001" "impl" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  out=$(_run_status "$task_wt")
  if echo "$out" | grep -q "req-001"; then
    pass_test
  else
    _fail "status from task worktree did not find parent req. Output:"
    echo "$out" >&2
  fi
  fixture_teardown
}

test_status_no_active_req() {
  start_test "status reports empty when no active req exists"
  fixture_setup

  out=$(_run_status "$FIXTURE_DIR")
  if echo "$out" | grep -q "没有活跃"; then
    pass_test
  else
    _fail "expected 没有活跃 message. Output:"
    echo "$out" >&2
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# Run all
# ---------------------------------------------------------------

test_status_no_active_req
test_status_from_main_sees_req_in_worktree
test_status_from_req_worktree
test_status_from_task_worktree

report_results "status-view"
