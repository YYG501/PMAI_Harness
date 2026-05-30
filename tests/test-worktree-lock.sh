#!/usr/bin/env bash
# v2 状态物化回归：task worktree 建时 git worktree lock，删前先 unlock。
# 目的：并发多 task 时，一个 task 的清理 / prune 不会误删另一个在跑的 task worktree。
# 跨 task 代码串台（2026-04-22）由 dispatch 越界保护 + 一 task 一执行器兜底；本测试只验 lock 机制本身。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$SCRIPT_DIR"
source "$TEST_ROOT/helpers/assert.sh"
source "$TEST_ROOT/helpers/fixture.sh"

CREATE_TASK_WORKTREE="$FRAMEWORK_ROOT/scripts/create-task-worktree.sh"

echo "▶ Running test-worktree-lock.sh"
echo "─────────────────────────────────────────"

# 建一个真 task worktree（走真脚本，触发 create 时的 git worktree lock），回 worktree 路径
_make_locked_task_wt() {
  local req_dir task
  req_dir=$(fixture_create_req "req-001" "single" 6)
  task=$(fixture_create_task "$req_dir" "001" "locktest" "待执行" "(无)")
  (cd "$FIXTURE_DIR/.worktrees/req-001-single" && bash "$CREATE_TASK_WORKTREE" "$task" "req-001-single") >/dev/null 2>&1
  echo "$FIXTURE_DIR/.worktrees/task-001-locktest"
}

test_worktree_locked_on_create() {
  start_test "create-task-worktree: 新建 task worktree 被 git worktree lock"
  fixture_setup
  local task_wt
  task_wt=$(_make_locked_task_wt)
  # 非 porcelain `worktree list` 对 locked worktree 在行尾加 'locked'；按 basename
  # 抓该行再判 locked（避开 macOS /tmp↔/private/tmp 符号链接导致的全路径不等）。
  if git -C "$FIXTURE_DIR" worktree list | grep -F "task-001-locktest" | grep -q "locked"; then
    pass_test
  else
    _fail "task worktree 未被 lock：$(git -C "$FIXTURE_DIR" worktree list)"
  fi
  fixture_teardown
}

test_lock_blocks_remove_unlock_allows() {
  start_test "lock 挡裸 remove；unlock 后可删（close-task 删前 unlock 的依据）"
  fixture_setup
  local task_wt
  task_wt=$(_make_locked_task_wt)
  # 裸 remove 应失败（被 lock 挡住）
  if git -C "$FIXTURE_DIR" worktree remove "$task_wt" 2>/dev/null; then
    _fail "locked worktree 被裸 remove 删掉了（lock 没生效）"
    fixture_teardown
    return
  fi
  # unlock 后可删（这是 close-task / discard / cleanup 删前先 unlock 的依据）
  git -C "$FIXTURE_DIR" worktree unlock "$task_wt" 2>/dev/null
  if git -C "$FIXTURE_DIR" worktree remove "$task_wt" 2>/dev/null; then
    pass_test
  else
    _fail "unlock 后仍删不掉 task worktree"
  fi
  fixture_teardown
}

test_worktree_locked_on_create
test_lock_blocks_remove_unlock_allows

report_results "worktree-lock"
