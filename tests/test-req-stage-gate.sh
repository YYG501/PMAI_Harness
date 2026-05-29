#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REQ_STAGE_GATE_SKILL="$FRAMEWORK_ROOT/skills/req-stage-gate/SKILL.md"

# ---------------------------------------------------------------------------
# 六步重构（office-hours 收敛）：req-stage-gate 从旧 7-stage 编排引擎
# 改写为薄「异常恢复入口」壳。主推进驱动已搬 /pmai-next。
#
# 旧断言（stage 6→7 步骤 / closed-task 校验契约 / 变更记录排除算法 /
# boundary cases / stage 5→6 契约）已随 7-stage 编排逻辑整体砍掉——
# 这些能力现在归 /pmai-next 与 /pmai-close-req，不再是本 skill 的职责。
# ---------------------------------------------------------------------------

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

_assert_absent() {
  local file="$1"
  local text="$2"
  local desc="$3"
  if _contains "$file" "$text"; then
    _fail "$desc: 仍含已砍内容 '$text'"
    return 1
  fi
  return 0
}

test_thin_shell_declares_not_main_engine() {
  start_test "req-stage-gate 顶部声明：不再是主推进引擎，驱动已搬 /pmai-next"

  _assert_contains "$REQ_STAGE_GATE_SKILL" "异常恢复入口" "薄壳定位声明" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "本 skill 已不是主推进引擎" "明确不是主引擎" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "/pmai-next" "指向 /pmai-next 驱动" || return

  pass_test
}

test_useful_parts_noted_merged_into_next() {
  start_test "req-stage-gate 注明结构决策前置 / worktree 残留检测并入 /pmai-next"

  # 结构决策前置：注明已并入 /pmai-next
  _assert_contains "$REQ_STAGE_GATE_SKILL" "结构决策前置" "结构决策前置指针" || return
  # worktree 残留检测：本 skill 异常恢复时保留
  _assert_contains "$REQ_STAGE_GATE_SKILL" "check-worktree-residue.py" "worktree 残留检测保留" || return

  pass_test
}

test_six_step_semantics_no_seven_stage() {
  start_test "req-stage-gate 用六步语义，无旧 7-stage 编排残留"

  # 六步阶段名（PM 视图）
  _assert_contains "$REQ_STAGE_GATE_SKILL" "范围确认" "六步阶段名（范围确认）" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "复审" "六步阶段名（复审）" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "沉淀" "六步阶段名（沉淀）" || return

  # 旧 7-stage 编排机制必须已砍
  _assert_absent "$REQ_STAGE_GATE_SKILL" "Stage 过渡逻辑" "旧 Stage 过渡逻辑编排" || return
  _assert_absent "$REQ_STAGE_GATE_SKILL" "req-transition.py" "旧 stage 推进命令" || return
  _assert_absent "$REQ_STAGE_GATE_SKILL" "需求方案" "旧 7-stage 产物名（需求方案 / PRD stage）" || return

  pass_test
}

test_new_artifact_names() {
  start_test "req-stage-gate 引用六步产物名（req-plan / PRODUCT-STATE / prototype）"

  _assert_contains "$REQ_STAGE_GATE_SKILL" "req-plan.md" "新产物 req-plan.md" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "PRODUCT-STATE" "新产物 PRODUCT-STATE" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "prototype/" "新产物 prototype/ 主原型" || return

  pass_test
}

test_no_fabricate_state_fallback() {
  start_test "req-stage-gate 无 active req 兜底不编造"

  _assert_contains "$REQ_STAGE_GATE_SKILL" "目前没有 active req" "无 active req 兜底话术" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "不编造" "防 narrative 幻觉声明" || return

  pass_test
}

test_no_internal_ids_or_jargon() {
  start_test "req-stage-gate 无内部编号 / 工程黑话残留"

  # 旧内部编号（vp-N / delta-N / D13 等）与旧 stage 章节号不应出现在 PM 面文本
  for token in "vp-" "delta-" "D13" "polish-" "Stage 1 → 2" "Stage 5 → 6"; do
    if _contains "$REQ_STAGE_GATE_SKILL" "$token"; then
      _fail "仍含内部编号 / 旧 stage 章节号：$token"
      return
    fi
  done

  pass_test
}

test_thin_shell_declares_not_main_engine
test_useful_parts_noted_merged_into_next
test_six_step_semantics_no_seven_stage
test_new_artifact_names
test_no_fabricate_state_fallback
test_no_internal_ids_or_jargon

report_results "req-stage-gate (六步薄壳)"
