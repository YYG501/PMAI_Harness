#!/usr/bin/env bash
# Regression tests for mixed prototype + docs/mockups commit guard.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CHECKER="$FRAMEWORK_ROOT/scripts/check-mixed-delivery.py"
INSTALL_HOOKS="$FRAMEWORK_ROOT/scripts/install-hooks.sh"
HOOK_TMPL="$FRAMEWORK_ROOT/templates/git-hooks/pre-commit.tmpl"
export PMAI_HOME="$FRAMEWORK_ROOT"

_run_checker() {
  (cd "$FIXTURE_DIR" && python3 "$CHECKER")
}

_stage_file() {
  local path="$1"
  mkdir -p "$(dirname "$FIXTURE_DIR/$path")"
  printf 'fixture\n' > "$FIXTURE_DIR/$path"
  (cd "$FIXTURE_DIR" && git add "$path")
}

test_prototype_only_passes() {
  start_test "mixed guard: prototype-only 通过"
  fixture_setup
  _stage_file "prototype/app.tsx"

  if _run_checker >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    pass_test
  else
    _fail "prototype-only 不应被拦"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$
  fixture_teardown
}

test_docs_only_passes() {
  start_test "mixed guard: docs-only 通过"
  fixture_setup
  _stage_file "docs/modules/capability/spec.md"

  if _run_checker >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    pass_test
  else
    _fail "docs-only 不应被拦"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$
  fixture_teardown
}

test_mockups_only_passes() {
  start_test "mixed guard: mockups-only 通过"
  fixture_setup
  _stage_file "mockups/capability/index.html"

  if _run_checker >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    pass_test
  else
    _fail "mockups-only 不应被拦"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$
  fixture_teardown
}

test_prototype_plus_docs_blocks() {
  start_test "mixed guard: prototype + docs/modules 阻止"
  fixture_setup
  _stage_file "prototype/app.tsx"
  _stage_file "docs/modules/capability/spec.md"

  if _run_checker >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    _fail "prototype + docs/modules 应被拦"
  elif grep -q "/pmai-build" /tmp/mixed.err.$$ && grep -q "自动完成最终检查" /tmp/mixed.err.$$ && grep -q "混合交付" /tmp/mixed.err.$$; then
    pass_test
  else
    _fail "阻断提示应说明混合交付由 /pmai-build 自动 finalize"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$
  fixture_teardown
}

test_prototype_plus_mockups_blocks() {
  start_test "mixed guard: prototype + mockups 阻止"
  fixture_setup
  _stage_file "prototype/app.tsx"
  _stage_file "mockups/capability/index.html"

  if _run_checker >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    _fail "prototype + mockups 应被拦"
  elif grep -q "/pmai-build" /tmp/mixed.err.$$ && grep -q "mockup" /tmp/mixed.err.$$; then
    pass_test
  else
    _fail "阻断提示应说明 mockup 混合交付"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$
  fixture_teardown
}

test_prototype_plus_docs_plus_mockups_blocks() {
  start_test "mixed guard: prototype + docs/modules + mockups 阻止"
  fixture_setup
  _stage_file "prototype/app.tsx"
  _stage_file "docs/modules/capability/spec.md"
  _stage_file "mockups/capability/index.html"

  if _run_checker >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    _fail "prototype + docs/modules + mockups 应被拦"
  elif grep -q "模块文档" /tmp/mixed.err.$$ && grep -q "mockup" /tmp/mixed.err.$$; then
    pass_test
  else
    _fail "阻断提示应同时列出 docs 和 mockups"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$
  fixture_teardown
}

test_build_close_allow_env_passes() {
  start_test "mixed guard: build-close 环境变量放行"
  fixture_setup
  _stage_file "prototype/app.tsx"
  _stage_file "docs/modules/capability/spec.md"

  if (cd "$FIXTURE_DIR" && PMAI_ALLOW_MIXED_DELIVERY=build-close python3 "$CHECKER") >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    pass_test
  else
    _fail "build-close 放行环境变量应允许混合提交"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$
  fixture_teardown
}

test_hook_template_calls_checker() {
  start_test "mixed guard: pre-commit 模板调用 checker"

  if grep -q "check-mixed-delivery.py" "$HOOK_TMPL"; then
    pass_test
  else
    _fail "pre-commit 模板未调用 check-mixed-delivery.py"
  fi
}

test_pre_commit_blocks_mixed_delivery() {
  start_test "mixed guard: pre-commit 实际阻止混合提交"
  fixture_setup
  (cd "$FIXTURE_DIR" && bash "$INSTALL_HOOKS") >/tmp/mixed.install.$$ 2>&1
  _stage_file "prototype/app.tsx"
  _stage_file "docs/modules/capability/spec.md"

  if (cd "$FIXTURE_DIR" && git commit -q -m "mixed delivery") >/tmp/mixed.$$ 2>/tmp/mixed.err.$$; then
    _fail "pre-commit 应阻止混合交付提交"
  elif grep -q "混合交付" /tmp/mixed.err.$$; then
    pass_test
  else
    _fail "pre-commit 阻断提示应包含混合交付"
    cat /tmp/mixed.err.$$ >&2
  fi
  rm -f /tmp/mixed.$$ /tmp/mixed.err.$$ /tmp/mixed.install.$$
  fixture_teardown
}

test_prototype_only_passes
test_docs_only_passes
test_mockups_only_passes
test_prototype_plus_docs_blocks
test_prototype_plus_mockups_blocks
test_prototype_plus_docs_plus_mockups_blocks
test_build_close_allow_env_passes
test_hook_template_calls_checker
test_pre_commit_blocks_mixed_delivery

report_results "mixed-delivery-guard"
