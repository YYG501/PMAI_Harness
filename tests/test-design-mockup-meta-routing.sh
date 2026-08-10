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
  start_test "design: 对象关系先于页面方案"

  assert_file_contains "$DESIGN_SKILL" "对象关系" "design should require object relationships" || return
  assert_file_contains "$DESIGN_SKILL" "真问题" "design should recover the real problem" || return
  assert_file_contains "$DESIGN_METHOD" "原始输入 / 触发材料" "method should require source input" || return
  assert_file_contains "$DESIGN_SKILL" "对象关系" "design should require object relationships" || return
  assert_file_contains "$DESIGN_METHOD" "下游判断 / 动作" "method should require downstream judgment" || return
  assert_file_contains "$DESIGN_METHOD" "不允许从页面方案倒推对象" "method should reject UI-first modeling" || return
  pass_test
}

test_design_routes_to_downstream_skills() {
  start_test "design: meta/mockup/build/feedback 分流"

  assert_file_contains "$DESIGN_SKILL" "按需自动进入 meta" "design should define meta routing" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-meta" "design should route product judgment to meta" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-mockup" "design should route visual forks to mockup" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-build" "design should route prototype work to build" || return
  assert_file_contains "$DESIGN_SKILL" "/pmai-feedback" "design should route workflow issues to feedback" || return
  assert_file_contains "$DESIGN_SKILL" "不等于授权 design 直接改主原型" "design should never edit the build target" || return
  pass_test
}

test_mockup_preserves_adaptive_divergence() {
  start_test "mockup: 只有真实岔路才发散，工具受限不降级覆盖"

  assert_file_contains "$MOCKUP_SKILL" "无真实岔路" "mockup should support one recommended direction" || return
  assert_file_contains "$MOCKUP_SKILL" "有真实岔路" "mockup should generate alternatives when needed" || return
  assert_file_contains "$MOCKUP_SKILL" "check-gstack-browser.sh" "mockup should call gstack diagnostics" || return
  assert_file_contains "$MOCKUP_SKILL" "gstack 受限：走 PMAI 内部 HTML / 静态稿" "mockup should have a local fallback" || return
  assert_file_contains "$MOCKUP_SKILL" "交互模型、信息层级或任务路径" "variants should differ materially" || return
  assert_file_contains "$MOCKUP_SKILL" '不修改 `project.yml` 声明的实现入口' "mockup should not touch build target" || return
  pass_test
}

test_meta_distinguishes_multi_agent() {
  start_test "meta: 单主控多视角 vs 多 Agent"

  assert_file_contains "$META_SKILL" "多视角与多 Agent" "meta should define terminology" || return
  assert_file_contains "$META_SKILL" "默认指同一主控" "meta should distinguish normal multi-perspective analysis" || return
  assert_file_contains "$META_SKILL" "只有 PM 明确要求多 Agent" "meta should only use agents on explicit request" || return
  assert_file_contains "$TOOLBOX" "默认是单主控多视角，不等于多 Agent 复审" "toolbox should preserve distinction" || return
  pass_test
}

test_consumer_template_carries_runtime_rules() {
  start_test "template: consumer AGENTS carries new boundaries"

  assert_file_contains "$AGENTS_TEMPLATE" '新功能、产品规则、规格或验收路径变化走 `/pmai-design`' "template should name design entry role" || return
  assert_file_contains "$AGENTS_TEMPLATE" 'mockup 只出探索稿' "template should keep mockup out of prototype" || return
  assert_file_contains "$AGENTS_TEMPLATE" "单主控多视角退化执行" "template should require meta degradation statement" || return
  assert_file_contains "$AGENTS_TEMPLATE" 'localhost `EPERM`' "template should explain sandbox restriction" || return
  assert_file_contains "$AGENTS_TEMPLATE" "由 PM 一次确认建造对象与技术方案" "template should require design-time project definition confirmation" || return
  pass_test
}

test_design_has_object_modeling_gate
test_design_routes_to_downstream_skills
test_mockup_preserves_adaptive_divergence
test_meta_distinguishes_multi_agent
test_consumer_template_carries_runtime_rules

report_results "design-mockup-meta-routing"
