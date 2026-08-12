#!/usr/bin/env bash
# OpenCode Builder 与遗留主控资产兼容性测试：
# - 新 install/upgrade/init 不再生成 OpenCode 主控入口
# - OpenCode adapter/profile 继续作为外部 Builder
# - 旧 command renderer 只保留为显式兼容工具，便于诊断和受控清理
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
    "$home/skills/build-close" "$home/skills/publish-to-lark" "$home/skills/status" \
    "$home/skills/_shared"
  printf "# Build\n" > "$home/skills/build/SKILL.md"
  printf "# Init\n" > "$home/skills/init-project/SKILL.md"
  printf "# Upgrade\n" > "$home/skills/pmai-upgrade/SKILL.md"
  printf "# Close\n" > "$home/skills/build-close/SKILL.md"
  printf "# Publish\n" > "$home/skills/publish-to-lark/SKILL.md"
  printf "# Status\n" > "$home/skills/status/SKILL.md"
  printf "%s\n" "$home"
}

test_template_declares_opencode_builder_boundary() {
  start_test "T1: AGENTS.md.tmpl 只声明 OpenCode Builder 边界"

  assert_file_exists "$INSTALL_OPENCODE" "install-opencode-commands.sh should exist" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI Agent Entry" "AGENTS.md.tmpl should be generic agent entry" || return
  assert_file_contains "$AGENTS_TMPL" "Kimi Code、OpenCode 和 Cursor Agent" "AGENTS.md.tmpl should mention OpenCode among Builders" || return
  assert_file_contains "$AGENTS_TMPL" '只可由 `/pmai-build` 选作外部 Builder' "AGENTS.md.tmpl should limit OpenCode to Builder" || return
  assert_file_contains "$AGENTS_TMPL" "新消费仓不得生成 Kimi/OpenCode 主控入口" "AGENTS.md.tmpl should reject new controller assets" || return
  if grep -q "install-opencode-commands.sh" "$AGENTS_TMPL"; then
    _fail "AGENTS.md.tmpl must not route PMAI commands through OpenCode"
    return
  fi
  if grep -q -- ".cursor" "$AGENTS_TMPL"; then
    _fail "AGENTS.md.tmpl should not generate Cursor guidance in this round"
    return
  fi
  pass_test
}

