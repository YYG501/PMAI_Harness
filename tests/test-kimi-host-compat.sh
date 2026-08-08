#!/usr/bin/env bash
# Kimi Code first-class host and external builder regression: native skills,
# managed hooks, entry templates, lifecycle coverage, and current-host mapping.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANAGER="$REPO_ROOT/scripts/manage-kimi-hooks.py"
DISPATCH="$REPO_ROOT/scripts/kimi-hook-dispatch.sh"

test_kimi_native_entry_is_documented() {
  start_test "K1: 生成器和消费仓声明 Kimi 原生 /skill:pmai-* 入口"

  assert_file_contains "$REPO_ROOT/AGENTS.md" "/skill:pmai-build" "generator entry should document Kimi native command" || return
  assert_file_contains "$REPO_ROOT/templates/AGENTS.md.tmpl" "/skill:pmai-build" "consumer entry should document Kimi native command" || return
  assert_file_contains "$REPO_ROOT/templates/CLAUDE.md.tmpl" "/skill:pmai-status" "consumer charter should map status for Kimi" || return
  assert_file_contains "$REPO_ROOT/AGENTS.md" "重新完整读取本 checkout" "generator Kimi entry should prefer checkout sources" || return
  pass_test
}

test_kimi_hook_manager_preserves_user_config() {
  start_test "K2: Kimi hook manager 只维护标记区并保留用户配置"
  local tmp config before_without_block after_remove

  tmp=$(mktemp -d)
  config="$tmp/config.toml"
  printf '%s\n' 'default_model = "demo"' '' '[thinking]' 'enabled = true' > "$config"

  python3 "$MANAGER" install --config "$config" >/dev/null || {
    _fail "manage-kimi-hooks install failed"
    rm -rf "$tmp"
    return
  }
  python3 "$MANAGER" check --config "$config" >/dev/null || {
    _fail "manage-kimi-hooks check failed after install"
    rm -rf "$tmp"
    return
  }
  assert_file_contains "$config" 'event = "PreToolUse"' "Kimi hooks should include PreToolUse" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'event = "UserPromptSubmit"' "Kimi hooks should include UserPromptSubmit" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'kimi-hook-dispatch.sh' "Kimi hooks should route through scoped dispatcher" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'prompt-review' "Kimi hooks should keep review injection separate" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'prompt-build' "Kimi hooks should keep active build injection separate" || { rm -rf "$tmp"; return; }
  local prompt_hook_count
  prompt_hook_count=$(grep -c 'event = "UserPromptSubmit"' "$config")
  if [ "$prompt_hook_count" != "2" ]; then
    _fail "Kimi should install two independent prompt hooks, got $prompt_hook_count"
    rm -rf "$tmp"
    return
  fi

  before_without_block=$(sed -n '1,/^# >>> PMAI managed Kimi Code hooks >>>$/p' "$config" | sed '$d' | sed '/^[[:space:]]*$/d')
  python3 "$MANAGER" remove --config "$config" >/dev/null || {
    _fail "manage-kimi-hooks remove failed"
    rm -rf "$tmp"
    return
  }
  after_remove=$(sed '/^[[:space:]]*$/d' "$config")
  if [ "$before_without_block" != "$after_remove" ]; then
    _fail "Kimi hook remove should preserve non-PMAI config"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_kimi_dispatch_is_scoped_and_maps_write_path() {
  start_test "K3: Kimi 全局 Hook 仅作用于 PMAI 消费仓并映射 path 字段"
  local tmp consumer ordinary payload out rc

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  ordinary="$tmp/ordinary"
  mkdir -p "$consumer" "$ordinary"
  git -C "$consumer" init -q -b main
  git -C "$ordinary" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"path":"%s/src/app.ts","content":"x"}}' "$consumer" "$consumer")

  out=$(printf '%s' "$payload" | PMAI_HOME="$REPO_ROOT" bash "$DISPATCH" write 2>&1)
  rc=$?
  if [ "$rc" != "2" ]; then
    _fail "PMAI consumer main write should be denied after Kimi path mapping"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "main 分支写保护"; then
    _fail "Kimi write denial should preserve PMAI branch guard reason"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"path":"%s/src/app.ts","content":"x"}}' "$ordinary" "$ordinary")
  printf '%s' "$payload" | PMAI_HOME="$REPO_ROOT" bash "$DISPATCH" write >/dev/null 2>&1
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "global Kimi hook should be a no-op outside PMAI repos"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_lifecycle_surface_is_complete() {
  start_test "K4: install/upgrade/uninstall/doctor/status 覆盖 Kimi 宿主面"
  local file

  for file in pmai-install pmai-upgrade pmai-uninstall pmai-doctor pmai-status; do
    assert_file_contains "$REPO_ROOT/bin/$file" "KIMI_CODE_HOME" "$file should honor KIMI_CODE_HOME" || return
    assert_file_contains "$REPO_ROOT/bin/$file" "KIMI_SKILLS" "$file should manage Kimi skills" || return
  done
  assert_file_contains "$REPO_ROOT/bin/pmai-install" "manage-kimi-hooks.py" "install should manage Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-upgrade" "manage-kimi-hooks.py" "upgrade should refresh Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-uninstall" "manage-kimi-hooks.py" "uninstall should remove only managed Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-doctor" "Kimi Code PMAI-managed hooks" "doctor should validate Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-status" "Kimi native command" "status should show Kimi command syntax" || return
  pass_test
}

