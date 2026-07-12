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
LAND_WORK="$REPO_ROOT/scripts/land-work.sh"

test_design_landing_gate() {
  start_test "design: 落地意图进入统一 build，不在 design 直改"

  assert_file_contains "$DESIGN_SKILL" "落地 / 实现 / 做进主原型 / 提交 / 可以做了" "design should identify landing intent" || return
  assert_file_contains "$DESIGN_SKILL" "不等于授权 design 直接改主原型或真实产品" "design must not edit build targets" || return
  assert_file_contains "$DESIGN_SKILL" '自动交给 `/pmai-build`' "design should route landing to build" || return
  assert_file_contains "$DESIGN_METHOD" "混合交付转 build" "method should mirror mixed delivery route" || return
  pass_test
}

test_build_small_change_tightened() {
  start_test "build: mockup/spec 落地不能伪装成 quick-fix"

  assert_file_contains "$BUILD_SKILL" "把 mockup / spec 做进最终 build target" "build should force full gate for mock/spec landing" || return
  assert_file_contains "$BUILD_SKILL" "不得伪装成小改" "build should forbid mixed quick-fix" || return
  assert_file_contains "$BUILD_SKILL" "只要进入本 skill，就按完整 build 执行" "mock/spec landing should keep the full lifecycle" || return
  assert_file_contains "$BUILD_SKILL" "开工前确认工作环境" "full build should confirm its work environment" || return
  assert_file_contains "$BUILD_SKILL" "自动落地主线" "build should own automatic finalize" || return
  pass_test
}

test_build_close_mixed_delivery_authority() {
  start_test "finalize: build 自动收口，build-close 仅兼容恢复"

  assert_file_contains "$BUILD_CLOSE_SKILL" "正常用户链路不再要求 PM 额外运行本命令" "build-close should not be a normal user step" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "只按 build contract 和 lifecycle state" "recovery must use the same contract" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "文档失败不重复 merge" "docs recovery must not repeat merge" || return
  assert_file_contains "$LAND_WORK" "PMAI_ALLOW_MIXED_DELIVERY=build-close" "automatic finalize should use the mixed-delivery guard token internally" || return
  pass_test
}

test_consumer_template_landing_rules() {
  start_test "template: 消费仓完整 build 自动 finalize"

  assert_file_contains "$AGENTS_TEMPLATE" '完整交付走 `/pmai-build` 并自动 finalize' "template should say landing uses build" || return
  assert_file_contains "$AGENTS_TEMPLATE" "混合交付必须走完整 build" "template should require the full lifecycle" || return
  assert_file_contains "$AGENTS_TEMPLATE" '`/pmai-build-close` 保留为兼容与恢复入口' "template should keep close as compatibility only" || return
  assert_file_contains "$AGENTS_TEMPLATE" "PM 说“可以提交 / 定稿 / 可以合并”即授权" "template should recognize natural-language finalization" || return
  pass_test
}

test_design_landing_gate
test_build_small_change_tightened
test_build_close_mixed_delivery_authority
test_consumer_template_landing_rules

report_results "build-close-hard-gates"
