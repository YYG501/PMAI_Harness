#!/usr/bin/env bash
# Static regression tests for landing/build/close hard gates.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
DESIGN_METHOD="$REPO_ROOT/skills/design/references/design-method.md"
BUILD_SKILL="$REPO_ROOT/skills/build/SKILL.md"
BUILD_CLOSE_SKILL="$REPO_ROOT/skills/build-close/SKILL.md"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"

test_design_landing_gate() {
  start_test "design: 落地意图必须过 prototype 分流门"

  assert_file_contains "$DESIGN_SKILL" "落地意图识别" "design should identify landing intent" || return
  assert_file_contains "$DESIGN_SKILL" "小改 prototype-only" "design should define prototype-only small change" || return
  assert_file_contains "$DESIGN_SKILL" "混合交付转 build" "design should route mixed delivery to build" || return
  assert_file_contains "$DESIGN_SKILL" "落地 / 实现 / 做进主原型 / 提交 / 可以做了" "design should catch PM landing phrases" || return
  assert_file_contains "$DESIGN_METHOD" "混合交付转 build" "method should mirror mixed delivery route" || return
  pass_test
}

test_build_small_change_tightened() {
  start_test "build: 小改不得同时改 docs/mockups"

  assert_file_contains "$BUILD_SKILL" "小改不得同时改 docs/mockups" "build should forbid mixed small change" || return
  assert_file_contains "$BUILD_SKILL" "PM 明确确认的 prototype-only 微调" "build should require prototype-only small change" || return
  assert_file_contains "$BUILD_SKILL" "把 mockup / spec 做进主原型" "build should force full gate for mock/spec landing" || return
  assert_file_contains "$BUILD_SKILL" "交接 /pmai-build-close 收尾" "build should hand off to build-close" || return
  pass_test
}

test_build_close_mixed_delivery_authority() {
  start_test "build-close: 混合交付唯一收口"

  assert_file_contains "$BUILD_CLOSE_SKILL" "混合交付唯一收口" "build-close should own mixed delivery close" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "PMAI_ALLOW_MIXED_DELIVERY=build-close" "build-close should document guard bypass" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "缺 build contract" "build-close should stop without contract" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "不能把“已经改完了”伪装成 close" "build-close should reject fake close" || return
  pass_test
}

test_consumer_template_landing_rules() {
  start_test "template: 消费仓落地分流和混合提交规则"

  assert_file_contains "$AGENTS_TEMPLATE" "不等于直接改主原型" "template should say landing is not direct prototype edit" || return
  assert_file_contains "$AGENTS_TEMPLATE" "prototype-only 小改" "template should define small change" || return
  assert_file_contains "$AGENTS_TEMPLATE" "混合交付必须 build/close" "template should require build/close for mixed delivery" || return
  assert_file_contains "$AGENTS_TEMPLATE" '混合交付必须走 `/pmai-build` → `/pmai-build-close`' "template should repeat guardrail" || return
  pass_test
}

test_design_landing_gate
test_build_small_change_tightened
test_build_close_mixed_delivery_authority
test_consumer_template_landing_rules

report_results "build-close-hard-gates"
