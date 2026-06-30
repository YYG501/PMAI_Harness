#!/usr/bin/env bash
# Regressions for writing skill routing and product-direction doc writing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HUMANIZE="$REPO_ROOT/skills/humanize/SKILL.md"
SPEC="$REPO_ROOT/skills/spec-writing/SKILL.md"
SPEC_TMPL="$REPO_ROOT/skills/spec-writing/templates/prd.md.tmpl"
SPEC_RULES="$REPO_ROOT/skills/spec-writing/references/writing-rules.md"
SPEC_FEWSHOTS="$REPO_ROOT/skills/spec-writing/references/few-shots.md"
PMVIEW="$REPO_ROOT/skills/_shared/PM-VIEW-RULES.md"
PMVIEW_CHECKLIST="$REPO_ROOT/skills/_shared/pm-view/checklist.md"
PMVIEW_WRITING="$REPO_ROOT/skills/_shared/pm-view/writing-rules.md"
CHECK_PRD="$REPO_ROOT/scripts/check-prd-hierarchy.py"
DOC="$REPO_ROOT/skills/doc-writing/SKILL.md"
DOC_REF="$REPO_ROOT/skills/doc-writing/references/product-direction.md"
PUBLISH="$REPO_ROOT/skills/publish-to-lark/SKILL.md"
OLD_WRITING_DIR="$REPO_ROOT/skills/prd""-writing"
OLD_WRITING_COMMAND="/pmai-prd""-writing"

test_humanize_remains_entry_but_expression_only() {
  start_test "humanize: 保留入口，但只负责表达层"

  assert_file_contains "$HUMANIZE" "入口保留" "humanize should remain a standalone entry" || return
  assert_file_contains "$HUMANIZE" "只动表达，不动信息" "humanize should be expression-only" || return
  assert_file_contains "$HUMANIZE" "整体优化结构、内容、文风" "humanize should route whole-document optimization away" || return
  assert_file_contains "$HUMANIZE" "/pmai-doc-writing" "humanize should route product docs to doc-writing" || return
  pass_test
}

test_spec_writing_replaces_prd_writing_entry() {
  start_test "spec-writing: 公开入口替换旧写作入口"

  assert_file_contains "$SPEC" "name: pmai-spec-writing" "spec-writing should expose the new command name" || return
  assert_file_missing "$OLD_WRITING_DIR" "old writing skill directory should not exist" || return
  if grep -q -- "$OLD_WRITING_COMMAND" "$SPEC"; then
    _fail "spec-writing should not keep old command fallback text"
    return
  fi
  pass_test
}

test_spec_writing_owns_functional_doc_optimization() {
  start_test "spec-writing: 功能型规格文档整体优化覆盖结构/内容/文风"

  assert_file_contains "$SPEC" "既有规格补差" "spec-writing should expose existing-spec gap-filling target" || return
  assert_file_contains "$SPEC" "整体优化结构、内容、文风" "spec-writing should match PM wording" || return
  assert_file_contains "$SPEC" "结构 / 内容 / 文风" "spec-writing should split optimization layers" || return
  assert_file_contains "$SPEC" "/pmai-humanize" "spec-writing should use humanize as final wording pass" || return
  pass_test
}

test_spec_writing_keeps_change_notes_brief() {
  start_test "spec-writing: 变更说明必须简要"

  assert_file_contains "$SPEC" "变更说明必须简要" "spec-writing should constrain change notes" || return
  assert_file_contains "$SPEC" "最多不超过 30 字" "spec-writing should make the briefness constraint measurable" || return
  assert_file_contains "$SPEC" "不写原因、过程、背景" "spec-writing should keep rationale out of change notes" || return
  assert_file_contains "$SPEC_TMPL" "主要变更内容必须简要" "PRD template should carry the same change-log constraint" || return
  assert_file_contains "$SPEC_RULES" "变更说明必须简要" "writing rules should carry the change-log constraint" || return
  pass_test
}

test_spec_writing_uses_presets_not_prd_default() {
  start_test "spec-writing: PRD 是 preset，功能需求先选写法"

  assert_file_contains "$SPEC" "功能需求写法选择器" "spec-writing should expose the requirement writing selector" || return
  assert_file_contains "$SPEC" "PRD 体例 preset" "spec-writing should keep PRD as a named preset" || return
  assert_file_contains "$SPEC" "4 列功能表只是特定写法" "spec-writing should not treat 4-column tables as the default world view" || return
  assert_file_contains "$SPEC" "规则收口 / 口径统一" "spec-writing should route rule consolidation away from PRD tables" || return
  assert_file_contains "$SPEC" "状态 / 分类 / 卡片" "spec-writing should cover card/status style specs" || return
  assert_file_contains "$SPEC" "多步流程" "spec-writing should route flows to prose instead of table cells" || return
  pass_test
}