test_global_opencode_commands_are_thin_routes() {
  start_test "T2: 遗留 OpenCode renderer 仍可确定性还原旧 command"

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
  local close_cmd publish_cmd status_cmd
  close_cmd="$opencode_dir/commands/pmai-build-close.md"
  publish_cmd="$opencode_dir/commands/pmai-publish-to-lark.md"
  status_cmd="$opencode_dir/commands/pmai-status.md"
  assert_file_exists "$close_cmd" "build-close compatibility entry should remain invocable" || { rm -rf "$base"; return; }
  assert_file_exists "$publish_cmd" "publish-to-lark manual entry should remain invocable" || { rm -rf "$base"; return; }
  assert_file_contains "$close_cmd" '$PMAI_HOME/skills/build-close/SKILL.md' "build-close command should route to its skill" || { rm -rf "$base"; return; }
  assert_file_contains "$publish_cmd" '$PMAI_HOME/skills/publish-to-lark/SKILL.md' "publish command should route to its skill" || { rm -rf "$base"; return; }
  assert_file_contains "$status_cmd" 'PMAI_PREAMBLE_READ_ONLY=1' "status preamble must stay read-only" || { rm -rf "$base"; return; }
  if grep -q 'PMAI_PREAMBLE_READ_ONLY=1' "$cmd"; then
    _fail "non-status OpenCode commands should keep the existing preamble mode"
    rm -rf "$base"
    return
  fi
  if ! python3 - "$close_cmd" "$publish_cmd" "$status_cmd" <<'PY'
import sys
from pathlib import Path

for value in sys.argv[1:]:
    text = Path(value).read_text(encoding="utf-8")
    parts = text.split("---", 2)
    assert len(parts) == 3 and "description:" in parts[1], value
PY
  then
    _fail "manual/status OpenCode command frontmatter should be parseable"
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

test_global_opencode_check_detects_and_repairs_drift() {
  start_test "T3: 全局 OpenCode command 漂移可检查并由重装逐字修复"

  local base pmai_home opencode_dir cmd expected
  base=$(mktemp -d)
  pmai_home=$(make_fake_pmai_home "$base")
  opencode_dir="$base/opencode"
  cmd="$opencode_dir/commands/pmai-build.md"
  expected="$base/pmai-build.expected.md"

  if ! PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$opencode_dir" bash "$INSTALL_OPENCODE" --global \
       >"$base/install.out" 2>&1; then
    _fail "drift fixture 的全局 OpenCode command 安装失败"
    cat "$base/install.out" >&2
    rm -rf "$base"
    return
  fi
  cp "$cmd" "$expected" || {
    _fail "无法保存未篡改的 OpenCode command 基线"
    rm -rf "$base"
    return
  }
  printf "\n篡改内容\n" >> "$cmd"

  if PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$opencode_dir" bash "$INSTALL_OPENCODE" --global --check \
       >"$base/check-drift.out" 2>&1; then
    _fail "被篡改的全局 OpenCode command 应使 --check 非零"
    rm -rf "$base"
    return
  fi

  if ! PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$opencode_dir" bash "$INSTALL_OPENCODE" --global \
       >"$base/reinstall.out" 2>&1; then
    _fail "重装全局 OpenCode command 应修复漂移"
    cat "$base/reinstall.out" >&2
    rm -rf "$base"
    return
  fi
  if ! cmp -s "$expected" "$cmd"; then
    _fail "重装后全局 OpenCode command 必须与渲染基线逐字一致"
    rm -rf "$base"
    return
  fi
  if ! PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$opencode_dir" bash "$INSTALL_OPENCODE" --global --check \
       >"$base/check-restored.out" 2>&1; then
    _fail "重装修复后全局 OpenCode command 应通过 --check"
    cat "$base/check-restored.out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_global_opencode_install_rejects_file_paths() {
  start_test "T4: 全局 OpenCode 目录或 commands 为普通文件时安装失败且不报成功"

  local base pmai_home config_file commands_root output rc
  base=$(mktemp -d)
  pmai_home=$(make_fake_pmai_home "$base")

  config_file="$base/.opencode"
  printf "not a directory\n" > "$config_file"
  output="$base/config-file.out"
  PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$config_file" bash "$INSTALL_OPENCODE" --global \
    >"$output" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    _fail "OPENCODE_CONFIG_DIR 是普通文件时安装必须失败"
    rm -rf "$base"
    return
  fi
  if grep -Fq "installed " "$output"; then
    _fail "OPENCODE_CONFIG_DIR 是普通文件时不能报告安装成功"
    rm -rf "$base"
    return
  fi

  commands_root="$base/opencode"
  mkdir -p "$commands_root"
  printf "not a directory\n" > "$commands_root/commands"
  output="$base/commands-file.out"
  PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$commands_root" bash "$INSTALL_OPENCODE" --global \
    >"$output" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    _fail "commands 是普通文件时安装必须失败"
    rm -rf "$base"
    return
  fi
  if grep -Fq "installed " "$output"; then
    _fail "commands 是普通文件时不能报告安装成功"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_opencode_config_is_lightweight() {
  start_test "T5: 项目级 OpenCode 配置轻量且不复制 framework 源资产"

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

test_project_opencode_check_is_read_only_and_detects_drift() {
  start_test "T5b: 项目级 OpenCode --check 只读检测 command 与配置漂移"

  local base pmai_home project command before after rc
  base=$(mktemp -d)
  pmai_home=$(make_fake_pmai_home "$base")
  project="$base/project"
  mkdir -p "$project"
  PMAI_HOME="$pmai_home" bash "$INSTALL_OPENCODE" --project "$project" >/dev/null 2>&1 || {
    _fail "project OpenCode fixture install failed"
    rm -rf "$base"
    return
  }
  before=$(find "$project" -type f -exec shasum -a 256 {} \; | sort)
  if ! PMAI_HOME="$pmai_home" bash "$INSTALL_OPENCODE" --project "$project" --check >/dev/null 2>&1; then
    _fail "current project OpenCode entries should pass --check"
    rm -rf "$base"
    return
  fi
  after=$(find "$project" -type f -exec shasum -a 256 {} \; | sort)
  if [ "$before" != "$after" ]; then
    _fail "project OpenCode --check modified files"
    rm -rf "$base"
    return
  fi

  command="$project/.opencode/commands/pmai-build.md"
  printf '\nlocal drift\n' >> "$command"
  PMAI_HOME="$pmai_home" bash "$INSTALL_OPENCODE" --project "$project" --check >/dev/null 2>&1
  rc=$?
  if [ "$rc" != "1" ]; then
    _fail "modified project command should return drift rc=1, got $rc"
    rm -rf "$base"
    return
  fi
  PMAI_HOME="$pmai_home" bash "$INSTALL_OPENCODE" --project "$project" >/dev/null 2>&1
  printf '{"instructions": [], "permission": {}}\n' > "$project/opencode.json"
  PMAI_HOME="$pmai_home" bash "$INSTALL_OPENCODE" --project "$project" --check >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "1" ]; then
    pass_test
  else
    _fail "invalid project opencode.json should return drift rc=1, got $rc"
  fi
  rm -rf "$base"
}

test_cli_scripts_limit_opencode_to_builder_and_cleanup() {
  start_test "T6: 新生命周期不生成 OpenCode 主控，仍保留 Builder 与清理"

  if grep -q "install-opencode-commands.sh" "$REPO_ROOT/bin/pmai-install" \
    || grep -q "install-opencode-commands.sh" "$REPO_ROOT/bin/pmai-upgrade" \
    || grep -q 'install-opencode-commands.sh.*--project' "$INIT_PROJECT_SH"; then
    _fail "install/upgrade/init must not create or refresh OpenCode controllers"
    return
  fi
  assert_file_contains "$REPO_ROOT/bin/pmai-uninstall" "OpenCode slash commands removed" "uninstall should clean OpenCode commands" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-doctor" "旧 OpenCode PMAI 主控 command" "doctor should report legacy OpenCode commands" || return
  if [ -e "$REPO_ROOT/bin/pmai-status" ]; then
    _fail "removed CLI status wrapper should not remain"
    return
  fi
  assert_file_contains "$REPO_ROOT/templates/pm-workflow.config.yml.tmpl" "executor: opencode" "OpenCode builder profile should remain" || return
  if [ ! -x "$REPO_ROOT/scripts/exec-adapters/opencode.sh" ]; then
    _fail "OpenCode Builder adapter should remain executable"
    return
  fi
  pass_test
}

test_template_and_scripts_do_not_add_cursor() {
  start_test "T7: 本轮不生成 Cursor 配置"

  if grep -q -- ".cursor" "$INSTALL_OPENCODE" "$INIT_PROJECT_SH" "$AGENTS_TMPL"; then
    _fail "OpenCode-only implementation should not generate Cursor config"
    return
  fi
  pass_test
}

test_template_declares_opencode_builder_boundary
test_global_opencode_commands_are_thin_routes
test_global_opencode_check_detects_and_repairs_drift
test_global_opencode_install_rejects_file_paths
test_project_opencode_config_is_lightweight
test_project_opencode_check_is_read_only_and_detects_drift
test_cli_scripts_limit_opencode_to_builder_and_cleanup
test_template_and_scripts_do_not_add_cursor

report_results "opencode-host-compat"
