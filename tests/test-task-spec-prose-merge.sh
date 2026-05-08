#!/usr/bin/env bash
# task-spec §5 项目级 + req 级 prose 合并契约（4.5d.4）
#
# 验证 task-spec SKILL 的 §5 子段：
# - A 层 4 档行为表（prototype/system/custom/unknown）
# - B 层 「无变更」/ 留空 / 含变更 三档行为
# - 已删冲突阻断（冲突由 PM 在 close-req step 2c 自决）
# - 拼接结果模板（A 层 + B 层 + 具体实现要求 三段）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_SPEC_SKILL="$REPO_ROOT/skills/task-spec/SKILL.md $REPO_ROOT/skills/task-spec/references/engineering-impl-prose-merge.md"

test_a_layer_four_archetype_table() {
  start_test "§5 A 层档位行为表覆盖 prototype/system/custom/unknown 四档"
  for arch in "prototype" "system" "custom" "unknown"; do
    if ! grep -q "$arch" $TASK_SPEC_SKILL; then
      _fail "§5 A 层应描述 $arch 档行为"
      return
    fi
  done
  pass_test
}

test_b_layer_three_states() {
  start_test "§5 B 层覆盖三态：无变更 / 留空 / 含变更"
  if ! grep -q "无变更" $TASK_SPEC_SKILL; then
    _fail "B 层应描述「无变更」处理（按 A 层单源）"
    return
  fi
  if ! grep -q "section 不存在\|留空" $TASK_SPEC_SKILL; then
    _fail "B 层应描述「section 不存在 / 留空」兼容（旧 req）"
    return
  fi
  if ! grep -q "含变更描述\|内容含变更" $TASK_SPEC_SKILL; then
    _fail "B 层应描述「含变更描述」时的覆盖语义"
    return
  fi
  pass_test
}

test_no_conflict_blocking() {
  start_test "§5 已移除双源机械冲突阻断（4.5d.4）"
  if ! grep -q "不再做项目级 vs req 级的冲突检测\|无机械冲突阻断\|冲突由 PM.*close-req.*自决" $TASK_SPEC_SKILL; then
    _fail "§5 应明确说明已移除冲突阻断、冲突由 PM 在 close-req 决"
    return
  fi
  pass_test
}

test_unknown_fallback_does_not_block() {
  start_test "§5 unknown 档 / A 层缺失时 fallback 不阻断"
  if ! grep -q "fallback" $TASK_SPEC_SKILL; then
    _fail "§5 应有 A 层缺失的 fallback 描述"
    return
  fi
  if ! grep -q "不阻断\|按 B 层单源生成" $TASK_SPEC_SKILL; then
    _fail "§5 fallback 应说明不阻断 task-spec"
    return
  fi
  pass_test
}

test_engineering_contract_section5_template() {
  start_test "§5 拼接结果含三段：A 层 / B 层 / 具体实现要求"
  if ! grep -q "工程结构约束（项目级，A 层）" $TASK_SPEC_SKILL; then
    _fail "§5 输出模板应有「工程结构约束（项目级，A 层）」一节"
    return
  fi
  if ! grep -q "本轮实现深度变更（req 级，B 层）" $TASK_SPEC_SKILL; then
    _fail "§5 输出模板应有「本轮实现深度变更（req 级，B 层）」一节"
    return
  fi
  if ! grep -q "具体实现要求" $TASK_SPEC_SKILL; then
    _fail "§5 输出模板应有「具体实现要求」一节"
    return
  fi
  pass_test
}

test_pm_handfilled_path() {
  start_test "§5 PM 手填段（删 auto-detected 标）按手填内容执行"
  if ! grep -q "auto-detected 标后视为 PM 手填\|auto-detected 标.*PM 手填\|删 auto-detected" $TASK_SPEC_SKILL; then
    _fail "§5 应说明删 auto-detected 标后框架不再覆盖（按 PM 手填执行）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_a_layer_four_archetype_table
test_b_layer_three_states
test_no_conflict_blocking
test_unknown_fallback_does_not_block
test_engineering_contract_section5_template
test_pm_handfilled_path

report_results "task-spec-prose-merge"
