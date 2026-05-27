#!/usr/bin/env bash
# test-new-req-no-arg-prompt.sh
#
# 验证 /pmai-new-req 无参数兜底文案被严格规定（PM 实测踩坑修复）：
#   T1: SKILL.md 含「步骤 0：获取需求描述」节
#   T2: 标准问法被严格固定为「请告诉我新需求是什么（一句话）。」
#   T3: 明示禁止 slug / 编号 / worktree 工程黑话
#   T4: 明示禁止「我才能...」条件句式 (防"我才能生成 slug、确定编号、拉 worktree")
#
# 背景：PM 实测跑 /pmai-new-req 无参数，AI 编出长文案：
#   "你这次 /pmai-new-req 没带参数。请先告诉我这个新需求是什么（一句话即可，
#    例如「实现用户登录」「租户内角色批量改名」），我才能生成 slug、确定
#    编号、拉 worktree。"
# SKILL.md 无步骤 0，AI 临场编工程黑话。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$REPO_ROOT/skills/new-req/SKILL.md"

# -----------------------------------------------------------------
test_skill_has_step_0() {
  start_test "T1: SKILL.md 含 步骤 0：获取需求描述"
  if ! grep -q '步骤 0：获取需求描述' "$SKILL_FILE"; then
    _fail "skills/new-req/SKILL.md 缺「步骤 0：获取需求描述」节"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_standard_prompt_fixed() {
  start_test "T2: 标准问法严格固定为「请告诉我新需求是什么（一句话）。」"
  if ! grep -q '请告诉我新需求是什么（一句话）。' "$SKILL_FILE"; then
    _fail "SKILL.md 缺标准问法严格全句（防 AI 临场编替代版）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_forbids_engineering_jargon() {
  start_test "T3: 明示禁止 slug / 编号 / worktree 工程黑话"
  for word in slug 编号 worktree; do
    if ! grep -q "$word" "$SKILL_FILE"; then
      _fail "SKILL.md 缺禁忌词 $word 说明（PM 视图规则）"
      return
    fi
  done
  # 确认是在"禁止扩展"语境（不是别处的工程描述）
  if ! grep -q '禁止扩展' "$SKILL_FILE"; then
    _fail "SKILL.md 缺「禁止扩展」语境标记"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_forbids_conditional_phrasing() {
  start_test "T4: 明示禁止「我才能...」条件句式"
  if ! grep -q '不写"我才能' "$SKILL_FILE"; then
    _fail "SKILL.md 缺禁忌「我才能...」条件句式说明"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_skill_has_step_0
test_standard_prompt_fixed
test_forbids_engineering_jargon
test_forbids_conditional_phrasing

report_results "new-req-no-arg-prompt"
