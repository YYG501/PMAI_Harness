#!/usr/bin/env bash
# OpenCode 主控入口兼容性测试：
# - install/upgrade 能生成全局 OpenCode slash commands
# - init-project 能生成项目级 .opencode/commands + opencode.json
# - command 文件只路由到 PMAI_HOME，不复制 framework 源资产，不生成 Cursor 配置
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_OPENCODE="$REPO_ROOT/scripts/install-opencode-commands.sh"
AGENTS_TMPL="$REPO_ROOT/templates/AGENTS.md.tmpl"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"

make_fake_pmai_home() {
  local base="$1"
  local home="$base/pmai"

  mkdir -p "$home/skills/build" "$home/skills/init-project" "$home/skills/pmai-upgrade" \
    "$home/skills/build-close" "$home/skills/publish-to-lark" "$home/skills/_shared"
  printf "# Build\n" > "$home/skills/build/SKILL.md"
  printf "# Init\n" > "$home/skills/init-project/SKILL.md"
  printf "# Upgrade\n" > "$home/skills/pmai-upgrade/SKILL.md"
  printf "# Close\n" > "$home/skills/build-close/SKILL.md"
  printf "# Publish\n" > "$home/skills/publish-to-lark/SKILL.md"
  printf "%s\n" "$home"
}

test_template_declares_opencode_entry() {
  start_test "T1: AGENTS.md.tmpl 声明 OpenCode 主控入口"

  assert_file_exists "$INSTALL_OPENCODE" "install-opencode-commands.sh should exist" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI Agent Entry" "AGENTS.md.tmpl should be generic agent entry" || return
  assert_file_contains "$AGENTS_TMPL" "OpenCode" "AGENTS.md.tmpl should mention OpenCode" || return
  assert_file_contains "$AGENTS_TMPL" ".opencode/commands" "AGENTS.md.tmpl should mention project OpenCode commands" || return
  assert_file_contains "$AGENTS_TMPL" "opencode.json" "AGENTS.md.tmpl should mention opencode.json" || return
  assert_file_contains "$AGENTS_TMPL" "install-opencode-commands.sh" "AGENTS.md.tmpl should tell how to repair OpenCode commands" || return
  if grep -q -- ".cursor" "$AGENTS_TMPL"; then
    _fail "AGENTS.md.tmpl should not generate Cursor guidance in this round"
    return
  fi
  pass_test
}

