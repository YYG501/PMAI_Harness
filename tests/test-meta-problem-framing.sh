#!/usr/bin/env bash
# Static regression tests for /pmai-meta as PMAI 问题会诊.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
META_SKILL="$REPO_ROOT/skills/meta/SKILL.md"
PROBLEM_FRAMING="$REPO_ROOT/skills/meta/references/problem-framing.md"
PRODUCT_IDEA="$REPO_ROOT/skills/meta/references/product-idea-framing.md"
WORKFLOW_DECISION="$REPO_ROOT/skills/meta/references/pmai-workflow-decision.md"
TOOLBOX="$REPO_ROOT/skills/meta/references/thinking-toolbox.md"
LEXICON="$REPO_ROOT/skills/meta/references/词表与句式.md"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
LEGACY_WORD="office"
FORBIDDEN_REF="${LEGACY_WORD}-hours-method.md"
FORBIDDEN_PATTERN="${LEGACY_WORD}[ _-]?hours?"

test_meta_skill_is_problem_framing_entry() {
  start_test "meta skill: 保留 /pmai-meta，定位为问题会诊"

  assert_file_contains "$META_SKILL" "name: pmai-meta" "command name should stay pmai-meta" || return
  assert_file_contains "$META_SKILL" "/pmai-meta · 问题会诊" "skill title should expose diagnosis positioning" || return
  assert_file_contains "$META_SKILL" "PMAI 问题会诊" "description should use PMAI's own naming" || return
  assert_file_contains "$META_SKILL" "升维分析输出器" "skill should reject analysis-generator behavior" || return
  assert_file_contains "$META_SKILL" "只是复述" "trigger should include shallow-restatement feedback" || return
  assert_file_contains "$META_SKILL" "没新思路" "trigger should include no-new-thinking feedback" || return
  assert_file_contains "$META_SKILL" "grillme" "trigger should include grillme wording" || return
  if grep -Eiq "$FORBIDDEN_PATTERN" "$META_SKILL" "$PROBLEM_FRAMING" "$PRODUCT_IDEA" "$WORKFLOW_DECISION" "$TOOLBOX" 2>/dev/null; then
    _fail "当前 meta 文件不应再出现外部英文命名"
    return
  fi
  pass_test
}

test_meta_references_are_neutral_and_complete() {
  start_test "meta references: 引用通用门禁、两条专用路径和工具箱/词表"

  assert_file_exists "$PROBLEM_FRAMING" "problem-framing reference should exist" || return
  assert_file_exists "$PRODUCT_IDEA" "product idea reference should exist" || return
  assert_file_exists "$WORKFLOW_DECISION" "workflow decision reference should exist" || return
  assert_file_exists "$TOOLBOX" "thinking toolbox reference should exist" || return
  assert_file_exists "$LEXICON" "lexicon reference should remain" || return
  assert_file_contains "$META_SKILL" "references/problem-framing.md" "skill should reference problem-framing" || return
  assert_file_contains "$META_SKILL" "references/product-idea-framing.md" "skill should reference product idea framing" || return
  assert_file_contains "$META_SKILL" "references/pmai-workflow-decision.md" "skill should reference workflow decision" || return
  assert_file_contains "$META_SKILL" "references/thinking-toolbox.md" "skill should reference thinking toolbox" || return
  assert_file_contains "$META_SKILL" "references/词表与句式.md" "skill should reference lexicon" || return
  if grep -q "$FORBIDDEN_REF" "$META_SKILL" "$PROBLEM_FRAMING" "$PRODUCT_IDEA" "$WORKFLOW_DECISION" "$TOOLBOX" 2>/dev/null; then
    _fail "不应使用旧 method 文件名作为 PMAI 文件名或引用"
    return
  fi
  pass_test
}

test_problem_framing_contains_hard_conversation_rules() {
  start_test "problem-framing: 锁定会话门禁"

  assert_file_contains "$PROBLEM_FRAMING" "Read Gate" "must include read gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "One Question Gate" "must include one question gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "推荐默认答案" "must include recommended default answer" || return
  assert_file_contains "$PROBLEM_FRAMING" "追问表层答案" "must push past surface answers" || return
  assert_file_contains "$PROBLEM_FRAMING" "Premise Gate" "must include premise gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "Alternatives Gate" "must include alternatives gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "Coverage Gate" "must include coverage gate" || return
  assert_file_contains "$PROBLEM_FRAMING" "Handoff Gate" "must force handoff to next step" || return
  assert_file_contains "$PROBLEM_FRAMING" "输出 alternatives 后必须停住" "must stop after alternatives" || return
  pass_test
}

test_toolbox_preserves_existing_meta_assets() {
  start_test "thinking-toolbox: 保留旧 meta 核心资产"

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
  start_test "design/changelog: 对齐 meta 问题会诊定位"

  assert_file_contains "$DESIGN_SKILL" "问题会诊入口（/pmai-meta）" "design should call meta diagnosis entry" || return
  assert_file_contains "$DESIGN_SKILL" "不是新阶段、也不是分析段落生成器" "design should not treat meta as default phase" || return
  assert_file_contains "$DESIGN_SKILL" "只作问题会诊旁路" "design should keep meta optional" || return
  assert_file_contains "$DESIGN_SKILL" "pmai-skill-improve" "design should route skill/workflow changes away from design" || return
  assert_file_contains "$CHANGELOG" "/pmai-meta" "changelog should mention meta" || return
  assert_file_contains "$CHANGELOG" "问题会诊" "changelog should mention diagnosis redesign" || return
  pass_test
}

test_meta_skill_is_problem_framing_entry
test_meta_references_are_neutral_and_complete
test_problem_framing_contains_hard_conversation_rules
test_toolbox_preserves_existing_meta_assets
test_design_and_changelog_reference_new_positioning

report_results "meta-problem-framing"
