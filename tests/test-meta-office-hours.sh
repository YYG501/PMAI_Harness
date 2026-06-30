#!/usr/bin/env bash
# Static regression tests for /pmai-meta as PMAI Office Hours.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
META_SKILL="$REPO_ROOT/skills/meta/SKILL.md"
PROBLEM_FRAMING="$REPO_ROOT/skills/meta/references/problem-framing.md"
TOOLBOX="$REPO_ROOT/skills/meta/references/thinking-toolbox.md"
LEXICON="$REPO_ROOT/skills/meta/references/词表与句式.md"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"
FORBIDDEN_REF="office-hours-"
FORBIDDEN_REF="${FORBIDDEN_REF}method.md"

test_meta_skill_is_office_hours_entry() {
  start_test "meta skill: 保留 /pmai-meta，定位为 Office Hours"

  assert_file_contains "$META_SKILL" "name: pmai-meta" "command name should stay pmai-meta" || return
  assert_file_contains "$META_SKILL" "/pmai-meta · Office Hours" "skill title should expose Office Hours positioning" || return
  assert_file_contains "$META_SKILL" "升维分析输出器" "skill should reject analysis-generator behavior" || return
  assert_file_contains "$META_SKILL" "只是复述" "trigger should include shallow-restatement feedback" || return
  assert_file_contains "$META_SKILL" "没新思路" "trigger should include no-new-thinking feedback" || return
  assert_file_contains "$META_SKILL" "grillme" "trigger should include grillme wording" || return
  pass_test
}

test_meta_references_are_neutral_and_complete() {
  start_test "meta references: 使用中性 problem-framing 名称并引用工具箱/词表"

  assert_file_exists "$PROBLEM_FRAMING" "problem-framing reference should exist" || return
  assert_file_exists "$TOOLBOX" "thinking toolbox reference should exist" || return
  assert_file_exists "$LEXICON" "lexicon reference should remain" || return
  assert_file_contains "$META_SKILL" "references/problem-framing.md" "skill should reference problem-framing" || return
  assert_file_contains "$META_SKILL" "references/thinking-toolbox.md" "skill should reference thinking toolbox" || return
  assert_file_contains "$META_SKILL" "references/词表与句式.md" "skill should reference lexicon" || return
  if grep -q "$FORBIDDEN_REF" "$META_SKILL" "$PROBLEM_FRAMING" "$TOOLBOX" 2>/dev/null; then
    _fail "不应使用旧 method 文件名作为 PMAI 文件名或引用"
    return
  fi
  pass_test
}

test_problem_framing_contains_hard_conversation_rules() {
  start_test "problem-framing: 锁定访谈硬规则"

  assert_file_contains "$PROBLEM_FRAMING" "先读再问" "must read before asking" || return
  assert_file_contains "$PROBLEM_FRAMING" "一题一问" "must ask one question at a time" || return
  assert_file_contains "$PROBLEM_FRAMING" "推荐默认答案" "must include recommended default answer" || return
  assert_file_contains "$PROBLEM_FRAMING" "追问表层答案" "must push past surface answers" || return
  assert_file_contains "$PROBLEM_FRAMING" "Premise Challenge" "must include premise challenge" || return
  assert_file_contains "$PROBLEM_FRAMING" "Alternatives" "must include alternatives" || return
  assert_file_contains "$PROBLEM_FRAMING" "Coverage Check" "must include coverage check" || return
  assert_file_contains "$PROBLEM_FRAMING" "降回下一步" "must force handoff to next step" || return
  assert_file_contains "$PROBLEM_FRAMING" "业务语言提问" "must use business language" || return
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
  start_test "design/changelog: 对齐 meta Office Hours 定位"

  assert_file_contains "$DESIGN_SKILL" "问题对焦入口（/pmai-meta）" "design should call meta problem-framing entry" || return
  assert_file_contains "$DESIGN_SKILL" "不是新阶段、也不是分析段落生成器" "design should not treat meta as default phase" || return
  assert_file_contains "$DESIGN_SKILL" "只作问题对焦旁路" "design should keep meta optional" || return
  assert_file_contains "$CHANGELOG" "/pmai-meta" "changelog should mention meta" || return
  assert_file_contains "$CHANGELOG" "Office Hours" "changelog should mention Office Hours redesign" || return
  pass_test
}

test_meta_skill_is_office_hours_entry
test_meta_references_are_neutral_and_complete
test_problem_framing_contains_hard_conversation_rules
test_toolbox_preserves_existing_meta_assets
test_design_and_changelog_reference_new_positioning

report_results "meta-office-hours"
