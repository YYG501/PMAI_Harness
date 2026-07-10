#!/usr/bin/env bash
# Static regression tests for /pmai-meta question gates.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
META_SKILL="$REPO_ROOT/skills/meta/SKILL.md"
MODEL="$REPO_ROOT/skills/meta/references/product-meta-thinking.md"
PROBLEM_FRAMING="$REPO_ROOT/skills/meta/references/problem-framing.md"
PRODUCT_IDEA="$REPO_ROOT/skills/meta/references/product-idea-framing.md"
WORKFLOW_DECISION="$REPO_ROOT/skills/meta/references/pmai-workflow-decision.md"
TOOLBOX="$REPO_ROOT/skills/meta/references/thinking-toolbox.md"
LEXICON="$REPO_ROOT/skills/meta/references/词表与句式.md"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

test_meta_skill_is_product_meta_entry() {
  start_test "meta skill: 保留 /pmai-meta，定位为产品元思考"

  assert_file_contains "$META_SKILL" "name: pmai-meta" "command name should stay pmai-meta" || return
  assert_file_contains "$META_SKILL" "/pmai-meta · 产品元思考与判断模型" "skill title should expose product meta thinking" || return
  assert_file_contains "$META_SKILL" "产品判断模型" "description should use PMAI's own artifact" || return
  assert_file_contains "$META_SKILL" "不是升维分析输出器" "skill should reject analysis-generator behavior" || return
  assert_file_contains "$META_SKILL" "只是复述" "trigger should include shallow-restatement feedback" || return
  assert_file_contains "$META_SKILL" "没新思路" "trigger should include no-new-thinking feedback" || return
  assert_file_contains "$META_SKILL" "grillme" "skill should retain grillme questioning discipline" || return
  assert_file_contains "$META_SKILL" "不 runtime 调 gstack" "skill should not runtime call gstack" || return
  pass_test
}

test_meta_references_are_complete() {
  start_test "meta references: 引用模型、门禁、两条专用路径和工具箱/词表"

  assert_file_exists "$MODEL" "product meta thinking reference should exist" || return
  assert_file_exists "$PROBLEM_FRAMING" "problem-framing reference should exist" || return
  assert_file_exists "$PRODUCT_IDEA" "product idea reference should exist" || return
  assert_file_exists "$WORKFLOW_DECISION" "workflow decision reference should exist" || return
  assert_file_exists "$TOOLBOX" "thinking toolbox reference should exist" || return
  assert_file_exists "$LEXICON" "lexicon reference should remain" || return
  assert_file_contains "$META_SKILL" "references/product-meta-thinking.md" "skill should reference product meta thinking" || return
  assert_file_contains "$META_SKILL" "references/problem-framing.md" "skill should reference problem-framing" || return
  assert_file_contains "$META_SKILL" "references/product-idea-framing.md" "skill should reference product idea framing" || return
  assert_file_contains "$META_SKILL" "references/pmai-workflow-decision.md" "skill should reference workflow decision" || return
  assert_file_contains "$META_SKILL" "references/thinking-toolbox.md" "skill should reference thinking toolbox" || return
  assert_file_contains "$META_SKILL" "references/词表与句式.md" "skill should reference lexicon" || return
  pass_test
}

test_problem_framing_contains_hard_conversation_rules() {
  start_test "problem-framing: 锁定补模型问法门禁"

  assert_file_contains "$PROBLEM_FRAMING" "Read Gate" "must include read gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "One Question Gate" "must include one question gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "推荐默认答案" "must include recommended default answer" || return
  assert_file_contains "$PROBLEM_FRAMING" "依赖决策树" "must ask along dependency tree" || return
  assert_file_contains "$PROBLEM_FRAMING" "短答追后果" "must pursue consequences after short answers" || return
  assert_file_contains "$PROBLEM_FRAMING" "Premise Gate" "must include premise gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "Alternatives Gate" "must include alternatives gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "Coverage Check" "must include coverage check" || return
  assert_file_contains "$PROBLEM_FRAMING" "Handoff Gate" "must force handoff to next step" || return
  assert_file_contains "$PROBLEM_FRAMING" "输出 alternatives 后必须停住" "must stop after alternatives" || return
  assert_file_contains "$PROBLEM_FRAMING" "能从项目资料" "must avoid asking what files can answer" || return
  pass_test
}

test_toolbox_preserves_existing_meta_assets() {
  start_test "thinking-toolbox: 保留旧 meta 核心资产"

  assert_file_contains "$TOOLBOX" "升维 / 换高度" "should preserve height-shift tool" || return
  assert_file_contains "$TOOLBOX" "更高判断标准" "should preserve higher-standard framing" || return
  assert_file_contains "$TOOLBOX" "第一性原理" "should preserve first-principles tool" || return
  assert_file_contains "$TOOLBOX" "多视角压测" "should preserve pressure-test tool" || return
  assert_file_contains "$TOOLBOX" "信息层" "should preserve UI information layer" || return
  assert_file_contains "$TOOLBOX" "任务层" "should preserve UI task layer" || return
  assert_file_contains "$TOOLBOX" "判断层" "should preserve UI judgment layer" || return
  assert_file_contains "$TOOLBOX" "词表与句式.md" "should keep lexicon as expression check" || return
  pass_test
}

test_design_and_changelog_reference_new_positioning() {
  start_test "design/changelog: 对齐 meta 产品判断模型定位"

  assert_file_contains "$DESIGN_SKILL" "按需自动进入 meta，再返回 design" "design should call meta as an internal capability" || return
  assert_file_contains "$DESIGN_SKILL" "危险前提、反例和推荐" "design should require new product judgment" || return
  assert_file_contains "$DESIGN_SKILL" "meta 不生成平行状态或长期文档" "design should not treat meta as a parallel stage" || return
  assert_file_contains "$DESIGN_SKILL" "出现任一信号时" "design should keep meta conditional" || return
  assert_file_contains "$DESIGN_SKILL" "pmai-skill-improve" "design should route skill/workflow changes away from design" || return
  assert_file_contains "$CHANGELOG" "/pmai-meta" "changelog should mention meta" || return
  assert_file_contains "$CHANGELOG" "产品判断模型" "changelog should mention model convergence" || return
  pass_test
}

test_meta_skill_is_product_meta_entry
test_meta_references_are_complete
test_problem_framing_contains_hard_conversation_rules
test_toolbox_preserves_existing_meta_assets
test_design_and_changelog_reference_new_positioning

report_results "meta-problem-framing"
