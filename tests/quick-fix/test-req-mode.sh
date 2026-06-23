#!/usr/bin/env bash
# quick-fix build mode + task reject 回归测试。
# Covers ensure_quickfix_root 三种分支：build-* 接受、task-* 拒绝、weird 分支拒绝。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

test_build_mode_merges_to_build_branch() {
  start_test "scenario QB1 build mode merges to build branch, leaves main untouched"
  fixture_setup
  fixture_create_req req-001 test 1 >/dev/null 2>&1

  local build_wt="$FIXTURE_DIR/.worktrees/build-req-001-test"
  # Pre-state: main has empty prototypes/, build branch has same
  echo "# main version" > "$FIXTURE_DIR/prototypes/page.md"
  (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "main page")
  # build branch picks it up via merge
  (cd "$build_wt" && git merge -q --no-edit main 2>/dev/null || true)

  # Run quick-fix from build worktree
  local out err
  out=$(mktemp); err=$(mktemp)
  (cd "$build_wt" && QUICK_FIX_COMMAND='echo "build-only fix" >> prototypes/page.md' \
    QUICK_FIX_DECISION=pass QUICK_FIX_ASSUME_YES=1 \
    bash "$QF" "build mode test" >"$out" 2>"$err")
  local rc=$?

  local base_branch
  base_branch=$(awk '/^BASE_BRANCH:/{print $2}' "$out")

  if [ "$rc" -eq 0 ] \
    && [ "$base_branch" = "build-req-001-test" ] \
    && grep -q "build-only fix" "$build_wt/prototypes/page.md" \
    && ! grep -q "build-only fix" "$FIXTURE_DIR/prototypes/page.md"; then
    pass_test
  else
    _fail "build mode failed: rc=$rc base=$base_branch"
    echo "--stdout--" >&2; cat "$out" >&2
    echo "--stderr--" >&2; cat "$err" >&2
  fi
  rm -f "$out" "$err"
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

test_build_mode_merges_to_build_branch
test_task_worktree_rejected
test_weird_branch_rejected
