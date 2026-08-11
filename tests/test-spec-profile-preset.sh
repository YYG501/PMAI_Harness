#!/usr/bin/env bash
# Stable contracts for spec content modules, additive profiles, and the single PRD preset.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$REPO_ROOT/skills/spec-writing/SKILL.md"
MODULES="$REPO_ROOT/skills/spec-writing/references/content-modules.md"
ENTERPRISE="$REPO_ROOT/skills/spec-writing/references/enterprise-platform-profile.md"
AI="$REPO_ROOT/skills/spec-writing/references/ai-product-profile.md"
PRESET="$REPO_ROOT/skills/spec-writing/references/full-prd-preset.md"
TEMPLATE="$REPO_ROOT/skills/spec-writing/templates/prd.md.tmpl"
WRITING_RULES="$REPO_ROOT/skills/spec-writing/references/writing-rules.md"

test_assets_and_routing() {
  start_test "spec profiles: canonical assets and upstream routes are wired"

  local asset
  for asset in "$MODULES" "$ENTERPRISE" "$AI" "$PRESET" "$TEMPLATE"; do
    assert_file_exists "$asset" "missing spec composition asset: $asset" || return
    assert_file_contains "$SPEC" "$(basename "$asset")" "spec-writing should link $(basename "$asset")" || return
  done

  assert_file_contains "$SPEC" '/pmai-proposal' "product-level gaps should route to proposal" || return
  assert_file_contains "$SPEC" '/pmai-design' "module-level gaps should route to design" || return
  pass_test
}

test_proposal_gate_precedes_every_document_target() {
  start_test "spec profiles: Proposal gate runs once before choosing any document target"

  local gate_line target_line manual_line module_line feature_line gate_count
  gate_line=$(grep -n '^## Proposal gate' "$SPEC" | head -1 | cut -d: -f1)
  target_line=$(grep -n '^## 文档目标' "$SPEC" | head -1 | cut -d: -f1)
  manual_line=$(grep -n '^## 手动调用确认' "$SPEC" | head -1 | cut -d: -f1)
  module_line=$(grep -n '^## 模块规格流程' "$SPEC" | head -1 | cut -d: -f1)
  feature_line=$(grep -n '^## 功能型规格流程' "$SPEC" | head -1 | cut -d: -f1)
  gate_count=$(grep -Fc 'python3 "$PMAI_HOME/scripts/proposal-contract.py" status "$REPO_ROOT"' "$SPEC")

  if [ -z "$gate_line" ] || [ -z "$target_line" ] || [ -z "$manual_line" ] \
    || [ -z "$module_line" ] || [ -z "$feature_line" ] \
    || [ "$gate_line" -ge "$target_line" ] || [ "$gate_line" -ge "$manual_line" ] \
    || [ "$gate_line" -ge "$module_line" ] || [ "$gate_line" -ge "$feature_line" ]; then
    _fail "Proposal gate must precede target selection and both spec-writing flows"
    return
  fi
  if [ "$gate_count" != "1" ]; then
    _fail "Proposal status gate should have one shared invocation, got $gate_count"
    return
  fi
  assert_file_contains "$SPEC" '`required`：新项目的产品级依据不完整，停止 spec-writing，返回 `/pmai-proposal`' \
    "required new-project status must return to Proposal before writing" || return
  assert_file_contains "$SPEC" '`invalid`：当前 Proposal 或 `PRODUCT.md` 已漂移，停止 spec-writing，返回 `/pmai-proposal`' \
    "invalid Proposal status must return before writing" || return
  if grep -q 'Product Proposal 是\*\*可选上游文档\*\*' "$SPEC"; then
    _fail "spec-writing still describes Proposal as an optional non-gate"
    return
  fi
  assert_file_contains "$PRESET" '完整 PRD 必须先通过产品方向 gate' \
    "full PRD preset must require the shared product-direction gate" || return
  assert_file_contains "$PRESET" '当前 Product Proposal.*PM 已确认仍有效的完整等价产品基线' \
    "full PRD preset must accept only the current Proposal or PM-confirmed equivalent baseline" || return
  if grep -q 'Product Proposal 是可选上游材料' "$PRESET"; then
    _fail "full PRD preset still treats Proposal as optional"
    return
  fi
  pass_test
}

