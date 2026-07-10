#!/usr/bin/env bash
# Static regression tests for /pmai-meta v2 routes and stop gates.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
META_SKILL="$REPO_ROOT/skills/meta/SKILL.md"
PROBLEM_FRAMING="$REPO_ROOT/skills/meta/references/problem-framing.md"
PRODUCT_IDEA="$REPO_ROOT/skills/meta/references/product-idea-framing.md"
WORKFLOW_DECISION="$REPO_ROOT/skills/meta/references/pmai-workflow-decision.md"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
BUILD_SKILL="$REPO_ROOT/skills/build/SKILL.md"
SPEC_SKILL="$REPO_ROOT/skills/spec-writing/SKILL.md"
DOC_SKILL="$REPO_ROOT/skills/doc-writing/SKILL.md"

test_meta_uses_context_specific_references() {
  start_test "meta v2: 按问题缺口调用产品想法、workflow 与压测素材"

  assert_file_contains "$META_SKILL" "references/product-idea-framing.md" "should include product idea material" || return
  assert_file_contains "$META_SKILL" "references/pmai-workflow-decision.md" "should include workflow decision material" || return
  assert_file_contains "$META_SKILL" "references/thinking-toolbox.md" "should include pressure-test tools" || return
  assert_file_contains "$META_SKILL" "小文案、明确机械动作" "should smart-skip meta when no model issue exists" || return
  pass_test
}

test_product_idea_route_has_real_forcing_questions() {
  start_test "meta v2: 产品想法会诊问题"

  assert_file_contains "$PRODUCT_IDEA" "现状对手" "product route should include status quo competitor" || return
  assert_file_contains "$PRODUCT_IDEA" "需求证据" "product route should include demand evidence" || return
  assert_file_contains "$PRODUCT_IDEA" "具体用户" "product route should include specific user" || return
  assert_file_contains "$PRODUCT_IDEA" "最小切口" "product route should include smallest wedge" || return
  assert_file_contains "$PRODUCT_IDEA" "失败预演" "product route should include premortem" || return
  assert_file_contains "$PRODUCT_IDEA" "下一步验证" "product route should include next validation" || return
  pass_test
}

test_workflow_route_guards_against_new_skill_bias() {
  start_test "meta v2: workflow 决策不默认新建 skill"

  assert_file_contains "$WORKFLOW_DECISION" "先读现状" "workflow route should read existing skills first" || return
  assert_file_contains "$WORKFLOW_DECISION" "没有读相关现状，不准给结论" "workflow route should gate conclusions on reading" || return
  assert_file_contains "$WORKFLOW_DECISION" "调用现有" "workflow route should include call existing option" || return
  assert_file_contains "$WORKFLOW_DECISION" "改现有" "workflow route should include modify existing option" || return
  assert_file_contains "$WORKFLOW_DECISION" "新建入口" "workflow route should include new entry option" || return
  assert_file_contains "$WORKFLOW_DECISION" "先不做" "workflow route should include do nothing option" || return
  assert_file_contains "$WORKFLOW_DECISION" "新建入口”不是默认答案" "workflow route should reject new-skill bias" || return
  assert_file_contains "$WORKFLOW_DECISION" "pmai-skill-improve" "workflow skill changes should route to skill-improve" || return
  assert_file_contains "$WORKFLOW_DECISION" "禁止把 skill / workflow 改造问题交给" "workflow changes should not route to design" || return
  pass_test
}

test_alternatives_gate_requires_stop() {
  start_test "meta v2: Alternatives 后必须停住"

  assert_file_contains "$META_SKILL" "然后停住让 PM 选择" "main skill should stop after real alternatives" || return
  assert_file_contains "$META_SKILL" "不强制凑 2–3 个方案" "main skill should not invent fake alternatives" || return
  assert_file_contains "$PROBLEM_FRAMING" "输出 alternatives 后必须停住" "reference should stop after alternatives" || return
  assert_file_contains "$PROBLEM_FRAMING" "推荐完直接改文件" "reference should forbid mutating after alternatives" || return
  pass_test
}

test_downstream_skills_use_internal_capability_language() {
  start_test "meta v2: 下游 skill 路由口径"

  assert_file_contains "$DESIGN_SKILL" "处理 PMAI skill / workflow 自身的反馈" "design should not own workflow changes" || return
  assert_file_contains "$DESIGN_SKILL" '交 `/pmai-skill-improve`' "workflow feedback should route to skill-improve" || return
  assert_file_contains "$BUILD_SKILL" "未决问题，停止 build，返回 design" "build should return unresolved product questions" || return
  assert_file_contains "$SPEC_SKILL" "多视角冷读（可选）" "spec-writing should preserve optional pressure testing" || return
  assert_file_contains "$DOC_SKILL" "已有材料压测" "doc-writing should preserve material pressure testing" || return
  pass_test
}

test_meta_uses_context_specific_references
test_product_idea_route_has_real_forcing_questions
test_workflow_route_guards_against_new_skill_bias
test_alternatives_gate_requires_stop
test_downstream_skills_use_internal_capability_language

report_results "meta-v2-routes"
