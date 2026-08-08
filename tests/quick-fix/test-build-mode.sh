#!/usr/bin/env bash
# quick-fix 启动位置回归测试。
# Covers ensure_quickfix_root 三种拒绝分支：build-* worktree、task-* worktree、主仓非 main。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

test_build_worktree_rejected_without_side_effects() {
  start_test "scenario QR1 build worktree rejects quick-fix without side effects"
  fixture_setup
  fixture_create_work work-001 test 1 >/dev/null 2>&1

  local build_wt="$FIXTURE_DIR/.worktrees/build-work-001-test"
  local before_branches after_branches err marker
  before_branches=$(git -C "$FIXTURE_DIR" branch --format='%(refname:short)' | sort)
  err=$(mktemp)
  marker="$build_wt/quick-fix-must-not-run.txt"

  if (cd "$build_wt" && QUICK_FIX_COMMAND='touch quick-fix-must-not-run.txt' \
    QUICK_FIX_DECISION=pass QUICK_FIX_ASSUME_YES=1 \
    bash "$QF" "build mode must reject" 2>"$err"); then
    _fail "build worktree should have been rejected but exit=0"
  else
    after_branches=$(git -C "$FIXTURE_DIR" branch --format='%(refname:short)' | sort)
    if grep -q "build worktree" "$err" \
      && [ ! -e "$marker" ] \
      && [ "$before_branches" = "$after_branches" ] \
      && ! find "$FIXTURE_DIR/.worktrees" -maxdepth 1 -type d -name 'tmp-quick-*' | grep -q .; then
      pass_test
    else
      _fail "build worktree rejection had wrong message or side effects"
      cat "$err" >&2
    fi
  fi
  rm -f "$err"
  fixture_teardown
}

test_task_worktree_rejected() {
  start_test "scenario QR2 task worktree rejects quick-fix"
  fixture_setup
  # Create a fake task worktree (branch name task-* triggers reject)
  (
    cd "$FIXTURE_DIR"
    git checkout -q -b task-001-fake
    git checkout -q main
    git worktree add -q .worktrees/task-001-fake task-001-fake
  )

  local err
  err=$(mktemp)
  if (cd "$FIXTURE_DIR/.worktrees/task-001-fake" && bash "$QF" "should fail" 2>"$err"); then
    _fail "task worktree should have been rejected but exit=0"
    cat "$err" >&2
  elif grep -q "task worktree" "$err"; then
    pass_test
  else
    _fail "wrong error message: $(cat "$err")"
  fi
  rm -f "$err"
  fixture_teardown
}

test_weird_branch_rejected() {
  start_test "scenario QR3 主仓根但分支非 main → 拒绝"
  fixture_setup
  (cd "$FIXTURE_DIR" && git checkout -q -b weird-branch)

  local err
  err=$(mktemp)
  if (cd "$FIXTURE_DIR" && bash "$QF" "should fail" 2>"$err"); then
    _fail "non-main branch on repo root should be rejected"
  elif grep -q "当前分支不是 main" "$err"; then
    pass_test
  else
    _fail "wrong error: $(cat "$err")"
  fi
  rm -f "$err"
  fixture_teardown
}

test_build_worktree_rejected_without_side_effects
test_task_worktree_rejected
test_weird_branch_rejected
report_results "quick-fix start location"