test_content_profile_preset_are_orthogonal() {
  start_test "spec profiles: content, profiles, and preset stay orthogonal"

  assert_file_contains "$SPEC" '内容 = 通用内容模块 + 可叠加 Profile' "content composition formula is missing" || return
  assert_file_contains "$SPEC" '形态 = Preset' "presentation formula is missing" || return
  assert_file_contains "$MODULES" '信息模型 -> 核心动作 -> 异常与空状态 -> 验收标准' "generic complex-spec backbone is missing" || return
  assert_file_contains "$PRESET" 'Preset 不引入新的产品规则' "preset should not own product content" || return
  assert_file_contains "$ENTERPRISE" '叠加在 `content-modules.md` 之上' "enterprise profile must extend generic modules" || return
  assert_file_contains "$AI" '叠加在 `content-modules.md` 之上' "AI profile must extend generic modules" || return
  pass_test
}

test_profiles_are_composable_without_combined_copy() {
  start_test "spec profiles: enterprise AI platform composes two profiles"

  assert_file_contains "$SPEC" '企业 AI 平台同时加载两份' "enterprise AI platform should load both profiles" || return
  assert_file_contains "$ENTERPRISE" '同时加载 `ai-product-profile.md`' "enterprise profile should compose with AI profile" || return
  assert_file_contains "$AI" '同时加载 `enterprise-platform-profile.md`' "AI profile should compose with enterprise profile" || return
  assert_file_contains "$ENTERPRISE" '任一治理信号时读取本 Profile' \
    "one enterprise governance signal should load relevant checks" || return
  assert_file_contains "$ENTERPRISE" '出现两项及以上.*完整启用本 Profile' \
    "multiple governance signals should trigger the full delivery check" || return

  if find "$REPO_ROOT/skills/spec-writing/references" -maxdepth 1 -type f \
    \( -name '*enterprise-ai*' -o -name '*企业-ai*' \) | grep -q .; then
    _fail "combined enterprise-AI profile should not duplicate the two canonical profiles"
    return
  fi
  pass_test
}

test_four_column_table_is_index_only() {
  start_test "spec profiles: four-column table is an optional action index"

  assert_file_contains "$SPEC" '可选动作索引' "spec-writing should call the table an optional action index" || return
  assert_file_contains "$ENTERPRISE" '只回答“有哪些动作、谁可以用、去哪里看详情”' "enterprise profile should limit index responsibility" || return
  assert_file_contains "$PRESET" '索引只帮助扫描，不承担完整需求' "preset should keep complete rules outside the index" || return
  assert_file_contains "$TEMPLATE" '每个索引项仍需在下文写完整动作详情' "template should require action details after the index" || return

  if grep -Fq '| 二级功能 | 三级功能 | 使用角色 | 需求描述 |' "$TEMPLATE"; then
    _fail "the full PRD template should not force the legacy four-column requirement table"
    return
  fi
  pass_test
}

test_single_preset_and_profile_coverage() {
  start_test "spec profiles: one full PRD preset with additive domain coverage"

  local template_count
  template_count=$(find "$REPO_ROOT/skills/spec-writing/templates" -maxdepth 1 -type f -name '*.tmpl' | wc -l | tr -d ' ')
  if [ "$template_count" != "1" ]; then
    _fail "spec-writing should expose exactly one full PRD template, got $template_count"
    return
  fi

  for heading in '## 五、信息模型' '## 六、核心动作' '## 七、异常与空状态' '## 八、验收标准'; do
    assert_file_contains "$TEMPLATE" "$heading" "full PRD template missing backbone heading: $heading" || return
  done

  assert_file_contains "$ENTERPRISE" '租户' "enterprise profile should cover tenant boundaries" || return
  assert_file_contains "$ENTERPRISE" '审计' "enterprise profile should cover audit" || return
  assert_file_contains "$AI" '人工确认' "AI profile should cover human confirmation" || return
  assert_file_contains "$AI" '评测集' "AI profile should cover evaluation sets" || return
  assert_file_contains "$AI" 'Case Rundown' "AI profile should cover end-to-end acceptance" || return
  pass_test
}

