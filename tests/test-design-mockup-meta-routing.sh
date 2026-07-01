#!/usr/bin/env bash
# Static regression tests for design/mockup/meta routing gates.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
DESIGN_METHOD="$REPO_ROOT/skills/design/references/design-method.md"
MOCKUP_SKILL="$REPO_ROOT/skills/mockup/SKILL.md"
META_SKILL="$REPO_ROOT/skills/meta/SKILL.md"
TOOLBOX="$REPO_ROOT/skills/meta/references/thinking-toolbox.md"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"

test_design_has_object_modeling_gate() {
  start_test "design: 业务对象建模硬门"

  assert_file_contains "$DESIGN_SKILL" "业务对象建模硬门" "design should require object modeling gate" || return
  assert_file_contains "$DESIGN_SKILL" "原始输入 / 触发材料" "design should require source input" || return
  assert_file_contains "$DESIGN_SKILL" "对象关系" "design should require object relationships" || return
  assert_file_contains "$DESIGN_SKILL" "下游判断 / 动作" "design should require downstream judgment" || return
  assert_file_contains "$DESIGN_METHOD" "不允许从页面方案倒推对象" "method should reject UI-first modeling" || return
  pass_test
}

test_design_routes_to_downstream_skills() {
  start_test "design: meta/mockup/build/skill-improve 分流"

  assert_file_contains "$DESIGN_SKILL" "分流硬门" "design should define routing gate" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-meta" "design should route product judgment to meta" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-mockup" "design should route visual forks to mockup" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-build" "design should route prototype work to build" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-skill-improve" "design should route workflow issues to skill-improve" || return
  assert_file_contains "$DESIGN_SKILL" '是否转 `/pmai-build` 或小改主原型确认' "design should force prototype confirmation" || return
  pass_test
}

test_mockup_preserves_divergent_fallback() {
  start_test "mockup: gstack 优先 + 内部 shotgun fallback"

  assert_file_contains "$MOCKUP_SKILL" "发散探索 + 对比看板" "mockup should be divergent comparison workflow" || return
  assert_file_contains "$MOCKUP_SKILL" "check-gstack-browser.sh" "mockup should call gstack diagnostics" || return
  assert_file_contains "$MOCKUP_SKILL" "pmai-internal-shotgun" "mockup should define internal fallback engine" || return
  assert_file_contains "$MOCKUP_SKILL" "gstack 不可用也要发散" "fallback should remain divergent" || return
  assert_file_contains "$MOCKUP_SKILL" "布局结构、信息密度、用户路径、视觉气质中的两项有差异" "variants should differ materially" || return
  assert_file_contains "$MOCKUP_SKILL" '只动 `mockups/`、不碰 `prototype/`' "mockup should not touch main prototype" || return
  pass_test
}

test_meta_distinguishes_multi_agent() {
  start_test "meta: 单主控多视角 vs 多 Agent"

  assert_file_contains "$META_SKILL" "多视角 vs 多 Agent 口径" "meta should define terminology" || return
  assert_file_contains "$META_SKILL" "这不等同于多 Agent 复审" "meta should declare degradation" || return
  assert_file_contains "$META_SKILL" "必须尝试当前 runtime 可用的子 Agent" "meta should try subagents when requested" || return
  assert_file_contains "$TOOLBOX" "默认是单主控多视角，不等于多 Agent 复审" "toolbox should preserve distinction" || return
  pass_test
}

test_consumer_template_carries_runtime_rules() {
  start_test "template: consumer AGENTS carries new boundaries"

  assert_file_contains "$AGENTS_TEMPLATE" '/pmai-design` 是设计主入口' "template should name design entry role" || return
  assert_file_contains "$AGENTS_TEMPLATE" '只写 `mockups/`' "template should keep mockup out of prototype" || return
  assert_file_contains "$AGENTS_TEMPLATE" "单主控多视角退化执行" "template should require meta degradation statement" || return
  assert_file_contains "$AGENTS_TEMPLATE" 'localhost `EPERM`' "template should explain sandbox restriction" || return
  assert_file_contains "$AGENTS_TEMPLATE" "未经 PM 明确确认" "template should require prototype confirmation" || return
  pass_test
}

test_design_has_object_modeling_gate
test_design_routes_to_downstream_skills
test_mockup_preserves_divergent_fallback
test_meta_distinguishes_multi_agent
test_consumer_template_carries_runtime_rules

report_results "design-mockup-meta-routing"
