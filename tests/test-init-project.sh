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

test_allow_existing_rejects_template_conflicts_before_writing() {
  start_test "init-project: --allow-existing preserves conflicting source material"
  local base proj out rc original
  base=$(mktemp -d)
  proj="$base/existing-materials"
  mkdir -p "$proj"
  original="# Existing product notes

Do not overwrite this file."
  printf '%s\n' "$original" > "$proj/PRODUCT.md"

  out=$(PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" \
    "test-proj" "$proj" "资料目录接入" --allow-existing 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "conflicting PRODUCT.md should block initialization"
  elif [ "$(cat "$proj/PRODUCT.md")" != "$original" ]; then
    _fail "existing PRODUCT.md was modified"
  elif [ -e "$proj/AGENTS.md" ] || [ -e "$proj/.pm-workflow/config.yml" ]; then
    _fail "initialization wrote files before reporting conflicts"
  elif ! echo "$out" | grep -q "PRODUCT.md"; then
    _fail "conflict output should identify PRODUCT.md: $out"
  else
    pass_test
  fi
  rm -rf "$base"
}

test_missing_git_identity_fails_before_writing() {
  start_test "init-project: missing Git identity fails before writing target"
  local base proj output rc
  base=$(mktemp -d)
  proj="$base/test-proj"
  output="$base/init.out"

  env \
    -u GIT_AUTHOR_NAME \
    -u GIT_AUTHOR_EMAIL \
    -u GIT_COMMITTER_NAME \
    -u GIT_COMMITTER_EMAIL \
    -u EMAIL \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=user.useConfigOnly \
    GIT_CONFIG_VALUE_0=true \
    PMAI_HOME="$REPO_ROOT" \
    bash "$INIT_PROJECT_SH" "test-proj" "$proj" "test" >"$output" 2>&1
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "initialization should fail without Git identity"
  elif [ -e "$proj" ]; then
    _fail "target directory should not be created before Git identity passes"
  elif ! grep -q 'git config --global user.name' "$output" \
    || ! grep -q 'git config --global user.email' "$output"; then
    _fail "failure should provide Git identity recovery commands"
  else
    pass_test
  fi
  rm -rf "$base"
}

test_no_framework_asset_copy
test_context_only_e2e_without_gstack
test_legacy_fourth_type_fails_with_migration
test_special_chars_in_background
test_allow_existing_rejects_template_conflicts_before_writing
test_missing_git_identity_fails_before_writing

report_results "init-project"
