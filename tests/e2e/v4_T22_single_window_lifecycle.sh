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

  # task-confirm simulation: dependency gate has no dependencies, create worktree, status remains 待确认.
  # Suppress create-task-worktree stdout (mixes git output); use known fixture path
  (cd "$FIXTURE_DIR/.worktrees/req-001-single" && bash "$CREATE_TASK_WORKTREE" "$task" "req-001-single") >/dev/null 2>&1
  task_wt="$FIXTURE_DIR/.worktrees/task-001-lifecycle"
  sed -i.bak "s|^\*\*worktree：\*\*.*|\*\*worktree：\*\* .worktrees/task-001-lifecycle|" "$task"
  rm -f "$task.bak"
  _commit_all_if_needed "$FIXTURE_DIR/.worktrees/req-001-single" "confirm task worktree"

  status=$(python3 "$TASK_TRANSITION" "$task" --get-status)
  if [ "$status" != "待确认" ]; then
    _fail "task-confirm simulation should keep 待确认, got $status"
    fixture_teardown
    return
  fi

  task_in_wt=$(_copy_task_path_to_task_worktree "$req_dir" "$task_wt" "$task")

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

  if ! (cd "$task_wt" && bash "$CLOSE_TASK" "$task_in_wt") >/tmp/v4_t22_close.out.$$ 2>/tmp/v4_t22_close.err.$$; then
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
  if [ -d "$FIXTURE_DIR/.worktrees/task-001-lifecycle" ]; then
    _fail "task worktree should be removed by close-task"
    fixture_teardown
    return
  fi

  rm -f /tmp/v4_t22_close.out.$$ /tmp/v4_t22_close.err.$$
  pass_test
  fixture_teardown
}

test_single_window_lifecycle

report_results "v4_T22_single_window_lifecycle"
