#!/usr/bin/env bash
# Static regression tests for /pmai-meta as 产品判断模型.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
META_SKILL="$REPO_ROOT/skills/meta/SKILL.md"
MODEL="$REPO_ROOT/skills/meta/references/product-meta-thinking.md"
PROBLEM_FRAMING="$REPO_ROOT/skills/meta/references/problem-framing.md"
PRODUCT_IDEA="$REPO_ROOT/skills/meta/references/product-idea-framing.md"
TOOLBOX="$REPO_ROOT/skills/meta/references/thinking-toolbox.md"
GSTACK_CONTRACT="$REPO_ROOT/skills/_shared/gstack-integration.md"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

test_meta_skill_declares_product_judgment_model() {
  start_test "meta: 产品元思考入口与产品判断模型"

  assert_file_contains "$META_SKILL" "/pmai-meta · 产品元思考" "skill title should expose product meta thinking" || return
  assert_file_contains "$META_SKILL" "产品判断模型" "skill should use product judgment model as artifact" || return
  assert_file_contains "$MODEL" "用追问和压测，把表层诉求建成" "model reference should define core method" || return
  assert_file_contains "$META_SKILL" "product-meta-thinking.md" "skill should reference model methodology" || return
  assert_file_contains "$META_SKILL" "problem-framing.md" "skill should reference question discipline" || return
  assert_file_contains "$META_SKILL" "thinking-toolbox.md" "skill should reference thinking toolbox" || return
  pass_test
}

test_model_file_defines_five_parts() {
  start_test "product-meta-thinking: 五个模型部件"

  assert_file_exists "$MODEL" "product-meta-thinking reference should exist" || return
  assert_file_contains "$MODEL" "产品判断模型" "model file should be named by artifact" || return
  assert_file_contains "$MODEL" "判断句" "model should include judgment sentence" || return
  assert_file_contains "$MODEL" "地基账本" "model should include foundation ledger" || return
  assert_file_contains "$MODEL" "判断标准" "model should include judgment standard" || return
  assert_file_contains "$MODEL" "模型轴" "model should include model axis" || return
  assert_file_contains "$MODEL" "分路" "model should include alternatives" || return
  pass_test
}

test_external_sources_are_absorbed_not_frontend_structure() {
  start_test "product-meta-thinking: 外部来源只是吸收来源"

  assert_file_contains "$MODEL" "来源如何被消化" "model should explain source digestion" || return
  assert_file_contains "$MODEL" "不允许成为 \`/pmai-meta\` 的主结构层或前台品牌" "external methods should not be foreground structure" || return
  assert_file_contains "$MODEL" "PMAI 原有方法" "model should preserve PMAI methods" || return
  assert_file_contains "$MODEL" "gstack / office-hours" "model should absorb office-hours material" || return
  assert_file_contains "$MODEL" "grill" "model should absorb grill discipline" || return
  assert_file_contains "$MODEL" "不 runtime 调 gstack" "meta should not call gstack at runtime" || return
  pass_test
}

test_problem_framing_disciplines_model_completion() {
  start_test "problem-framing: 补齐模型的问法纪律"

  assert_file_contains "$PROBLEM_FRAMING" "补齐模型字段" "problem framing should serve model completion" || return
  assert_file_contains "$PROBLEM_FRAMING" "一题一问" "should ask one question at a time" || return
  assert_file_contains "$PROBLEM_FRAMING" "推荐默认答案" "should include recommended defaults" || return
  assert_file_contains "$PROBLEM_FRAMING" "短答追后果" "should pursue consequences after short answers" || return
  assert_file_contains "$PROBLEM_FRAMING" "依赖决策树" "should ask along dependency tree" || return
  assert_file_contains "$PROBLEM_FRAMING" "能从项目资料" "should not ask what files can answer" || return
  assert_file_contains "$PROBLEM_FRAMING" "输出 alternatives 后必须停住" "should stop after alternatives" || return
  pass_test
}

test_product_idea_contains_office_hours_material() {
  start_test "product-idea-framing: office-hours 素材 PMAI 化"

  assert_file_contains "$PRODUCT_IDEA" "产品想法模型素材库" "product idea file should be material library" || return
  assert_file_contains "$PRODUCT_IDEA" "需求证据" "should include demand evidence" || return
  assert_file_contains "$PRODUCT_IDEA" "现状对手" "should include status quo competitor" || return
  assert_file_contains "$PRODUCT_IDEA" "具体用户" "should include specific user" || return
  assert_file_contains "$PRODUCT_IDEA" "最小切口" "should include smallest wedge" || return
  assert_file_contains "$PRODUCT_IDEA" "观察意外" "should include observation surprise" || return
  assert_file_contains "$PRODUCT_IDEA" "未来适配" "should include future fit" || return
  assert_file_contains "$PRODUCT_IDEA" "Smart Routing" "should route questions intelligently" || return
  pass_test
}

test_toolbox_preserves_original_meta_engines() {
  start_test "thinking-toolbox: 保留旧 meta 核心资产"

  assert_file_contains "$TOOLBOX" "升维 / 换高度" "should preserve height-shift name" || return
  assert_file_contains "$TOOLBOX" "第一性原理" "should preserve first-principles name" || return
  assert_file_contains "$TOOLBOX" "多视角压测" "should preserve multi-perspective pressure test" || return
  assert_file_contains "$TOOLBOX" "UI 信息 / 任务 / 判断层" "should preserve UI three-layer framing" || return
  assert_file_contains "$TOOLBOX" "地基账本" "first principles should map to foundation ledger" || return
  assert_file_contains "$TOOLBOX" "分路压测" "pressure test should map to alternatives" || return
  if grep -q "判断上移" "$TOOLBOX" || grep -q "前提重推" "$TOOLBOX"; then
    _fail "thinking toolbox should not replace original section names with new labels"
    return
  fi
  pass_test
}

test_boundaries_and_changelog_are_updated() {
  start_test "boundaries: gstack/design/changelog 对齐模型内核"

  assert_file_contains "$GSTACK_CONTRACT" "产品判断模型" "gstack contract should name PMAI artifact" || return
  assert_file_contains "$GSTACK_CONTRACT" "不 runtime 调 gstack" "gstack contract should forbid runtime meta call" || return
  assert_file_contains "$GSTACK_CONTRACT" "不把 office-hours / grillme 作为 PMAI 主品牌" "gstack contract should reject external branding" || return
  assert_file_contains "$DESIGN_SKILL" "按需自动进入 meta，再返回 design" "design should call meta internally" || return
  assert_file_contains "$DESIGN_SKILL" "危险前提、反例和推荐" "design should require model-level output" || return
  assert_file_contains "$DESIGN_SKILL" "出现任一信号时" "design should not make meta a default phase" || return
  assert_file_contains "$CHANGELOG" "收敛为产品判断模型" "changelog should record this convergence" || return
  pass_test
}

test_meta_skill_declares_product_judgment_model
test_model_file_defines_five_parts
test_external_sources_are_absorbed_not_frontend_structure
test_problem_framing_disciplines_model_completion
test_product_idea_contains_office_hours_material
test_toolbox_preserves_original_meta_engines
test_boundaries_and_changelog_are_updated

report_results "meta-product-meta-thinking"
