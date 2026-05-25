#!/usr/bin/env bash
# Tests for status-view.py — enforce that /task-status reads from the req worktree
# when running from anywhere in the repo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

STATUS_VIEW="$FRAMEWORK_ROOT/scripts/status-view.py"

_run_status() {
  # cwd is where the user runs /task-status from
  (cd "$1" && python3 "$STATUS_VIEW" 2>&1)
}

# ---------------------------------------------------------------
# Active req only exists in req worktree; /task-status must find it.
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

test_skill_preamble_detects_v3_active_task() {
  start_test "skill-preamble: v3 task-card 状态能导出 ACTIVE_TASK"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  fixture_create_task_v3 "$req_dir" "001" "impl" "执行中" "/qa" >/dev/null
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"

  out=$(cd "$req_wt" && bash "$FRAMEWORK_ROOT/scripts/skill-preamble.sh" 2>&1)
  if echo "$out" | grep -q "ACTIVE_TASK: task-001-impl (执行中)"; then
    pass_test
  else
    _fail "expected ACTIVE_TASK for v3 task-card. Output:"
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
# Stage 6 + task-plan.md cross-reference (fixes the "已完成 1 → all done" trap)
# ---------------------------------------------------------------

# Helper: write a minimal task-plan.md with given task ids/titles to req worktree
_write_task_plan() {
  local req_branch="$1"
  shift
  local req_dir="$FIXTURE_DIR/.worktrees/$req_branch/requirements/active/$req_branch"
  local plan="$req_dir/task-plan.md"
  {
    echo "| id | title | 所属模块 | 所属模块章节 | summary | order | risk |"
    echo "|----|-------|----------|--------------|---------|-------|------|"
    while [ $# -ge 2 ]; do
      echo "| $1 | $2 | mod-x | sec-y | summary | 1 | 无 |"
      shift 2
    done
    echo ""
    echo "## 执行顺序与并行性"
    echo ""
    echo "## 变更记录"
    echo ""
    echo "- （暂无）"
  } > "$plan"
  (cd "$FIXTURE_DIR/.worktrees/$req_branch" && git add -A && git commit -q -m "add task-plan")
}

test_stage6_partial_spec_does_not_claim_all_done() {
  start_test "S-PLAN1 stage 6: plan has 4 tasks but only task-001 spec'd & done → should not claim all done"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  _write_task_plan "req-001-test" \
    "task-001" "登录主流程" \
    "task-002" "权限提示" \
    "task-003" "导航栏" \
    "task-004" "退出"
  fixture_create_task "$req_dir" "001" "login" "已完成" "/qa" >/dev/null
  (cd "$FIXTURE_DIR/.worktrees/req-001-test" && git add -A && git commit -q -m "add task-001")

  out=$(_run_status "$FIXTURE_DIR")
  if echo "$out" | grep -q "所有 task 已完成"; then
    _fail "should NOT claim 所有 task 已完成 when plan has un-spec'd tasks. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  if ! echo "$out" | grep -q "task-spec task-002"; then
    _fail "expected hint to /task-spec task-002. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  if ! echo "$out" | grep -q "📝 task-002.*待 spec"; then
    _fail "expected pending-spec list to show task-002. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_stage6_all_planned_specced_and_done_claims_all_done() {
  start_test "S-PLAN2 stage 6: plan == specced && all done → claim all done"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  _write_task_plan "req-001-test" \
    "task-001" "登录" \
    "task-002" "退出"
  fixture_create_task "$req_dir" "001" "login" "已完成" "/qa" >/dev/null
  fixture_create_task "$req_dir" "002" "logout" "已完成" "/qa" >/dev/null
  (cd "$FIXTURE_DIR/.worktrees/req-001-test" && git add -A && git commit -q -m "add tasks")

  out=$(_run_status "$FIXTURE_DIR")
  if ! echo "$out" | grep -q "所有 task 已完成"; then
    _fail "expected '所有 task 已完成' when plan fully spec'd & done. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_stage6_v2_engineering_file_not_counted_as_task() {
  start_test "S-PLAN2b stage 6: v2 engineering companion is not counted as a task"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  _write_task_plan "req-001-test" \
    "task-001" "双文件任务"
  fixture_create_task_v2 "$req_dir" "001" "dualfile" "已完成" "/qa" >/dev/null
  (cd "$FIXTURE_DIR/.worktrees/req-001-test" && git add -A && git commit -q -m "add v2 task")

  out=$(_run_status "$FIXTURE_DIR")
  if echo "$out" | grep -q "Engineering"; then
    _fail "engineering companion should not appear in task status. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  if ! echo "$out" | grep -q "所有 task 已完成"; then
    _fail "v2 completed task should allow close-req hint. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_stage6_no_plan_file_falls_back_to_legacy() {
  start_test "S-PLAN3 stage 6: no task-plan.md → original behavior (all done if specced all done)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  fixture_create_task "$req_dir" "001" "only" "已完成" "/qa" >/dev/null
  (cd "$FIXTURE_DIR/.worktrees/req-001-test" && git add -A && git commit -q -m "add task")

  out=$(_run_status "$FIXTURE_DIR")
  if ! echo "$out" | grep -q "所有 task 已完成"; then
    _fail "without plan file should claim all done (legacy). Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_stage6_discarded_task_is_excluded_from_pending() {
  start_test "S-PLAN4 stage 6: task in tasks/discarded/ is excluded from 待 spec"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  _write_task_plan "req-001-test" \
    "task-001" "kept" \
    "task-002" "discarded" \
    "task-003" "kept2"
  fixture_create_task "$req_dir" "001" "kept" "已完成" "/qa" >/dev/null
  fixture_create_task "$req_dir" "003" "kept2" "已完成" "/qa" >/dev/null
  # Place a discarded marker for task-002
  mkdir -p "$req_dir/tasks/discarded"
  echo "# task-002 discarded" > "$req_dir/tasks/discarded/task-002-discarded.md"
  (cd "$FIXTURE_DIR/.worktrees/req-001-test" && git add -A && git commit -q -m "discard task-002")

  out=$(_run_status "$FIXTURE_DIR")
  if ! echo "$out" | grep -q "所有 task 已完成"; then
    _fail "discarded task should not block 'all done'. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_stage6_does_not_match_task_id_in_change_log() {
  start_test "S-PLAN5 stage 6: ## 变更记录 mentions of task-id are not matched as planned"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  # Hand-write plan: only task-001 in the table; ## 变更记录 mentions a fake task-009
  plan="$req_dir/task-plan.md"
  cat > "$plan" <<'EOF'
| id | title | 所属模块 | 所属模块章节 | summary | order | risk |
|----|-------|----------|--------------|---------|-------|------|
| task-001 | only | mod | sec | summary | 1 | 无 |

## 变更记录

- 2026-04-26 废弃 task-009（regex 误抓陷阱）
EOF
  fixture_create_task "$req_dir" "001" "only" "已完成" "/qa" >/dev/null
  (cd "$FIXTURE_DIR/.worktrees/req-001-test" && git add -A && git commit -q -m "add plan and task")

  out=$(_run_status "$FIXTURE_DIR")
  if echo "$out" | grep -q "task-spec task-009"; then
    _fail "task-id in 变更记录 should NOT be treated as un-spec'd. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  if ! echo "$out" | grep -q "所有 task 已完成"; then
    _fail "expected 所有 task 已完成 when only task-001 planned and done. Output:"
    echo "$out" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

# ---------------------------------------------------------------
# Run all
# ---------------------------------------------------------------

test_status_no_active_req
test_status_from_main_sees_req_in_worktree
test_status_from_req_worktree
test_status_from_task_worktree
test_skill_preamble_detects_v3_active_task
test_stage6_partial_spec_does_not_claim_all_done
test_stage6_all_planned_specced_and_done_claims_all_done
test_stage6_v2_engineering_file_not_counted_as_task
test_stage6_no_plan_file_falls_back_to_legacy
test_stage6_discarded_task_is_excluded_from_pending
test_stage6_does_not_match_task_id_in_change_log

report_results "status-view"