test_pm_view_does_not_force_four_column_tables() {
  start_test "PM-VIEW: 4 列功能表只是表格 preset"

  if grep -q -- "## 五、功能清单格式（强制）" "$PMVIEW"; then
    _fail "PM-VIEW should not keep universal forced feature-list heading"
    return
  fi
  if grep -q -- '适用：模块 `spec.md` / `prd` 中描述具体功能时' "$PMVIEW"; then
    _fail "PM-VIEW should not say module spec/prd always use the same forced format"
    return
  fi
  assert_file_contains "$PMVIEW" "4 列功能表不是所有规格的默认格式" "PM-VIEW should scope 4-column tables as a preset" || return
  assert_file_contains "$PMVIEW" "先选写法，再写功能需求" "PM-VIEW should require writing-style selection first" || return
  assert_file_contains "$PMVIEW_CHECKLIST" "只有选择 4 列功能表 preset 时" "checklist should make table checks conditional" || return
  assert_file_contains "$PMVIEW_CHECKLIST" "不要为满足表格检查" "checklist should reject forced table fitting" || return
  pass_test
}

test_prd_lint_is_scoped_to_prd_preset() {
  start_test "lint: check-prd-hierarchy 只绑定 PRD / 4 列功能表"

  assert_file_contains "$SPEC" "不跑本 lint" "spec-writing should not run PRD lint for all specs" || return
  assert_file_contains "$CHECK_PRD" "本脚本不作为模块 spec.md" "check-prd-hierarchy should document its scoped use" || return
  assert_file_contains "$CHECK_PRD" "PRD 体例或 4 列功能表文档路径" "check-prd-hierarchy usage should name the scoped target" || return
  pass_test
}

test_four_column_preset_does_not_trigger_prd_artifacts() {
  start_test "spec-writing: 4 列表格不自动触发 PRD 原型覆盖"

  assert_file_contains "$SPEC" "显式选择 4 列功能表 preset 但未选择 PRD 体例时，只走 P2.5 的二级 / 三级拆分确认和 P3.5 lint" "4-column preset should only trigger split confirmation and lint" || return
  assert_file_contains "$SPEC" "原型覆盖范围表、§六原型节或完整 PRD 附件" "4-column preset should not imply PRD artifact requirements" || return
  assert_file_contains "$SPEC" "原型覆盖范围表和 §六原型节只属于 PRD 体例" "PRD-only artifacts should be explicitly scoped" || return
  pass_test
}

test_l1_l5_remain_optional_writing_tools() {
  start_test "spec-writing: L1-L5 不恢复成重型硬约束"

  assert_file_contains "$SPEC_RULES" "需要时才用，不强加" "L1-L5 should stay optional in the overview" || return
  assert_file_contains "$SPEC_RULES" "不要为了套 L1，把每条都展开成重型论证" "L1 should reject heavy mandatory expansion" || return
  if grep -q -- "必须用「\\*\\*X。\\*\\* 段落说明」结构" "$SPEC_RULES"; then
    _fail "L1 should not require bold-sentence paragraph structure for every item"
    return
  fi
  if grep -q -- "给出反例 + 反例后果" "$SPEC_RULES"; then
    _fail "L1 should not require counterexample plus consequence as a hard rule"
    return
  fi
  pass_test
}

test_pm_view_section_references_follow_new_numbering() {
  start_test "PM-VIEW: §五重排后的引用不指错小节"

  assert_file_contains "$PMVIEW_WRITING" "PM-VIEW-RULES.md §5.2 的「续行 rowspan」" "rowspan reference should point to table preset section" || return
  assert_file_contains "$PMVIEW_CHECKLIST" "§5.3「换 UI 还成立」判别" "checklist should point to the current business-rule section" || return
  if grep -q -- "§5.1 的「续行 rowspan」" "$PMVIEW_WRITING"; then
    _fail "rowspan reference should not point at §5.1 after §五 was reorganized"
    return
  fi
  if grep -q -- "§5.2「换 UI 还成立」判别" "$PMVIEW_CHECKLIST"; then
    _fail "business-rule reference should not point at old §5.2"
    return
  fi
  pass_test
}