test_landed_and_lint_contracts_remain() {
  start_test "spec profiles: landed reconciliation and lint contracts remain"

  assert_file_contains "$SPEC" '\*\*符合\*\*' "landed reconciliation should retain conforming branch" || return
  assert_file_contains "$SPEC" '\*\*accepted delta\*\*' "landed reconciliation should retain accepted delta branch" || return
  assert_file_contains "$SPEC" '\*\*漏实现\*\*' "landed reconciliation should retain missing implementation branch" || return
  assert_file_contains "$SPEC" '\*\*无依据实现\*\*' "landed reconciliation should retain unsupported implementation branch" || return
  assert_file_contains "$SPEC" 'python3 "$PMAI_HOME/scripts/check-prd-hierarchy.py" "$PRD_PATH"' \
    "consumer PRD lint must use the installed framework script" || return
  if grep -Fq '"$REPO_ROOT/scripts/check-prd-hierarchy.py"' "$SPEC"; then
    _fail "spec-writing must not look for framework lint scripts inside the consumer repo"
    return
  fi
  assert_file_contains "$SPEC" 'PM-VIEW-RULES.md' "PM view contract should remain wired" || return
  pass_test
}

test_project_truth_sources_stay_in_owner_transaction() {
  start_test "spec profiles: project truth-source changes are handed back to their owner"

  assert_file_contains "$SPEC" '只报告这些同步目标，不直接修改这三个项目级真相源' \
    "spec-writing should not leave project-level truth sources outside the caller transaction" || return
  assert_file_contains "$SPEC" '由 design 或 landed 文档对账按各自提交合同处理' \
    "spec-writing should hand project-level synchronization to the owning workflow" || return
  pass_test
}

test_active_build_and_truth_source_boundaries() {
  start_test "spec profiles: manual writing cannot bypass active build authority"

  assert_file_contains "$SPEC" '^## Active build gate' \
    "manual spec-writing should have an active-build gate" || return
  assert_file_contains "$SPEC" 'ready_to_build / building / iterating / final_check' \
    "the authority gate should cover approved and active build states" || return
  assert_file_contains "$SPEC" '`ready_to_build` 尚未开工.*返回 `/pmai-design`' \
    "approved but unstarted authority should return to design" || return
  assert_file_contains "$SPEC" '小范围行为或体验调整.*回当前 `/pmai-build`.*accepted delta' \
    "scoped active-build changes should return to the build feedback loop" || return
  assert_file_contains "$SPEC" '对象、关系、动作、状态、权限、真相源、业务规则、信息结构、任务路径或关键交互变化.*`/pmai-design`' \
    "module-model changes should return to design" || return
  assert_file_contains "$SPEC" '手动调用不得冒充这些模式' \
    "manual writing must not impersonate controlled lifecycle modes" || return
  assert_file_contains "$WRITING_RULES" '最终目标中的产品行为' \
    "spec rules should describe a final target rather than landed current facts" || return
  assert_file_contains "$WRITING_RULES" '已经落地的当前事实以 `PRODUCT-STATE.md` 为准' \
    "PRODUCT-STATE should remain the current-fact authority" || return
  assert_file_contains "$WRITING_RULES" '列为 landed 后的术语同步目标.*不直接修改 `PRODUCT.md`' \
    "new terms should be handed to landed reconciliation instead of mutating PRODUCT" || return
  pass_test
}

test_assets_and_routing
test_proposal_gate_precedes_every_document_target
test_content_profile_preset_are_orthogonal
test_profiles_are_composable_without_combined_copy
test_four_column_table_is_index_only
test_single_preset_and_profile_coverage
test_landed_and_lint_contracts_remain
test_project_truth_sources_stay_in_owner_transaction
test_active_build_and_truth_source_boundaries

report_results "spec-profile-preset"
exit $((FAIL_COUNT > 0 ? 1 : 0))
