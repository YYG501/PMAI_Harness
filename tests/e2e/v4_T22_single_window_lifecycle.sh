#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TEST_ROOT/helpers/assert.sh"
source "$TEST_ROOT/helpers/fixture.sh"

CREATE_TASK_WORKTREE="$FRAMEWORK_ROOT/scripts/create-task-worktree.sh"
TASK_TRANSITION="$FRAMEWORK_ROOT/scripts/task-transition.py"
TASK_EVENTS="$FRAMEWORK_ROOT/scripts/task-events.py"
CLOSE_TASK="$FRAMEWORK_ROOT/scripts/close-task.sh"
CLEANUP_PENDING="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"

_commit_all_if_needed() {
  local wt="$1"
  local message="$2"
  (
    cd "$wt"
    if [ -n "$(git status --porcelain)" ]; then
      git add -A
      git commit -q -m "$message"
    fi
  )
}

_copy_task_path_to_task_worktree() {
  local req_dir="$1"
  local task_wt="$2"
  local task_file="$3"
  local req_name
  req_name=$(basename "$req_dir")
  echo "$task_wt/requirements/active/$req_name/tasks/$(basename "$task_file")"
}

test_single_window_lifecycle() {
  start_test "single-window lifecycle confirm → execute → submit → close"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "single" 6)
  task=$(fixture_create_task "$req_dir" "001" "lifecycle" "待确认" "(无)")

  # task-confirm simulation: dependency gate has no dependencies, create worktree.
  # v4.5：create-task-worktree.sh 自动把 task md 从 req 分支移走（task 分支独家）。
  # 不在 confirm 阶段更新 worktree 字段以免 task 分支多出"代码先于状态机"commit
  # 触发 I-CT8（worktree 字段由 task-execute 启动时回填）。
  (cd "$FIXTURE_DIR/.worktrees/req-001-single" && bash "$CREATE_TASK_WORKTREE" "$task" "req-001-single") >/dev/null 2>&1
  task_wt="$FIXTURE_DIR/.worktrees/task-001-lifecycle"
  task_in_wt=$(_copy_task_path_to_task_worktree "$req_dir" "$task_wt" "$task")

  status=$(python3 "$TASK_TRANSITION" "$task_in_wt" --get-status)
  if [ "$status" != "待确认" ]; then
    _fail "task-confirm simulation should keep 待确认, got $status"
    fixture_teardown
    return
  fi

  # task-execute simulation: status transition happens in the task worktree.
  (cd "$task_wt" && python3 "$TASK_TRANSITION" "$task_in_wt" --to 执行中 >/dev/null)
  (cd "$task_wt" && python3 "$TASK_EVENTS" append "$task_in_wt" --type execution_started --payload '{"executor":"manual"}' >/dev/null 2>&1)
  # I-CT8 要求 commit 时间晚于首次 status_changed 事件 (commit 秒精度 vs event microsecond)
  sleep 1
  echo "implemented in task branch" > "$task_wt/lifecycle.txt"
  _commit_all_if_needed "$task_wt" "implement lifecycle task"

  # task-submit simulation: no review required, transition to 待验收, then PM accepts to 已完成.
  (cd "$task_wt" && python3 "$TASK_TRANSITION" "$task_in_wt" --to 待验收 >/dev/null)
  _commit_all_if_needed "$task_wt" "submit lifecycle task"
  (cd "$task_wt" && python3 "$TASK_TRANSITION" "$task_in_wt" --to 已完成 >/dev/null)
  _commit_all_if_needed "$task_wt" "accept lifecycle task"

  # v4.5：close 在 req worktree 内执行（PM 关 task 窗口后切到 req 窗口）。
  # 一步关完：merge → 归档 → 删 task worktree → 删 task branch。
  if ! (cd "$FIXTURE_DIR/.worktrees/req-001-single" && bash "$CLOSE_TASK" "$task_in_wt") >/tmp/v4_t22_close.out.$$ 2>/tmp/v4_t22_close.err.$$; then
    _fail "close-task failed"
    cat /tmp/v4_t22_close.err.$$ >&2
    fixture_teardown
    return
  fi

  # 先存变量再 grep — 避免 grep -q SIGPIPE 在 set -uo pipefail 下退 141
  req_log=$(git -C "$FIXTURE_DIR/.worktrees/req-001-single" log --oneline --all)
  if ! echo "$req_log" | grep -F -q "implement lifecycle task"; then
    _fail "req branch does not contain task implementation commit"
    fixture_teardown
    return
  fi
  final_task="$FIXTURE_DIR/.worktrees/req-001-single/requirements/active/req-001-single/tasks/task-001-lifecycle.md"
  final_status=$(python3 "$TASK_TRANSITION" "$final_task" --get-status)
  if [ "$final_status" != "已完成" ]; then
    _fail "expected final status 已完成, got $final_status"
    fixture_teardown
    return
  fi

  # v4.5：close 完成后 task worktree + branch 应已被直接删除（一步关完）
  if [ -d "$FIXTURE_DIR/.worktrees/task-001-lifecycle" ]; then
    _fail "task worktree should be removed after close (v4.5 一步关完)"
    fixture_teardown
    return
  fi
  if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/task-001-lifecycle"; then
    _fail "task branch should be deleted after close (v4.5 一步关完)"
    fixture_teardown
    return
  fi

  # v4.5：pending-cleanup.json 不该有当前 task 的 entry
  pending_file="$FIXTURE_DIR/.runs/pending-cleanup.json"
  if [ -f "$pending_file" ]; then
    queued=$(python3 -c "import json; print(any(e.get('branch')=='task-001-lifecycle' for e in json.load(open('$pending_file'))))")
    if [ "$queued" = "True" ]; then
      _fail "pending-cleanup.json should NOT have task-001-lifecycle entry (v4.5: deleted directly)"
      fixture_teardown
      return
    fi
  fi

  rm -f /tmp/v4_t22_close.out.$$ /tmp/v4_t22_close.err.$$
  pass_test
  fixture_teardown
}

test_single_window_lifecycle

report_results "v4_T22_single_window_lifecycle"
