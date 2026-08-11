#!/usr/bin/env bash
# Static regression tests for the project-local design-system Skill contract.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$REPO_ROOT/skills/_shared/project-design-system.md"
DESIGN_TEMPLATE="$REPO_ROOT/templates/DESIGN.md.tmpl"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"
BUILD_SKILL="$REPO_ROOT/skills/build/SKILL.md"
UI_SKILLS=(
  "$REPO_ROOT/skills/design/SKILL.md"
  "$REPO_ROOT/skills/mockup/SKILL.md"
  "$BUILD_SKILL"
  "$REPO_ROOT/skills/quick-fix/SKILL.md"
  "$REPO_ROOT/skills/mirror-site/SKILL.md"
)

test_contract_preserves_design_baseline() {
  start_test "contract: DESIGN.md 始终是产品设计基线"
  assert_file_exists "$CONTRACT" "project design system contract should exist" || return
  assert_file_contains "$CONTRACT" '无论是否接入外部设计系统都必须先读' "DESIGN.md should always be read" || return
  assert_file_contains "$CONTRACT" '继续按 `DESIGN.md`、共享组件 inventory、现有页面和现有组件工作' "legacy consumers should preserve the existing UI flow" || return
  assert_file_contains "$CONTRACT" '这不是忽略 `DESIGN.md`' "no-skill fallback should not bypass DESIGN.md" || return
  pass_test
}

test_contract_executes_declared_skill_fail_closed() {
  start_test "contract: 已声明 Skill 必须执行且失败关闭"
  assert_file_contains "$CONTRACT" '当前宿主能按 `项目级 Skill` 原生解析时' "native hosts should invoke the declared Skill" || return
  assert_file_contains "$CONTRACT" '完整读取 `Skill 文件`' "other hosts should read the same project file" || return
  assert_file_contains "$CONTRACT" 'required references' "required references should be loaded" || return
  assert_file_contains "$CONTRACT" '并且已经被 Git 跟踪' "the project Skill should be portable through Git" || return
  assert_file_contains "$CONTRACT" '缺失、不可读、越出仓库或未跟踪时停止' "invalid declarations should stop UI work" || return
  pass_test
}

test_design_template_declares_generic_slot() {
  start_test "template: DESIGN.md 提供通用声明槽"
  assert_file_contains "$DESIGN_TEMPLATE" '## 四、项目设计系统' "DESIGN template should expose the integration section" || return
  assert_file_contains "$DESIGN_TEMPLATE" '状态：未接入' "new consumers should not opt in automatically" || return
  assert_file_contains "$DESIGN_TEMPLATE" '使用范围：' "adoption scope should be explicit" || return
  assert_file_contains "$DESIGN_TEMPLATE" '项目级 Skill：' "the callable name should be declared" || return
  assert_file_contains "$DESIGN_TEMPLATE" 'Skill 文件：' "the repository path should be declared" || return
  if grep -qiE 'example-org|example-org|agent-skill\.json' "$DESIGN_TEMPLATE" "$CONTRACT"; then
    _fail "generic framework contract should not bind a specific design system"
    return
  fi
  pass_test
}

test_consumer_entry_carries_cross_host_fallback() {
  start_test "template: 消费仓入口携带跨宿主执行规则"
  assert_file_contains "$AGENTS_TEMPLATE" '$PMAI_HOME/skills/_shared/project-design-system.md' "consumer entry should load the installed shared contract" || return
  assert_file_contains "$AGENTS_TEMPLATE" '当前宿主能原生解析时直接调用' "native Skill invocation should be preferred" || return
  assert_file_contains "$AGENTS_TEMPLATE" '完整读取声明的 `SKILL.md` 及其 required references' "file fallback should be explicit" || return
  if ! sed -n '/PMAI:BEGIN consumer-startup/,/PMAI:END consumer-startup/p' "$AGENTS_TEMPLATE" \
    | grep -q 'project-design-system.md'; then
    _fail "managed Startup block should carry the rule to existing consumers"
    return
  fi
  pass_test
}

test_all_ui_skills_reference_contract() {
  start_test "skills: 五个 UI 入口共用同一合同"
  local skill
  for skill in "${UI_SKILLS[@]}"; do
    if ! grep -q 'skills/_shared/project-design-system.md' "$skill"; then
      _fail "missing project design system contract reference: ${skill#$REPO_ROOT/}"
      return
    fi
  done
  pass_test
}

test_builder_prompt_carries_design_skill() {
  start_test "build: 外部 Builder 收到 DESIGN 与 Skill 路径"
  assert_file_contains "$BUILD_SKILL" '`DESIGN.md` 全文' "builder prompt should contain the full design baseline" || return
  assert_file_contains "$BUILD_SKILL" '项目级 Skill 名称和 Skill 仓内路径' "builder prompt should contain the declared Skill identity" || return
  assert_file_contains "$BUILD_SKILL" '不能原生调用时，完整读取该 `SKILL.md` 及其 required references' "builder should follow the file fallback" || return
  assert_file_contains "$BUILD_SKILL" '包括首次实现、每轮反馈修改和中断恢复' "every implementation entry should reload the declaration" || return
  assert_file_contains "$BUILD_SKILL" '构建工具无法访问其仓内路径时，在实现前停止' "an inaccessible Skill should stop implementation" || return
  pass_test
}

test_framework_does_not_add_product_specific_skill() {
  start_test "boundary: 不新增设计系统专用 PMAI 入口"
  assert_file_missing "$REPO_ROOT/skills/design-system" "framework should not add pmai-design-system" || return
  assert_file_missing "$REPO_ROOT/skills/internal-design-system" "framework should not vendor a product design system" || return
  if grep -Rqs '^name: pmai-design-system$' "$REPO_ROOT/skills"/*/SKILL.md; then
    _fail "framework should not expose a pmai-design-system Skill"
    return
  fi
  pass_test
}

test_contract_preserves_design_baseline
test_contract_executes_declared_skill_fail_closed
test_design_template_declares_generic_slot
test_consumer_entry_carries_cross_host_fallback
test_all_ui_skills_reference_contract
test_builder_prompt_carries_design_skill
test_framework_does_not_add_product_specific_skill

report_results "project-design-system-contract"
