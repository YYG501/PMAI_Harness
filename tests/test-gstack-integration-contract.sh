#!/usr/bin/env bash
# Static regression tests for PMAI x gstack integration contract.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$REPO_ROOT/skills/_shared/gstack-integration.md"

test_contract_exists_and_classifies_integration() {
  start_test "gstack contract: 四类结合方式"

  assert_file_exists "$CONTRACT" "gstack integration contract should exist" || return
  assert_file_contains "$CONTRACT" "方法吸收" "contract should include method absorption" || return
  assert_file_contains "$CONTRACT" "能力调用" "contract should include capability calls" || return
  assert_file_contains "$CONTRACT" "证据生产" "contract should include evidence production" || return
  assert_file_contains "$CONTRACT" "可选旁路" "contract should include optional side paths" || return
  assert_file_contains "$CONTRACT" "不能把 \`~/.gstack/...\` 当长期真相源" "contract should reject gstack as source of truth" || return
  pass_test
}

test_pdf_and_document_generate_boundaries() {
  start_test "gstack contract: /make-pdf 与 /document-generate 边界"

  assert_file_contains "$CONTRACT" "/make-pdf" "contract should name make-pdf" || return
  assert_file_contains "$CONTRACT" "PDF 只是交付格式" "contract should make PDF an export artifact" || return
  assert_file_contains "$CONTRACT" "/document-generate" "contract should name document-generate" || return
  assert_file_contains "$CONTRACT" "/document-release" "contract should name document-release" || return
  assert_file_contains "$CONTRACT" "工程文档生成旁路" "document-generate should be engineering-doc side path" || return
  assert_file_contains "$CONTRACT" "不用于产品介绍、PRD、模块规格或 PM 汇报材料" "document-generate should not own product docs" || return
  pass_test
}

test_side_path_docs_return_protocol() {
  start_test "gstack contract: 旁路文档接回 PMAI 文档地图"

  assert_file_contains "$CONTRACT" "旁路文档接回协议" "contract should define side-path document return protocol" || return
  assert_file_contains "$CONTRACT" "docs/engineering/" "contract should name engineering docs destination" || return
  assert_file_contains "$CONTRACT" "docs/engineering/INDEX.md" "contract should require engineering index" || return
  assert_file_contains "$CONTRACT" "补索引后，才算 PMAI 已接收" "contract should require index registration before acceptance" || return
  assert_file_contains "$CONTRACT" "只引用 \`~/.gstack/...\`" "contract should reject temporary gstack paths" || return
  assert_file_contains "$CONTRACT" "/pmai-doc-writing" "contract should route product docs away from document-generate" || return
  assert_file_contains "$CONTRACT" "/pmai-spec-writing" "contract should route spec docs away from document-generate" || return
  pass_test
}

test_doc_writing_names_make_pdf() {
  start_test "doc-writing: PDF 出口明确为 /make-pdf"

  assert_file_contains "$REPO_ROOT/skills/doc-writing/SKILL.md" "/make-pdf" "doc-writing should name make-pdf" || return
  assert_file_contains "$REPO_ROOT/templates/deliverables-INDEX.md.tmpl" "/make-pdf" "deliverables index should name make-pdf" || return

  if grep -q "Markdown 转 PDF skill" "$REPO_ROOT/skills/doc-writing/SKILL.md" "$REPO_ROOT/templates/deliverables-INDEX.md.tmpl"; then
    _fail "PDF outlet should not use vague Markdown 转 PDF skill wording"
    return
  fi
  pass_test
}

test_key_skills_reference_or_encode_contract() {
  start_test "gstack contract: 关键 skill 已接入合同"

  assert_file_contains "$REPO_ROOT/skills/meta/SKILL.md" "gstack-integration.md" "meta should reference contract" || return
  assert_file_contains "$REPO_ROOT/skills/mockup/SKILL.md" "gstack-integration.md" "mockup should reference contract" || return
  assert_file_contains "$REPO_ROOT/skills/build/SKILL.md" "gstack-integration.md" "build should reference contract" || return
  assert_file_contains "$REPO_ROOT/skills/build-close/SKILL.md" "gstack-integration.md" "build-close should reference contract" || return
  assert_file_contains "$REPO_ROOT/skills/init-project/SKILL.md" "初始化阶段完全可选" "init-project should make gstack optional" || return
  assert_file_contains "$REPO_ROOT/skills/mirror-site/SKILL.md" "gstack-integration.md" "mirror-site should reference contract" || return
  assert_file_contains "$REPO_ROOT/skills/_internal/codebase-audit/SKILL.md" "gstack-integration.md" "codebase-audit should reference contract" || return
  pass_test
}

test_readme_dependency_is_not_unconditional() {
  start_test "README: gstack 不是全仓无条件硬依赖"

  if grep -q "| \\*\\*gstack\\*\\* | 必需 |" "$REPO_ROOT/README.md"; then
    _fail "README should not describe gstack as unconditional 必需"
    return
  fi
  assert_file_contains "$REPO_ROOT/README.md" "可选能力层" "README should describe gstack as optional capability layer" || return
  assert_file_contains "$REPO_ROOT/README.md" "初始化和非 Web build 都不受阻塞" "README should preserve init/non-web fallback" || return
  pass_test
}

test_contract_preserves_public_interface_choices() {
  start_test "gstack contract: 不新增 PMAI 入口、不接 /spec"

  assert_file_contains "$CONTRACT" "不新增 \`/pmai-gstack\` 或 \`/pmai-office-hours\`" "contract should forbid new PMAI gstack entry" || return
  assert_file_contains "$CONTRACT" "不给 gstack skill 加 \`pmai-\` 前缀" "contract should preserve bare gstack names" || return
  assert_file_contains "$CONTRACT" "不把 \`/spec\` 接入 PMAI 主链路" "contract should keep gstack spec out of PMAI main flow" || return
  pass_test
}

test_contract_exists_and_classifies_integration
test_pdf_and_document_generate_boundaries
test_side_path_docs_return_protocol
test_doc_writing_names_make_pdf
test_key_skills_reference_or_encode_contract
test_readme_dependency_is_not_unconditional
test_contract_preserves_public_interface_choices

report_results "gstack-integration-contract"
