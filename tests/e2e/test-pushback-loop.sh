#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TEST_ROOT/helpers/assert.sh"
source "$TEST_ROOT/helpers/fixture.sh"

TASK_EXECUTE_SKILL="$FRAMEWORK_ROOT/skills/task-execute/SKILL.md"
TASK_SUBMIT_SKILL="$FRAMEWORK_ROOT/skills/task-submit/SKILL.md"

_contains() {
  local file="$1"
  local text="$2"
  grep -F -q -- "$text" "$file"
}

_assert_contains() {
  local file="$1"
  local text="$2"
  local desc="$3"
  if _contains "$file" "$text"; then
    return 0
  fi
  _fail "$desc: missing '$text'"
  sed -n '1,460p' "$file" >&2
  return 1
}

_append_pm_feedback() {
  local task="$1"
  local n="$2"
  local desc="$3"
  local req="$4"
  cat >> "$task" <<EOF

### 反馈 $n - 2026-04-25
**问题描述：** $desc
**要求修改：** $req
**处理结果：** 待处理
EOF
}

test_pushback_loop_contract() {
  start_test "e2e pushback: task-submit hands off to task-execute triage"

  _assert_contains "$TASK_SUBMIT_SKILL" "DX RU3 分流策略" "DX RU3 handoff message" || return
  _assert_contains "$TASK_EXECUTE_SKILL" "本次反馈识别为" "classification one-liner" || return
  _assert_contains "$TASK_EXECUTE_SKILL" 'PM says `wrong`: flip the classification' "wrong branch flip" || return

  pass_test
}

test_pushback_loop_behavioral_fixture() {
  start_test "e2e pushback: feedback append and status transition simulation"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "401" "pushback" "待验收" "/qa")

  _append_pm_feedback "$task" "1" "should change behavior before showing result" "改成先校验权限再显示结果"
  if ! grep -q "should change behavior" "$task"; then
    _fail "behavior revision feedback missing"
    fixture_teardown
    return
  fi

  sed -i.bak 's|^\*\*状态：\*\*.*|\*\*状态：\*\* 执行中|' "$task"
  rm -f "$task.bak"
  if ! grep -q '^\*\*状态：\*\* 执行中' "$task"; then
    _fail "task status should transition back to 执行中"
    fixture_teardown
    return
  fi

  _append_pm_feedback "$task" "2" "missing step 3，漏了错误态提示" "补上漏掉的错误态"
  if ! grep -q "missing step 3" "$task" || ! grep -q "漏了" "$task"; then
    _fail "bug-type feedback missing"
    fixture_teardown
    return
  fi

  _assert_contains "$TASK_EXECUTE_SKILL" "wrong" "PM wrong rejection keyword" || { fixture_teardown; return; }
  _assert_contains "$TASK_EXECUTE_SKILL" "flip the classification" "switch classification on wrong" || { fixture_teardown; return; }

  fixture_teardown
  pass_test
}

test_pushback_loop_contract
test_pushback_loop_behavioral_fixture

report_results "e2e-pushback-loop"
