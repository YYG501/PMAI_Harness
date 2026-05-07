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
  return 1
}

_assert_missing() {
  local file="$1"
  local text="$2"
  local desc="$3"
  if _contains "$file" "$text"; then
    _fail "$desc: should not contain '$text'"
    return 1
  fi
  return 0
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

# Contract: task-submit 把反馈循环交给 task-execute 按反馈循环规则处理；不再有分流/wrong 翻转
test_pushback_loop_contract() {
  start_test "e2e pushback: task-submit hands off to task-execute 反馈循环规则"

  _assert_contains "$TASK_SUBMIT_SKILL" "反馈循环规则" "feedback-loop handoff message" || return
  _assert_contains "$TASK_EXECUTE_SKILL" "### 反馈循环规则" "task-execute owns 反馈循环规则" || return
  _assert_contains "$TASK_EXECUTE_SKILL" "文档对齐预告" "文档对齐预告 field present" || return

  _assert_missing "$TASK_SUBMIT_SKILL" "DX RU3" "no legacy DX RU3 reference" || return
  _assert_missing "$TASK_EXECUTE_SKILL" "本次反馈识别为" "no legacy classification one-liner" || return
  _assert_missing "$TASK_EXECUTE_SKILL" "flip the classification" "no legacy wrong-flip" || return

  pass_test
}

# Behavioral: 反馈 append 到 task md + 状态回执行中 (这两个动作不变)
test_pushback_loop_behavioral_fixture() {
  start_test "e2e pushback: feedback append and status transition simulation"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "401" "pushback" "待验收" "/qa")

  _append_pm_feedback "$task" "1" "should change behavior before showing result" "改成先校验权限再显示结果"
  if ! grep -q "should change behavior" "$task"; then
    _fail "behavior-style feedback missing"
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
    _fail "second feedback round missing"
    fixture_teardown
    return
  fi

  # 反馈循环规则: 多轮反馈用"后覆盖前"作为冲突解决（无须 wrong/翻转）
  _assert_contains "$TASK_EXECUTE_SKILL" "后覆盖前" "conflict-resolution rule documented" || { fixture_teardown; return; }
  _assert_contains "$TASK_EXECUTE_SKILL" "实现歧义阻塞" "ambiguity gate documented" || { fixture_teardown; return; }

  fixture_teardown
  pass_test
}

test_pushback_loop_contract
test_pushback_loop_behavioral_fixture

report_results "e2e-pushback-loop"
