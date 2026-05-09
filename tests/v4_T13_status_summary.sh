#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

STATUS_VIEW="$FRAMEWORK_ROOT/scripts/status-view.py"

test_summary_counts_active_tasks() {
  start_test "status-view --summary counts executing and pending-start tasks (post 2026-05-08「待验收」合并)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "summary" 6)
  # 「待验收」于 2026-05-08 合并入「执行中」 — commit 后呈交期间仍是「执行中」
  fixture_create_task "$req_dir" "001" "running" "执行中" >/dev/null
  fixture_create_task "$req_dir" "002" "review" "执行中" >/dev/null
  pending_task=$(fixture_create_task "$req_dir" "003" "ready" "待执行")
  fixture_create_task "$req_dir" "004" "done" "已完成" >/dev/null

  mkdir -p "$FIXTURE_DIR/.worktrees/task-003-ready"

  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --summary 2>&1)
  if ! echo "$out" | grep -F -q "📋 task 概览: 执行中 2 / 待启动 1"; then
    _fail "summary line missing or wrong. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  if [ ! -f "$pending_task" ]; then
    _fail "fixture pending task was not created"
    fixture_teardown
    return
  fi

  pass_test
  fixture_teardown
}

test_summary_counts_active_tasks

report_results "v4_T13_status_summary"
