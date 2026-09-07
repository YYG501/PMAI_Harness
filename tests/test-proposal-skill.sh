#!/usr/bin/env bash
# Stable contracts for the Product Proposal entry. Keep detailed prose out of this suite.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/proposal/SKILL.md"
METHOD="$REPO_ROOT/skills/proposal/references/proposal-method.md"
AGENT="$REPO_ROOT/skills/proposal/agents/openai.yaml"

frontmatter_name() {
  sed -n '1,/^---$/p' "$1" | sed -n 's/^name:[[:space:]]*//p' | head -n 1
}

test_public_entry_and_assets_exist() {
  start_test "proposal: public entry and canonical assets exist"

  assert_file_exists "$SKILL" "proposal skill should exist" || return
  assert_file_exists "$METHOD" "proposal method should exist" || return
  assert_file_exists "$AGENT" "proposal UI metadata should exist" || return
  if [ "$(frontmatter_name "$SKILL")" != "pmai-proposal" ]; then
    _fail "proposal frontmatter name drifted"
    return
  fi
  assert_file_contains "$AGENT" '\$pmai-proposal' "default prompt should invoke the public skill" || return
  pass_test
}

test_proposal_is_a_complete_product_level_decision() {
  start_test "proposal: complete product-level decision stays above design"

  assert_file_contains "$SKILL" 'Proposal 位于模块 design 之前' "proposal should own the product-level decision" || return
  assert_file_contains "$SKILL" '完整产品主张' "proposal should remain a reusable product claim for downstream work" || return
  assert_file_contains "$SKILL" '端到端体验、关键能力和 MVP 证明目标' "proposal should connect experience, capabilities, and proof target" || return
  assert_file_contains "$SKILL" '必须完成一份可独立评审的完整 Product Proposal' "proposal should require a complete artifact" || return
  assert_file_contains "$SKILL" '不得用 brief、方向摘要、问题清单、竞品报告或普通介绍稿代替' "partial substitutes should be rejected" || return
  assert_file_contains "$SKILL" '/pmai-doc-writing' "confirmed narrative work should route to doc-writing" || return
  assert_file_contains "$SKILL" '/pmai-design' "module design should route to design" || return
  assert_file_contains "$SKILL" '/pmai-spec-writing' "functional specifications should route to spec-writing" || return
  pass_test
}

test_versioning_and_atomic_product_sync_are_explicit() {
  start_test "proposal: revisions supersede and sync PRODUCT atomically"

  assert_file_contains "$SKILL" 'docs/proposals/INDEX.md' "proposal index should be canonical" || return
  assert_file_contains "$SKILL" '新建完整 `vN+1`' "direction changes should create a full new version" || return
  assert_file_contains "$SKILL" '旧文档只更新状态头' "superseded proposal bodies should remain intact" || return
  assert_file_contains "$SKILL" '作为一个原子变更提交' "proposal and product baseline should commit atomically" || return
  assert_file_contains "$SKILL" 'scripts/proposal-contract.py' "proposal should call the machine contract helper" || return
  assert_file_contains "$SKILL" 'accept "$REPO_ROOT"' "proposal should accept the current version through the helper" || return
  assert_file_contains "$SKILL" '--supersedes "<旧-proposal-id>"' "proposal revisions should bind the superseded id" || return
  assert_file_contains "$SKILL" '.pm-workflow/proposal.json' "proposal contract should join the atomic commit" || return
  assert_file_contains "$SKILL" '禁止 `git add -A`' "proposal commit should not absorb unrelated work" || return
  assert_file_contains "$SKILL" 'diff --cached --quiet' "proposal should reject pre-existing staged work" || return
  assert_file_contains "$SKILL" 'diff --cached --name-only' "proposal should verify the exact staged atomic paths" || return
  assert_file_contains "$SKILL" 'validate "$REPO_ROOT"' "proposal should revalidate Git currentness after commit" || return
  assert_file_contains "$SKILL" '合同只是待提交' "accept alone should not be described as active" || return
  assert_file_contains "$SKILL" '只能在主仓 `main/master` 定稿' "proposal acceptance should stay on the integration branch" || return
  assert_file_contains "$SKILL" '旧 active build 尚未按步骤 0 冻结候选并清掉活动状态前' "active build should be resolved before changing its upstream Proposal" || return
  assert_file_contains "$SKILL" 'replan-work.py' "active builds should use the shared upstream replan entry" || return
  assert_file_contains "$SKILL" '--route proposal' "proposal replans should bind the proposal route" || return
  assert_file_contains "$SKILL" 'main mode' "main-mode builds should be handled explicitly" || return
  assert_file_contains "$SKILL" '已经进入 main 的实现原样保留' "main-mode replans should preserve implementation already on main" || return
  assert_file_contains "$SKILL" '不让 PM 改走 `/pmai-build-cancel`' "main-mode replans should not be routed through cancellation" || return
  assert_file_contains "$SKILL" 'replan-work.py.*list' "cross-session proposal recovery should enumerate frozen candidates" || return
  assert_file_contains "$SKILL" '再次扫描主仓与所有 attached worktrees' "the contract helper should be documented as the final active-build guard" || return
  assert_file_contains "$SKILL" '只能读取或幂等校验已有 Proposal' "existing proposal reads should remain available in build worktrees" || return
  assert_file_contains "$SKILL" '本 skill 禁止修改' "proposal should protect PRODUCT-STATE" || return
  pass_test
}

