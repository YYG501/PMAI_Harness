#!/usr/bin/env bash
# Codex 主控入口兼容性测试：
# - framework 提供 AGENTS.md.tmpl
# - init-project 会把 AGENTS.md 生成到消费仓根目录
# - AGENTS.md 是薄入口，引用 CLAUDE.md / PMAI_HOME，不复制 framework 资产
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"
AGENTS_TMPL="$REPO_ROOT/templates/AGENTS.md.tmpl"

test_agents_template_exists_and_maps_codex() {
  start_test "T1: AGENTS.md.tmpl 存在并声明 Codex host mapping"

  assert_file_exists "$AGENTS_TMPL" "AGENTS.md.tmpl should exist" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI Codex Entry" "AGENTS.md.tmpl should name Codex entry" || return
  assert_file_contains "$AGENTS_TMPL" "CLAUDE.md" "AGENTS.md.tmpl should reference CLAUDE.md truth source" || return
  assert_file_contains "$AGENTS_TMPL" "驱动 Codex" "AGENTS.md.tmpl should map driver role to Codex" || return
  assert_file_contains "$AGENTS_TMPL" "skill-preamble.sh" "AGENTS.md.tmpl should use neutral PMAI preamble" || return
  assert_file_contains "$AGENTS_TMPL" "AskUserQuestion 不可用" "AGENTS.md.tmpl should define AskUser fallback" || return
  pass_test
}

test_init_project_knows_agents_template() {
  start_test "T2: init-project.sh 白名单生成 AGENTS.md"

  assert_file_contains "$INIT_PROJECT_SH" "templates/AGENTS.md.tmpl" "init-project should require AGENTS template" || return
  assert_file_contains "$INIT_PROJECT_SH" 'AGENTS.md)' "init-project should route AGENTS.md template" || return
  assert_file_contains "$INIT_PROJECT_SH" 'DEST="$TARGET_DIR/AGENTS.md"' "init-project should write root AGENTS.md" || return
  pass_test
}

test_e2e_generates_agents_md_without_framework_assets() {
  start_test "T3: init-project e2e 生成根 AGENTS.md 且不泄漏 framework 资产"

  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e（T1/T2 静态断言已覆盖生成路径）"
    return
  fi

  local base proj
  base=$(mktemp -d)
  proj="$base/codex-compat-proj"

  if ! bash "$INIT_PROJECT_SH" "codex-compat-proj" "$proj" "Codex 主控兼容测试" prototype \
       >/tmp/test-init-project-codex-compat.out 2>&1; then
    _fail "init-project.sh 执行失败 —— 见 /tmp/test-init-project-codex-compat.out"
    tail -20 /tmp/test-init-project-codex-compat.out >&2
    rm -rf "$base"
    return
  fi

  if [ ! -f "$proj/AGENTS.md" ]; then
    _fail "消费仓根目录未生成 AGENTS.md"
    rm -rf "$base"
    return
  fi

  if ! grep -q "Codex 主控" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺 Codex 主控说明"
    rm -rf "$base"
    return
  fi

  if [ -d "$proj/.claude/skills" ] || [ -d "$proj/.claude/scripts" ] || [ -d "$proj/.claude/agents" ]; then
    _fail "消费仓 .claude/ 泄漏 framework 资产"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_agents_template_exists_and_maps_codex
test_init_project_knows_agents_template
test_e2e_generates_agents_md_without_framework_assets

report_results "init-project-codex-compat"
