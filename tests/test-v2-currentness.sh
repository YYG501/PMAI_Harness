#!/usr/bin/env bash
# Cross-surface guard against pre-v2 workflow language returning to active assets.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

test_fixed_audit_chain_is_not_exposed() {
  start_test "currentness: fixed audit orchestrator and reviewer are retired"
  local stale
  for path in scripts/build-audits.py agents/coverage-reviewer.md docs/build-audits-编排与自测.md tests/test-build-audits.sh; do
    if [ -e "$REPO_ROOT/$path" ]; then
      _fail "retired asset still exists: $path"
      return
    fi
  done
  stale=$(rg -n 'build-audits|coverage-reviewer|三道审|docs/DESIGN\.md' \
    "$REPO_ROOT/skills" "$REPO_ROOT/templates" "$REPO_ROOT/agents" \
    "$REPO_ROOT/README.md" "$REPO_ROOT/AGENTS.md" "$REPO_ROOT/PRODUCT.md" \
    "$REPO_ROOT/RUNTIME.md" "$REPO_ROOT/INVARIANTS.md" "$REPO_ROOT/TODOS.md" 2>/dev/null || true)
  if [ -n "$stale" ]; then
    _fail "active user-facing asset still exposes retired audit language"
    echo "$stale" >&2
    return
  fi
  pass_test
}

test_retired_structure_contract_is_not_exposed() {
  start_test "currentness: retired structure detector and templates are not active"
  local path stale
  for path in \
    scripts/detect-project-structure.py \
    scripts/derive-structure-templates.py \
    scripts/inject-structure-segment.py \
    templates/prototype-README.md.tmpl \
    templates/工程结构约束-prototype.md \
    templates/工程结构约束-system.md \
    templates/工程结构约束-custom.md \
    templates/工程结构约束.schema.json; do
    if [ -e "$REPO_ROOT/$path" ]; then
      _fail "retired structure asset still exists: $path"
      return
    fi
  done
  stale=$(rg -n '工程结构约束-[*{]|工程结构约束\.schema|detect-project-structure|derive-structure-templates|inject-structure-segment' \
    "$REPO_ROOT/skills" "$REPO_ROOT/templates" "$REPO_ROOT/agents" "$REPO_ROOT/docs/INDEX.md" 2>/dev/null || true)
  if [ -n "$stale" ]; then
    _fail "active assets still reference the retired structure contract"
    echo "$stale" >&2
    return
  fi
  pass_test
}

test_init_and_project_definition_have_one_boundary() {
  start_test "currentness: init creates context; design owns project.yml"
  local init="$REPO_ROOT/scripts/init-project.sh"
  local config="$REPO_ROOT/templates/pm-workflow.config.yml.tmpl"
  local product="$REPO_ROOT/templates/PRODUCT.md.tmpl"
  if grep -qE 'PROJECT_TYPE=|STRUCTURE_INTENT=|mkdir -p .*prototype|mkdir -p .*mockups|\.dev-port|gstack 未安装' "$init"; then
    _fail "init-project still creates a pre-design build shape"
    return
  fi
  if grep -qE '^project:|dev_server:|screenshot_tool:|PROJECT_TYPE' "$config"; then
    _fail "builder config duplicates project definition"
    return
  fi
  if grep -q '^## 技术栈' "$product" || ! grep -q '^## 产品边界' "$product"; then
    _fail "PRODUCT template should keep product boundaries, not duplicate implementation.stack"
    return
  fi
  if ! grep -q 'project-definition.py.*write' "$REPO_ROOT/skills/design/SKILL.md" \
     || ! grep -q 'project-definition.py.*show' "$REPO_ROOT/skills/build/SKILL.md"; then
    _fail "design/build do not share the project definition helper"
    return
  fi
  pass_test
}

