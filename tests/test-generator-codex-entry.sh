#!/usr/bin/env bash
# 生成器仓 Codex 主控入口测试：
# - 仓库根目录提供 AGENTS.md
# - AGENTS.md 指向本仓真相源
# - AGENTS.md 明确本仓开发优先读 repo-local assets，而不是安装态 ~/.pmai
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_MD="$REPO_ROOT/AGENTS.md"
CODEX_HOOKS="$REPO_ROOT/.codex/hooks.json"

test_root_agents_exists() {
  start_test "T1: 根目录 AGENTS.md 存在"

  assert_file_exists "$AGENTS_MD" "generator repo should expose root AGENTS.md" || return
  pass_test
}

test_root_agents_points_to_truth_sources() {
  start_test "T2: AGENTS.md 指向生成器真相源"

  assert_file_contains "$AGENTS_MD" "CLAUDE.md" "AGENTS.md should reference CLAUDE.md" || return
  assert_file_contains "$AGENTS_MD" "PRODUCT.md" "AGENTS.md should reference PRODUCT.md" || return
  assert_file_contains "$AGENTS_MD" "RUNTIME.md" "AGENTS.md should reference RUNTIME.md" || return
  assert_file_contains "$AGENTS_MD" "生成器仓" "AGENTS.md should identify this as generator repo" || return
  assert_file_contains "$AGENTS_MD" "默认用中文" "AGENTS.md should preserve Chinese default" || return
  pass_test
}

test_root_agents_uses_repo_local_assets() {
  start_test "T3: AGENTS.md 声明 repo-local assets 优先"

  assert_file_contains "$AGENTS_MD" "本仓 checkout 内的" "AGENTS.md should prefer repo-local checkout assets" || return
  assert_file_contains "$AGENTS_MD" "不要默认改用已安装的" "AGENTS.md should avoid defaulting to installed PMAI" || return
  assert_file_contains "$AGENTS_MD" "skills/<command-without-pmai-prefix>/SKILL.md" "AGENTS.md should map pmai commands to local skills" || return
  pass_test
}

test_root_agents_covers_three_codex_paths() {
  start_test "T4: AGENTS.md 覆盖三条 Codex 链路"

  assert_file_contains "$AGENTS_MD" "协同改造本框架仓" "AGENTS.md should cover framework collaboration" || return
  assert_file_contains "$AGENTS_MD" "从本 checkout 初始化消费仓" "AGENTS.md should cover consumer init from checkout" || return
  assert_file_contains "$AGENTS_MD" "在消费仓中使用 PMAI" "AGENTS.md should cover consumer usage" || return
  assert_file_contains "$AGENTS_MD" "bash scripts/init-project.sh" "AGENTS.md should show repo-local init command" || return
  assert_file_contains "$AGENTS_MD" "脚本返回 0 只代表 B 步完成" "AGENTS.md should not equate init script with full pmai-init-project" || return
  assert_file_contains "$AGENTS_MD" "C/D 步执行" "AGENTS.md should require C/D continuation after skeleton creation" || return
  pass_test
}

test_root_agents_defends_install_mode_boundary() {
  start_test "T5: AGENTS.md 保留 install/status 边界"

  assert_file_contains "$AGENTS_MD" "repo-local" "AGENTS.md should distinguish repo-local CLI" || return
  assert_file_contains "$AGENTS_MD" "installed user-facing CLI" "AGENTS.md should distinguish installed CLI" || return
  assert_file_contains "$AGENTS_MD" "--local" "AGENTS.md should mention removed local install mode" || return
  pass_test
}

test_generator_codex_hooks_exist() {
  start_test "T6: 生成器仓提供项目级 Codex hooks"

  assert_file_exists "$CODEX_HOOKS" "generator repo should expose .codex/hooks.json" || return
  assert_file_contains "$CODEX_HOOKS" "review-skill-guard.cjs" "generator Codex hooks should wire review guard" || return
  assert_file_contains "$CODEX_HOOKS" "check-doc-currency.cjs" "generator Codex hooks should wire doc currency guard" || return
  assert_file_contains "$CODEX_HOOKS" "check-sync-asset-jargon.cjs" "generator Codex hooks should wire sync jargon guard" || return
  assert_file_contains "$CODEX_HOOKS" "check-stage-number-jargon.cjs" "generator Codex hooks should wire stage jargon guard" || return
  if grep -q "check-branch.sh" "$CODEX_HOOKS"; then
    _fail "生成器仓 Codex hooks 不应套消费仓 check-branch 写保护"
    return
  fi
  python3 -m json.tool "$CODEX_HOOKS" >/dev/null || {
    _fail ".codex/hooks.json 不是合法 JSON"
    return
  }
  pass_test
}

test_root_agents_exists
test_root_agents_points_to_truth_sources
test_root_agents_uses_repo_local_assets
test_root_agents_covers_three_codex_paths
test_root_agents_defends_install_mode_boundary
test_generator_codex_hooks_exist

report_results "generator-codex-entry"
