#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

TASK_EXECUTE_SKILL="$FRAMEWORK_ROOT/skills/task-execute/SKILL.md"
TASK_SUBMIT_SKILL="$FRAMEWORK_ROOT/skills/task-submit/SKILL.md"
CLOSE_TASK_SKILL="$FRAMEWORK_ROOT/skills/close-task/SKILL.md"
TASK_TMPL="$FRAMEWORK_ROOT/templates/task.md.tmpl"

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

# 新行为：反馈循环规则（替代已删除的 §PM 反馈分流策略）

test_task_execute_has_feedback_loop_rules() {
  start_test "task-execute has 反馈循环规则 section"
  _assert_contains "$TASK_EXECUTE_SKILL" "### 反馈循环规则" "反馈循环规则 section header" || return
  pass_test
}

test_task_execute_only_changes_prototype_code() {
  start_test "task-execute 反馈循环规则 says only change prototype code"
  _assert_contains "$TASK_EXECUTE_SKILL" "改原型代码" "prototype-code-only directive" || return
  _assert_contains "$TASK_EXECUTE_SKILL" "不改" "explicit do-not-change directive" || return
  pass_test
}

test_task_execute_has_doc_alignment_preview_field() {
  start_test "task-execute execution report has 文档对齐预告 field"
  _assert_contains "$TASK_EXECUTE_SKILL" "文档对齐预告" "文档对齐预告 field" || return
  pass_test
}

test_task_execute_has_conflict_resolution() {
  start_test "task-execute 反馈循环规则 has 后覆盖前 conflict resolution"
  _assert_contains "$TASK_EXECUTE_SKILL" "后覆盖前" "conflict resolution rule" || return
  pass_test
}

test_task_execute_blocks_only_on_implementation_ambiguity() {
  start_test "task-execute only asks PM on 实现歧义阻塞"
  _assert_contains "$TASK_EXECUTE_SKILL" "实现歧义阻塞" "implementation ambiguity gate" || return
  pass_test
}

# 旧行为已删除（防止回退）

test_task_execute_no_legacy_triage() {
  start_test "task-execute no longer has §PM 反馈分流策略"
  _assert_missing "$TASK_EXECUTE_SKILL" "### PM 反馈分流策略" "legacy triage section" || return
  _assert_missing "$TASK_EXECUTE_SKILL" "本次反馈识别为" "legacy classification one-liner" || return
  _assert_missing "$TASK_EXECUTE_SKILL" "flip the classification" "legacy wrong-flip mechanism" || return
  pass_test
}

test_task_execute_no_legacy_classification() {
  start_test "task-execute no longer classifies as 行为修订 vs Bug 修复"
  _assert_missing "$TASK_EXECUTE_SKILL" "**行为修订**（behavior" "legacy 行为修订 classification" || return
  _assert_missing "$TASK_EXECUTE_SKILL" "**Bug 修复**（bug" "legacy Bug 修复 classification" || return
  _assert_missing "$TASK_EXECUTE_SKILL" "Classification signal guide" "legacy classification signal guide" || return
  pass_test
}

# task-submit 不重复定义；引用新规则

test_task_submit_references_feedback_loop_rules() {
  start_test "task-submit references 反馈循环规则 as authority"
  _assert_contains "$TASK_SUBMIT_SKILL" "task-execute" "task-execute reference" || return
  _assert_contains "$TASK_SUBMIT_SKILL" "反馈循环规则" "反馈循环规则 reference" || return
  pass_test
}

test_task_submit_no_legacy_terms() {
  start_test "task-submit drops legacy DX RU3 / wrong-flip language"
  _assert_missing "$TASK_SUBMIT_SKILL" "DX RU3" "legacy DX RU3 marker" || return
  _assert_missing "$TASK_SUBMIT_SKILL" "PM 反馈分流策略" "legacy 分流策略 reference" || return
  _assert_missing "$TASK_SUBMIT_SKILL" "行为修订 path" "legacy behavior path" || return
  _assert_missing "$TASK_SUBMIT_SKILL" "Bug 修复 path" "legacy bug path" || return
  pass_test
}

# close-task §0 扫描范围 + 读取文档对齐预告

test_close_task_scans_v3_typed_zones() {
  start_test "close-task §0 scans v3 typed contract zones（关键产品决策 已移 prd.md）"
  # delta-2：🎯 关键产品决策 移出 task 文件进 prd.md；close-task §0 改扫 v3 三区
  _assert_contains "$CLOSE_TASK_SKILL" "🔧 实现规格" "§🔧 实现规格 in close-task §0 scan scope" || return
  _assert_contains "$CLOSE_TASK_SKILL" "🧩 实现设计引用" "§🧩 实现设计引用 in close-task §0 scan scope" || return
  pass_test
}

test_close_task_reads_doc_alignment_preview() {
  start_test "close-task §0 reads 文档对齐预告 as alignment cue"
  _assert_contains "$CLOSE_TASK_SKILL" "文档对齐预告" "文档对齐预告 cited in close-task §0" || return
  pass_test
}

# 模板对齐

test_task_template_has_doc_alignment_preview_field() {
  start_test "task.md.tmpl execution report has 文档对齐预告 field"
  _assert_contains "$TASK_TMPL" "文档对齐预告" "文档对齐预告 in task template" || return
  pass_test
}

test_task_execute_has_feedback_loop_rules
test_task_execute_only_changes_prototype_code
test_task_execute_has_doc_alignment_preview_field
test_task_execute_has_conflict_resolution
test_task_execute_blocks_only_on_implementation_ambiguity
test_task_execute_no_legacy_triage
test_task_execute_no_legacy_classification
test_task_submit_references_feedback_loop_rules
test_task_submit_no_legacy_terms
test_close_task_scans_v3_typed_zones
test_close_task_reads_doc_alignment_preview
test_task_template_has_doc_alignment_preview_field

report_results "task-pm-feedback"
