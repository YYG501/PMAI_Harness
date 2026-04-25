#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

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

test_task_execute_has_triage_strategy() {
  start_test "task-execute has PM feedback triage strategy"
  _assert_contains "$TASK_EXECUTE_SKILL" "PM 反馈分流策略" "triage section header" || return
  pass_test
}

test_task_execute_has_oneliner_output() {
  start_test "task-execute has classification one-liner"
  _assert_contains "$TASK_EXECUTE_SKILL" "本次反馈识别为" "classification one-liner" || return
  pass_test
}

test_task_execute_has_wrong_rejection() {
  start_test "task-execute has wrong rejection mechanism"
  _assert_contains "$TASK_EXECUTE_SKILL" "wrong" "PM wrong mechanism" || return
  pass_test
}

test_task_execute_has_behavior_path() {
  start_test "task-execute has behavior revision path"
  _assert_contains "$TASK_EXECUTE_SKILL" "行为修订" "behavior classification" || return
  _assert_contains "$TASK_EXECUTE_SKILL" "改 task.md" "behavior task rewrite action" || return
  pass_test
}

test_task_execute_has_bug_path() {
  start_test "task-execute has bug fix path"
  _assert_contains "$TASK_EXECUTE_SKILL" "Bug 修复" "bug classification" || return
  _assert_contains "$TASK_EXECUTE_SKILL" "只改代码" "bug code-only action" || return
  pass_test
}

test_task_execute_has_behavior_three_steps() {
  start_test "task-execute behavior path requires PM second confirmation"
  _assert_contains "$TASK_EXECUTE_SKILL" "二次确认" "behavior revision second confirmation" || return
  pass_test
}

test_task_submit_references_task_execute() {
  start_test "task-submit references task-execute as DX RU3 authority"
  _assert_contains "$TASK_SUBMIT_SKILL" "task-execute" "task-execute reference" || return
  _assert_contains "$TASK_SUBMIT_SKILL" "DX RU3" "DX RU3 reference" || return
  pass_test
}

test_task_submit_no_duplicate_triage() {
  start_test "task-submit does not duplicate triage definition"
  _assert_missing "$TASK_SUBMIT_SKILL" "行为修订 path" "no behavior path definition in task-submit" || return
  _assert_missing "$TASK_SUBMIT_SKILL" "Bug 修复 path" "no bug path definition in task-submit" || return
  pass_test
}

test_single_authority_source() {
  start_test "single authority source for PM feedback triage"
  _assert_contains "$TASK_EXECUTE_SKILL" "共享权威源" "task-execute authority marker" || return
  _assert_missing "$TASK_SUBMIT_SKILL" "### PM 反馈分流策略" "task-submit has no standalone triage section" || return
  pass_test
}

test_task_execute_has_triage_strategy
test_task_execute_has_oneliner_output
test_task_execute_has_wrong_rejection
test_task_execute_has_behavior_path
test_task_execute_has_bug_path
test_task_execute_has_behavior_three_steps
test_task_submit_references_task_execute
test_task_submit_no_duplicate_triage
test_single_authority_source

report_results "task-pm-feedback"
