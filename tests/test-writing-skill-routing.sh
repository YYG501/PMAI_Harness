#!/usr/bin/env bash
# Regressions for writing skill routing and product-direction doc writing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HUMANIZE="$REPO_ROOT/skills/humanize/SKILL.md"
PRD="$REPO_ROOT/skills/prd-writing/SKILL.md"
DOC="$REPO_ROOT/skills/doc-writing/SKILL.md"
DOC_REF="$REPO_ROOT/skills/doc-writing/references/product-direction.md"

test_humanize_remains_entry_but_expression_only() {
  start_test "humanize: 保留入口，但只负责表达层"

  assert_file_contains "$HUMANIZE" "入口保留" "humanize should remain a standalone entry" || return
  assert_file_contains "$HUMANIZE" "只动表达，不动信息" "humanize should be expression-only" || return
  assert_file_contains "$HUMANIZE" "整体优化结构、内容、文风" "humanize should route whole-document optimization away" || return
  assert_file_contains "$HUMANIZE" "/pmai-doc-writing" "humanize should route product docs to doc-writing" || return
  pass_test
}

test_prd_writing_owns_functional_doc_optimization() {
  start_test "prd-writing: 功能型文档整体优化覆盖结构/内容/文风"

  assert_file_contains "$PRD" "优化已有功能型文档" "prd-writing should expose existing-doc optimization mode" || return
  assert_file_contains "$PRD" "整体优化结构、内容、文风" "prd-writing should match PM wording" || return
  assert_file_contains "$PRD" "结构 / 内容 / 文风" "prd-writing should split optimization layers" || return
  assert_file_contains "$PRD" "/pmai-humanize" "prd-writing should use humanize as final wording pass" || return
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
  assert_file_contains "$DOC" "/pmai-prd-writing" "doc-writing should route functional docs away" || return
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

  assert_file_contains "$PRD" "不要把它降级成 \`/pmai-humanize\` 纯润色" "prd-writing should not downgrade whole-doc work" || return
  assert_file_contains "$DOC" "不要让 humanize 改产品判断" "doc-writing should keep product judgment ownership" || return
  pass_test
}

test_humanize_remains_entry_but_expression_only
test_prd_writing_owns_functional_doc_optimization
test_doc_writing_supports_product_direction_docs
test_doc_writing_has_product_direction_reference
test_humanize_not_primary_for_whole_doc_rewrite

report_results "writing-skill-routing"