test_global_opencode_commands_are_thin_routes() {
  start_test "T2: 全局 OpenCode commands 只路由到 PMAI_HOME skill"

  local base pmai_home opencode_dir cmd
  base=$(mktemp -d)
  pmai_home=$(make_fake_pmai_home "$base")
  opencode_dir="$base/opencode"

  if ! PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$opencode_dir" bash "$INSTALL_OPENCODE" --global \
       >/tmp/test-opencode-global.out 2>&1; then
    _fail "install-opencode-commands.sh --global 执行失败"
    cat /tmp/test-opencode-global.out >&2
    rm -rf "$base"
    return
  fi

  cmd="$opencode_dir/commands/pmai-build.md"
  assert_file_exists "$cmd" "global OpenCode command should be written" || { rm -rf "$base"; return; }
  assert_file_contains "$cmd" "Run PMAI /pmai-build workflow" "command should have slash description" || { rm -rf "$base"; return; }
  assert_file_contains "$cmd" '$ARGUMENTS' "command should preserve OpenCode arguments variable" || { rm -rf "$base"; return; }
  assert_file_contains "$cmd" '$PMAI_HOME/skills/build/SKILL.md' "command should route to installed build skill" || { rm -rf "$base"; return; }
  assert_file_contains "$cmd" "OpenCode 不使用 Codex hooks" "command should be honest about hook model" || { rm -rf "$base"; return; }

  if [ -e "$opencode_dir/commands/pmai-_shared.md" ]; then
    _fail "_shared should not become a slash command"
    rm -rf "$base"
    return
  fi
  if [ -e "$opencode_dir/commands/pmai-build-close.md" ] \
     || [ -e "$opencode_dir/commands/pmai-publish-to-lark.md" ]; then
    _fail "internal recovery/execution workflows should not become OpenCode commands"
    rm -rf "$base"
    return
  fi
  if grep -q -- "/Users/" "$cmd"; then
    _fail "OpenCode command should not contain machine-bound paths"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_opencode_config_is_lightweight() {
  start_test "T3: 项目级 OpenCode 配置轻量且不复制 framework 源资产"

  local base pmai_home project cmd
  base=$(mktemp -d)
  pmai_home=$(make_fake_pmai_home "$base")
  project="$base/project"
  mkdir -p "$project"

  if ! PMAI_HOME="$pmai_home" bash "$INSTALL_OPENCODE" --project "$project" \
       >/tmp/test-opencode-project.out 2>&1; then
    _fail "install-opencode-commands.sh --project 执行失败"
    cat /tmp/test-opencode-project.out >&2
    rm -rf "$base"
    return
  fi

  cmd="$project/.opencode/commands/pmai-init-project.md"
  assert_file_exists "$cmd" "project OpenCode command should be written" || { rm -rf "$base"; return; }
  assert_file_exists "$project/opencode.json" "project opencode.json should be written" || { rm -rf "$base"; return; }
  python3 -m json.tool "$project/opencode.json" >/dev/null || {
    _fail "project opencode.json should be valid JSON"
    rm -rf "$base"
    return
  }
  assert_file_contains "$project/opencode.json" "AGENTS.md" "opencode.json should include AGENTS.md instructions" || { rm -rf "$base"; return; }
  assert_file_contains "$project/opencode.json" "CLAUDE.md" "opencode.json should include CLAUDE.md instructions" || { rm -rf "$base"; return; }
  assert_file_contains "$project/opencode.json" '"edit": "ask"' "opencode.json should ask before edits" || { rm -rf "$base"; return; }
  assert_file_contains "$project/opencode.json" '"bash": "ask"' "opencode.json should ask before bash" || { rm -rf "$base"; return; }

  if [ -d "$project/skills" ] || [ -d "$project/scripts" ] || [ -d "$project/.cursor" ]; then
    _fail "project install should not copy framework assets or create Cursor config"
    rm -rf "$base"
    return
  fi
  if grep -q -- "/Users/" "$cmd" "$project/opencode.json"; then
    _fail "project OpenCode config should not contain machine-bound paths"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_cli_scripts_reference_opencode_commands() {
  start_test "T4: CLI install/upgrade/uninstall/status/doctor 接入 OpenCode commands"

  assert_file_contains "$REPO_ROOT/bin/pmai-install" "install-opencode-commands.sh" "install should generate OpenCode commands" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-upgrade" "install-opencode-commands.sh" "upgrade should refresh OpenCode commands" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-uninstall" "OpenCode slash commands removed" "uninstall should clean OpenCode commands" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-status" "OpenCode slash commands" "status should report OpenCode commands" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-doctor" "OpenCode slash commands" "doctor should check OpenCode commands" || return
  assert_file_contains "$INIT_PROJECT_SH" "install-opencode-commands.sh" "init-project should install project OpenCode commands" || return
  pass_test
}

test_template_and_scripts_do_not_add_cursor() {
  start_test "T5: 本轮不生成 Cursor 配置"

  if grep -q -- ".cursor" "$INSTALL_OPENCODE" "$INIT_PROJECT_SH" "$AGENTS_TMPL"; then
    _fail "OpenCode-only implementation should not generate Cursor config"
    return
  fi
  pass_test
}

test_template_declares_opencode_entry
test_global_opencode_commands_are_thin_routes
test_project_opencode_config_is_lightweight
test_cli_scripts_reference_opencode_commands
test_template_and_scripts_do_not_add_cursor

report_results "opencode-host-compat"