test_few_shots_anchor_spec_before_prd_examples() {
  start_test "few-shots: 先锚定规格写法，再看 PRD 示例"

  assert_file_contains "$SPEC_FEWSHOTS" "# Few-shots：规格写法示例" "few-shots should not be titled as PRD-only examples" || return
  assert_file_contains "$SPEC_FEWSHOTS" "同一主题按不同写法组织" "few-shots should include pattern selection examples" || return
  assert_file_contains "$SPEC_FEWSHOTS" "待办事项卡里的文件确认规则收口" "few-shots should cover the card-rule regression topic" || return
  assert_file_contains "$SPEC_FEWSHOTS" "只有 PRD 体例或动作清单场景才用二级 / 三级功能表" "few-shots should prevent table defaulting" || return
  pass_test
}

test_doc_writing_supports_product_direction_docs() {
  start_test "doc-writing: 支持高质量产品方向文档"

  assert_file_contains "$DOC" "产品方向 memo" "doc-writing should produce product direction memos" || return
  assert_file_contains "$DOC" "高质量标准" "doc-writing should define quality bar" || return
  assert_file_contains "$DOC" "一句主张" "doc-writing should require a clear thesis" || return
  assert_file_contains "$DOC" "关键取舍" "doc-writing should require tradeoffs" || return
  assert_file_contains "$DOC" "产品方向六问" "doc-writing should require product direction questions" || return
  assert_file_contains "$DOC" "每个关键判断都要能对应一个证据来源" "doc-writing should require evidence mapping" || return
  assert_file_contains "$DOC" "异议处理" "doc-writing should handle objections" || return
  assert_file_contains "$DOC" "优化已有介绍型 / 产品方向文档" "doc-writing should optimize existing docs" || return
  assert_file_contains "$DOC" "/pmai-spec-writing" "doc-writing should route functional docs away" || return
  assert_file_contains "$DOC" "/pmai-humanize" "doc-writing should use humanize as final wording pass" || return
  pass_test
}

test_doc_writing_has_product_direction_reference() {
  start_test "doc-writing reference: 吸收社区方法并形成产品方向 playbook"

  assert_file_exists "$DOC_REF" "product direction reference should exist" || return
  assert_file_contains "$DOC_REF" "content-strategy" "reference should cite community content strategy skill" || return
  assert_file_contains "$DOC_REF" "copywriting" "reference should cite community copywriting skill" || return
  assert_file_contains "$DOC_REF" "market-research" "reference should cite community market research skill" || return
  assert_file_contains "$DOC_REF" "产品方向六问" "reference should include six direction questions" || return
  assert_file_contains "$DOC_REF" "证据地图" "reference should include evidence map" || return
  assert_file_contains "$DOC_REF" "高管一页纸" "reference should include executive one-pager template" || return
  assert_file_contains "$DOC_REF" "异议处理清单" "reference should include objection handling checklist" || return
  pass_test
}

test_humanize_not_primary_for_whole_doc_rewrite() {
  start_test "routing: 整体优化不直接降级成 humanize"

  assert_file_contains "$SPEC" "不要把它降级成 \`/pmai-humanize\` 纯润色" "spec-writing should not downgrade whole-doc work" || return
  assert_file_contains "$DOC" "不要让 humanize 改产品判断" "doc-writing should keep product judgment ownership" || return
  pass_test
}

test_path_guidance_prefers_repo_relative_paths() {
  start_test "path guidance: 文档路径优先仓内相对路径"

  assert_file_contains "$SPEC" "优先贴仓内相对路径" "spec-writing custom output path should prefer repo-relative paths" || return
  assert_file_contains "$PUBLISH" "优先用仓内相对路径" "publish-to-lark markdown path should prefer repo-relative paths" || return
  if grep -q -- "贴绝对路径" "$SPEC"; then
    _fail "spec-writing should not ask PM to paste an absolute path by default"
    return
  fi
  if grep -q -- "markdown 文件绝对路径" "$PUBLISH"; then
    _fail "publish-to-lark should not require absolute markdown paths by default"
    return
  fi
  pass_test
}

test_humanize_remains_entry_but_expression_only
test_spec_writing_replaces_prd_writing_entry
test_spec_writing_owns_functional_doc_optimization
test_spec_writing_keeps_change_notes_brief
test_spec_writing_uses_presets_not_prd_default
test_pm_view_does_not_force_four_column_tables
test_prd_lint_is_scoped_to_prd_preset
test_four_column_preset_does_not_trigger_prd_artifacts
test_l1_l5_remain_optional_writing_tools
test_pm_view_section_references_follow_new_numbering
test_few_shots_anchor_spec_before_prd_examples
test_doc_writing_supports_product_direction_docs
test_doc_writing_has_product_direction_reference
test_humanize_not_primary_for_whole_doc_rewrite
test_path_guidance_prefers_repo_relative_paths

report_results "writing-skill-routing"
