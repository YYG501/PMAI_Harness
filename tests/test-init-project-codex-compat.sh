#!/usr/bin/env bash
# Codex 主控入口兼容性测试：
# - framework 提供 AGENTS.md.tmpl
# - init-project 会把 AGENTS.md 和 .codex/hooks.json 生成到消费仓根目录
# - AGENTS.md 是薄入口，hooks 是 host 配置，二者引用 CLAUDE.md / PMAI_HOME，不复制 framework 源资产
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"
AGENTS_TMPL="$REPO_ROOT/templates/AGENTS.md.tmpl"
CODEX_HOOKS_TMPL="$REPO_ROOT/templates/codex-hooks.json.tmpl"
INSTALL_CODEX_HOOKS="$REPO_ROOT/scripts/install-codex-hooks.sh"

test_agents_template_exists_and_maps_codex() {
  start_test "T1: AGENTS.md.tmpl 存在并声明 Codex host mapping"

  assert_file_exists "$AGENTS_TMPL" "AGENTS.md.tmpl should exist" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI Codex Entry" "AGENTS.md.tmpl should name Codex entry" || return
  assert_file_contains "$AGENTS_TMPL" "CLAUDE.md" "AGENTS.md.tmpl should reference CLAUDE.md truth source" || return
  assert_file_contains "$AGENTS_TMPL" "驱动 Codex" "AGENTS.md.tmpl should map driver role to Codex" || return
  assert_file_contains "$AGENTS_TMPL" "skill-preamble.sh" "AGENTS.md.tmpl should use neutral PMAI preamble" || return
  assert_file_contains "$AGENTS_TMPL" "AskUserQuestion 不可用" "AGENTS.md.tmpl should define AskUser fallback" || return
  assert_file_contains "$AGENTS_TMPL" "默认用中文" "AGENTS.md.tmpl should preserve Chinese default" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI 消费仓" "AGENTS.md.tmpl should identify consumer repo" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI_HOME" "AGENTS.md.tmpl should resolve installed framework path" || return
  assert_file_contains "$AGENTS_TMPL" "不能在这里再跑" "AGENTS.md.tmpl should prevent re-init inside consumer repo" || return
  assert_file_contains "$AGENTS_TMPL" "install-codex-hooks.sh" "AGENTS.md.tmpl should tell Codex how to repair missing hooks" || return
  assert_file_contains "$AGENTS_TMPL" "不写死机器绑定路径" "AGENTS.md.tmpl should carry portable path principle" || return
  assert_file_contains "$AGENTS_TMPL" "/Users/<某人>/..." "AGENTS.md.tmpl should forbid user-specific local paths" || return
  pass_test
}

test_init_project_knows_agents_template() {
  start_test "T2: init-project.sh 白名单生成 AGENTS.md 并安装 Codex hooks"

  assert_file_contains "$INIT_PROJECT_SH" "templates/AGENTS.md.tmpl" "init-project should require AGENTS template" || return
  assert_file_contains "$INIT_PROJECT_SH" "templates/codex-hooks.json.tmpl" "init-project should require Codex hooks template" || return
  assert_file_contains "$INIT_PROJECT_SH" 'AGENTS.md)' "init-project should route AGENTS.md template" || return
  assert_file_contains "$INIT_PROJECT_SH" 'DEST="$TARGET_DIR/AGENTS.md"' "init-project should write root AGENTS.md" || return
  assert_file_contains "$INIT_PROJECT_SH" "install-codex-hooks.sh" "init-project should install project-level Codex hooks" || return
  pass_test
}

test_codex_hooks_template_shape() {
  start_test "T3: codex-hooks.json.tmpl 是项目级 Codex hook 配置"

  assert_file_exists "$CODEX_HOOKS_TMPL" "codex hooks template should exist" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" '"PreToolUse"' "Codex hooks should include PreToolUse" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" '"UserPromptSubmit"' "Codex hooks should include UserPromptSubmit" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" "check-branch.sh" "Codex hooks should wire check-branch" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" "review-skill-guard.cjs" "Codex hooks should wire review guard" || return
  python3 -m json.tool "$CODEX_HOOKS_TMPL" >/dev/null || {
    _fail "codex-hooks.json.tmpl 不是合法 JSON"
    return
  }
  pass_test
}

