#!/usr/bin/env bash
# init-project must create context only: no build target, code, mock board, or tool dependency.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"

test_no_framework_asset_copy() {
  start_test "init-project: does not copy framework sources into consumer"
  local bad
  bad=$(grep -nE 'cp[[:space:]]+-R.*(SKILL_DIR|FRAMEWORK_DIR/skills|FRAMEWORK_DIR/scripts|FRAMEWORK_DIR/agents)' "$INIT_PROJECT_SH" || true)
  if [ -n "$bad" ]; then
    _fail "framework assets leaked: $bad"
    return
  fi
  pass_test
}

test_context_only_e2e_without_gstack() {
  start_test "init-project: creates context spine without gstack or build artifacts"
  local base proj output leaked=""
  base=$(mktemp -d)
  proj="$base/test-proj"
  output="$base/init.out"

  if ! PATH="/usr/bin:/bin" PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" \
      "test-proj" "$proj" "给运营团队使用的审核产品" >"$output" 2>&1; then
    _fail "init-project failed without gstack"
    tail -30 "$output" >&2
    rm -rf "$base"
    return
  fi

  for file in PRODUCT.md PRODUCT-STATE.md DESIGN.md PRODUCT-RULES.md TODO.md AGENTS.md CLAUDE.md .pm-workflow/config.yml; do
    [ -f "$proj/$file" ] || leaked="$leaked missing:$file"
  done
  for path in .pm-workflow/project.yml prototype mockups .dev-port .pm-workflow/audits; do
    [ ! -e "$proj/$path" ] || leaked="$leaked unexpected:$path"
  done
  if grep -qE '^project:|dev_server:|screenshot_tool:' "$proj/.pm-workflow/config.yml"; then
    leaked="$leaked config-has-project-or-stack-defaults"
  fi
  if ! grep -q '/pmai-design' "$output"; then
    leaked="$leaked missing-design-next-up"
  fi
  if grep -qE 'Next Up.*(mockup|build)|直接.*prototype' "$output"; then
    leaked="$leaked stale-next-up-menu"
  fi
  if [ -d "$proj/.claude/skills" ] || [ -d "$proj/scripts" ] || [ -d "$proj/skills" ]; then
    leaked="$leaked framework-source-assets"
  fi

  rm -rf "$base"
  if [ -n "$leaked" ]; then
    _fail "context-only contract mismatch:$leaked"
    return
  fi
  pass_test
}

test_legacy_fourth_type_fails_with_migration() {
  start_test "init-project: legacy fourth project-type fails with design migration guidance"
  local base proj out rc
  base=$(mktemp -d)
  proj="$base/test-proj"
  out=$(PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" "test-proj" "$proj" "test" prototype 2>&1)
  rc=$?
  rm -rf "$base"
  if [ "$rc" != "0" ] && echo "$out" | grep -q '/pmai-design' && echo "$out" | grep -q 'project.yml'; then
    pass_test
  else
    _fail "legacy signature should fail clearly: rc=$rc out=$out"
  fi
}

test_special_chars_in_background() {
  start_test "init-project: background special characters remain literal"
  local base proj bg
  base=$(mktemp -d)
  proj="$base/test-proj"
  bg='A & B | C \ D 报表系统'
  if ! PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" "test-proj" "$proj" "$bg" >/dev/null 2>&1; then
    _fail "special-character initialization failed"
    rm -rf "$base"
    return
  fi
  if grep -qF "$bg" "$proj/CLAUDE.md"; then
    pass_test
  else
    _fail "background was not preserved"
  fi
  rm -rf "$base"
}

test_no_framework_asset_copy
test_context_only_e2e_without_gstack
test_legacy_fourth_type_fails_with_migration
test_special_chars_in_background

report_results "init-project"