test_builder_supports_kimi_with_current_host_exclusion() {
  start_test "K5: Kimi 可作外部 builder，作为当前主控时排除同名 profile"
  local out

  out=$(python3 "$REPO_ROOT/scripts/builder-profile.py" list \
    "$REPO_ROOT/templates/pm-workflow.config.yml.tmpl" --current-host codex 2>&1) || {
    _fail "builder-profile should list Kimi for other hosts"
    echo "$out" >&2
    return
  }
  if ! echo "$out" | grep -q '"executor": "kimi-code"'; then
    _fail "Kimi should be available as an external builder for Codex"
    return
  fi

  out=$(python3 "$REPO_ROOT/scripts/builder-profile.py" list \
    "$REPO_ROOT/templates/pm-workflow.config.yml.tmpl" --current-host kimi-code 2>&1) || {
    _fail "builder-profile should accept --current-host kimi-code"
    echo "$out" >&2
    return
  }
  if ! echo "$out" | grep -q '"executor": "native"'; then
    _fail "Kimi host should keep current-session native build available"
    return
  fi
  if echo "$out" | grep -q '"executor": "kimi-code"'; then
    _fail "Kimi current host should exclude the same external profile"
    return
  fi
  if [ ! -x "$REPO_ROOT/scripts/exec-adapters/kimi-code.sh" ]; then
    _fail "Kimi external builder adapter should be executable"
    return
  fi
  pass_test
}

test_public_skill_names_match_kimi_native_commands() {
  start_test "K6: 公开 Skill frontmatter 与 Kimi 原生命令名一致"
  local skill_file skill_dir expected actual

  for skill_file in "$REPO_ROOT"/skills/*/SKILL.md; do
    skill_dir=$(basename "$(dirname "$skill_file")")
    case "$skill_dir" in
      _internal|_shared) continue ;;
      pmai-*) expected="$skill_dir" ;;
      *) expected="pmai-$skill_dir" ;;
    esac
    actual=$(sed -n 's/^name:[[:space:]]*//p' "$skill_file" | head -1)
    if [ "$actual" != "$expected" ]; then
      _fail "$skill_file should declare name: $expected for /skill:$expected, got: ${actual:-missing}"
      return
    fi
  done
  pass_test
}

test_no_machine_bound_kimi_paths() {
  start_test "K7: Kimi 宿主资产不写死机器路径"
  if grep -En -- '/Users/[A-Za-z0-9]' "$MANAGER" "$DISPATCH" "$REPO_ROOT/templates/AGENTS.md.tmpl" "$REPO_ROOT/templates/CLAUDE.md.tmpl"; then
    _fail "Kimi host assets should not contain machine-bound paths"
    return
  fi
  pass_test
}

test_kimi_dispatch_keeps_prompt_outputs_separate() {
  start_test "K8: Kimi prompt review 与 active build 分别分发"
  assert_file_contains "$DISPATCH" 'prompt-review' "dispatcher should expose review prompt mode" || return
  assert_file_contains "$DISPATCH" 'prompt-build' "dispatcher should expose active build prompt mode" || return
  if grep -Eq 'write\|bash\|prompt\)' "$DISPATCH"; then
    _fail "dispatcher should not concatenate two hook outputs through one prompt mode"
    return
  fi
  pass_test
}

test_kimi_native_entry_is_documented
test_kimi_hook_manager_preserves_user_config
test_kimi_dispatch_is_scoped_and_maps_write_path
test_kimi_lifecycle_surface_is_complete
test_builder_supports_kimi_with_current_host_exclusion
test_public_skill_names_match_kimi_native_commands
test_no_machine_bound_kimi_paths
test_kimi_dispatch_keeps_prompt_outputs_separate

report_results "kimi-host-compat"