test_user_flow_has_no_main_prototype_exception() {
  start_test "currentness: consumer template has no direct-main prototype exception"
  local template="$REPO_ROOT/templates/AGENTS.md.tmpl"
  if grep -qE '小改直接落主原型|直接在 prototype/ 上改|PM 明确确认的小改' "$template"; then
    _fail "consumer AGENTS still permits direct main prototype changes"
    return
  fi
  if ! grep -q '任何代码改动走 `/pmai-build` 或 `/pmai-quick-fix`' "$template"; then
    _fail "consumer AGENTS should route all code changes through build/quick-fix"
    return
  fi
  pass_test
}

test_adaptive_browser_and_record_contracts_are_current() {
  start_test "currentness: active browser hard gate and six-class record model are exposed"
  if ! grep -q 'browser-smoke.*不接受 exception' "$REPO_ROOT/skills/build/SKILL.md" \
     || ! grep -q '不能用 exception 跳过' "$REPO_ROOT/skills/_shared/gstack-integration.md"; then
    _fail "UI active-browser hard gate is missing from active skills"
    return
  fi
  if ! grep -q '六类归位' "$REPO_ROOT/skills/record/SKILL.md" \
     || ! grep -q '⑥ 稳定术语' "$REPO_ROOT/skills/record/SKILL.md"; then
    _fail "record skill does not expose shared six-class model"
    return
  fi
  pass_test
}

test_active_helpers_require_project_definition() {
  start_test "currentness: active helpers cannot bypass project.yml"
  local acceptance="$REPO_ROOT/scripts/acceptance-profile.py"
  local contract="$REPO_ROOT/scripts/build-contract.py"
  local context="$REPO_ROOT/scripts/context-pack.py"
  local reconstruction="$REPO_ROOT/skills/_shared/context-reconstruction.md"
  local builder="$REPO_ROOT/scripts/builder-profile.py"
  if grep -q 'add_argument("--target"' "$acceptance" \
     || grep -q 'target_paths = \["prototype/"\]' "$contract" \
     || grep -q 'result.add_argument("--target"' "$context" \
     || grep -q -- '--target "<prototype|product>"' "$reconstruction"; then
    _fail "active helper still has a pre-project.yml target shortcut"
    return
  fi
  if ! grep -q 'add_argument("--project-definition", required=True)' "$acceptance" \
     || ! grep -q 'recommend.add_argument("--project-definition", required=True)' "$builder" \
     || ! grep -q 'recommend.add_argument("--current-host", required=True' "$builder" \
     || ! grep -q 'required_checks。' "$contract"; then
    _fail "project.yml / adaptive checks are not fail-closed"
    return
  fi
  pass_test
}

test_spec_contract_is_normative_not_implementation_inventory() {
  start_test "currentness: spec is the final target contract"
  local spec="$REPO_ROOT/skills/spec-writing/SKILL.md"
  local template="$REPO_ROOT/skills/spec-writing/templates/prd.md.tmpl"
  local fewshots="$REPO_ROOT/skills/spec-writing/references/few-shots.md"
  local pmview="$REPO_ROOT/skills/_shared/PM-VIEW-RULES.md"
  if rg -n '原型覆盖范围表|反向 PRD|§六.?原型.*ASCII|每个页面 / 弹窗 / 抽屉.*一张' \
    "$spec" "$template" "$fewshots" >/dev/null 2>&1; then
    _fail "spec-writing still exposes implementation-coverage artifacts"
    return
  fi
  if ! grep -q '指导研发实现与验收的.*最终目标合同' "$pmview" \
     || ! grep -q '规范性来源' "$spec" \
     || ! grep -q '漏实现' "$spec" \
     || ! grep -q '无依据实现' "$spec"; then
    _fail "normative source boundary or landed four-way reconciliation is missing"
    return
  fi
  pass_test
}

test_fixed_audit_chain_is_not_exposed
test_retired_structure_contract_is_not_exposed
test_init_and_project_definition_have_one_boundary
test_user_flow_has_no_main_prototype_exception
test_adaptive_browser_and_record_contracts_are_current
test_active_helpers_require_project_definition
test_spec_contract_is_normative_not_implementation_inventory

report_results "v2-currentness"