test_completeness_review_has_a_read_only_exit() {
  start_test "proposal: completeness review validates and exits without a new version"

  local review_line draft_line
  review_line=$(grep -n '完整性复核有独立的只读出口' "$SKILL" | head -1 | cut -d: -f1)
  draft_line=$(grep -n '^### 5\. 生成完整 Proposal 草案' "$SKILL" | head -1 | cut -d: -f1)
  if [ -z "$review_line" ] || [ -z "$draft_line" ] || [ "$review_line" -ge "$draft_line" ]; then
    _fail "completeness review must exit before draft generation"
    return
  fi
  assert_file_contains "$SKILL" 'proposal-contract.py" validate "$REPO_ROOT"' \
    "completeness review should validate the current machine contract" || return
  assert_file_contains "$SKILL" '合同、Proposal 固定章节与下游交接、`docs/proposals/INDEX.md`.*`PRODUCT.md`.*Git currentness' \
    "read-only review must cover the full current Proposal baseline" || return
  assert_file_contains "$SKILL" '不得进入步骤 2–9' \
    "successful review should stop before mutation steps" || return
  assert_file_contains "$SKILL" '不生成待确认草案、不调用 `accept`、不暂存、不提交' \
    "successful review must be mutation-free" || return
  assert_file_contains "$SKILL" '升级为\*\*方向修订\*\*，创建完整 `vN+1`' \
    "changed or invalid product direction should create a full revision" || return
  assert_file_contains "$SKILL" '不得原地修补已定稿版本' \
    "failed validation must not mutate the accepted Proposal in place" || return
  pass_test
}

test_downstream_boundary_is_fixed() {
  start_test "proposal: fixed handoff does not become a module specification"

  assert_file_contains "$METHOD" '## 10. 下游交接摘要' "method should define the fixed handoff section" || return
  assert_file_contains "$METHOD" '第一个 design 目标' "handoff should name the first design result" || return
  assert_file_contains "$METHOD" 'MVP 必须证明' "handoff should preserve the MVP proof target" || return
  assert_file_contains "$METHOD" '不提前写信息模型、页面层级、字段、状态机、权限矩阵或验收步骤' "proposal should not preempt design" || return
  assert_file_contains "$METHOD" 'Proposal 的下游用途' "handoff should explain downstream use" || return
  assert_file_contains "$METHOD" '取舍依据' "handoff should preserve prioritization rationale" || return
  assert_file_contains "$METHOD" '验证依据' "handoff should preserve the validation target" || return
  assert_file_contains "$SKILL" 'design、record、doc-writing、spec-writing 都不得修改 Proposal' "downstream skills should treat proposal as read-only" || return
  assert_file_contains "$SKILL" 'Proposal 不得直接跳回 lark-review，因为它本身不修改模块规格' \
    "product-review handoffs must pass through affected module design after Proposal" || return
  assert_file_contains "$SKILL" '按 `handoff_bundle` 中的文档与模块去重形成下游覆盖队列' \
    "Proposal should hand every affected review target to downstream design" || return
  assert_file_contains "$SKILL" '全部受影响规格处理完成后才回 `/pmai-lark-review`' \
    "Lark review should resume only after downstream authority is covered" || return
  pass_test
}

test_method_is_generic_with_ai_and_enterprise_profiles() {
  start_test "proposal: generic core retains enterprise and AI depth"

  assert_file_contains "$METHOD" '个人产品' "value model should support consumer products" || return
  assert_file_contains "$METHOD" '企业产品' "value model should support enterprise products" || return
  assert_file_contains "$METHOD" '开发者或平台产品' "value model should support platform products" || return
  assert_file_contains "$METHOD" '事实、推断、假设' "proposal should preserve evidence levels" || return
  assert_file_contains "$METHOD" '确定性软件' "AI should not absorb deterministic work" || return
  assert_file_contains "$METHOD" 'Agent Runtime' "Agent runtime boundaries should remain explicit" || return
  pass_test
}

test_skill_has_no_machine_specific_paths() {
  start_test "proposal: authored assets contain no machine-specific paths"

  if grep -Eq '/Users/[^<[:space:]]+/' "$SKILL" "$METHOD" "$AGENT"; then
    _fail "proposal assets contain a machine-specific path"
    return
  fi
  pass_test
}

test_public_entry_and_assets_exist
test_proposal_is_a_complete_product_level_decision
test_versioning_and_atomic_product_sync_are_explicit
test_completeness_review_has_a_read_only_exit
test_downstream_boundary_is_fixed
test_method_is_generic_with_ai_and_enterprise_profiles
test_skill_has_no_machine_specific_paths

report_results "proposal-skill"