test_e2e_generates_agents_md_without_framework_assets() {
  start_test "T4: init-project e2e 生成 AGENTS.md / .codex/hooks.json 且不泄漏 framework 资产"

  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e（T1/T2 静态断言已覆盖生成路径）"
    return
  fi

  local base proj
  base=$(mktemp -d)
  proj="$base/codex-compat-proj"

  if ! PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" "codex-compat-proj" "$proj" "Codex 主控兼容测试" prototype \
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
  if [ ! -f "$proj/.codex/hooks.json" ]; then
    _fail "消费仓根目录未生成 .codex/hooks.json"
    rm -rf "$base"
    return
  fi

  if ! grep -q "Codex 主控" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺 Codex 主控说明"
    rm -rf "$base"
    return
  fi

  if ! grep -q "PMAI 消费仓" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺消费仓定位"
    rm -rf "$base"
    return
  fi

  if ! grep -q "不能在这里再跑" "$proj/AGENTS.md" || ! grep -q "/pmai-init-project" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 未阻止消费仓重复 init"
    rm -rf "$base"
    return
  fi
  if ! grep -q "不写死机器绑定路径" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺路径可迁移原则"
    rm -rf "$base"
    return
  fi
  if ! grep -q "check-branch.sh" "$proj/.codex/hooks.json" || ! grep -q "review-skill-guard.cjs" "$proj/.codex/hooks.json"; then
    _fail "生成的 .codex/hooks.json 未注册 PMAI hooks"
    rm -rf "$base"
    return
  fi
  python3 -m json.tool "$proj/.codex/hooks.json" >/dev/null || {
    _fail "生成的 .codex/hooks.json 不是合法 JSON"
    rm -rf "$base"
    return
  }

  if [ -d "$proj/.claude/skills" ] || [ -d "$proj/.claude/scripts" ] || [ -d "$proj/.claude/agents" ]; then
    _fail "消费仓 .claude/ 泄漏 framework 资产"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_install_codex_hooks_merges_existing_hooks() {
  start_test "T5: install-codex-hooks.sh merge 既有 hook 且幂等"

  local base repo
  base=$(mktemp -d)
  repo="$base/repo"
  mkdir -p "$repo/.codex"
  (
    cd "$repo" || exit 1
    git init -b main >/dev/null 2>&1
  )
  cat > "$repo/.codex/hooks.json" <<'JSON'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo keep-existing"
          }
        ]
      }
    ]
  }
}
JSON

  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_CODEX_HOOKS") >/tmp/test-install-codex-hooks.out 2>&1; then
    _fail "install-codex-hooks.sh 执行失败"
    cat /tmp/test-install-codex-hooks.out >&2
    rm -rf "$base"
    return
  fi
  if ! grep -q "keep-existing" "$repo/.codex/hooks.json"; then
    _fail "既有 Codex hook 被覆盖"
    rm -rf "$base"
    return
  fi
  if ! grep -q "check-branch.sh" "$repo/.codex/hooks.json"; then
    _fail "PMAI check-branch hook 未安装"
    rm -rf "$base"
    return
  fi
  if ! grep -q "review-skill-guard.cjs" "$repo/.codex/hooks.json"; then
    _fail "PMAI review guard hook 未安装"
    rm -rf "$base"
    return
  fi

  (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_CODEX_HOOKS") >/tmp/test-install-codex-hooks-2.out 2>&1 || {
    _fail "install-codex-hooks.sh 第二次执行失败"
    cat /tmp/test-install-codex-hooks-2.out >&2
    rm -rf "$base"
    return
  }

  local guard_count
  guard_count=$(grep -c "review-skill-guard.cjs" "$repo/.codex/hooks.json")
  if [ "$guard_count" != "1" ]; then
    _fail "install-codex-hooks.sh 非幂等，review guard 出现 $guard_count 次"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_agents_template_exists_and_maps_codex
test_init_project_knows_agents_template
test_codex_hooks_template_shape
test_e2e_generates_agents_md_without_framework_assets
test_install_codex_hooks_merges_existing_hooks

report_results "init-project-codex-compat"
