#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/active-build-fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$REPO_ROOT/hooks/active-build-guard.cjs"

run_guard() {
  local prompt="$1"
  python3 - "$ACTIVE_BUILD_FIXTURE" "$prompt" <<'PY' | node "$GUARD"
import json
import sys
print(json.dumps({"cwd": sys.argv[1], "prompt": sys.argv[2]}, ensure_ascii=False))
PY
}

guard_additional_context() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'
}

test_natural_language_resumes_prototype_build() {
  start_test "active-build guard: 自然语言查看问题续接 prototype build"
  active_build_fixture_setup prototype iterating
  local out
  out=$(run_guard "启动起来看看，现在还有什么没有解决的问题吗" | guard_additional_context)
  if echo "$out" | grep -q "ACTIVE BUILD 续接护栏" \
     && echo "$out" | grep -q "interactive-simulation" \
     && echo "$out" | grep -q "simulate_by_default" \
     && echo "$out" | grep -q "不得转成无范围约束的通用 QA" \
     && echo "$out" | grep -q "规格已有的要求直接作为覆盖要求" \
     && echo "$out" | grep -q "不得重新包装成 PM 待确认问题"; then
    pass_test
  else
    _fail "prototype continuation context missing: $out"
  fi
  active_build_fixture_teardown
}

test_no_active_build_is_silent() {
  start_test "active-build guard: 无 active build 静默"
  active_build_fixture_setup prototype designing
  local out
  out=$(run_guard "启动起来看看")
  if [ -z "$out" ]; then
    pass_test
  else
    _fail "guard should be silent without resumable build: $out"
  fi
  active_build_fixture_teardown
}

test_product_keeps_production_depth() {
  start_test "active-build guard: product 保持 production implementation"
  active_build_fixture_setup product iterating
  local out
  out=$(run_guard "看看还有什么问题" | guard_additional_context)
  if echo "$out" | grep -q "production-implementation" \
     && echo "$out" | grep -q "product 仍按 production-implementation 检查"; then
    pass_test
  else
    _fail "product continuation context missing: $out"
  fi
  active_build_fixture_teardown
}

test_multiple_active_builds_require_module() {
  start_test "active-build guard: 多个 active build 不猜模块"
  active_build_fixture_setup prototype iterating
  active_build_fixture_add_second
  local out
  out=$(run_guard "启动看看" | guard_additional_context)
  if echo "$out" | grep -q '"status": "ambiguous"' \
     && echo "$out" | grep -q "只让 PM 指明本轮要继续看的模块"; then
    pass_test
  else
    _fail "multiple builds should inject ambiguity: $out"
  fi
  active_build_fixture_teardown
}

test_explicit_new_work_does_not_force_active_build() {
  start_test "active-build guard: 显式新 design 不强制当前 build"
  active_build_fixture_setup prototype iterating
  local out
  out=$(run_guard "/pmai-design 新建一个无关模块")
  if [ -z "$out" ]; then
    pass_test
  else
    _fail "explicit new workflow should bypass active build guard: $out"
  fi
  active_build_fixture_teardown
}

test_natural_language_resumes_prototype_build
test_no_active_build_is_silent
test_product_keeps_production_depth
test_multiple_active_builds_require_module
test_explicit_new_work_does_not_force_active_build

report_results "active-build-guard"
