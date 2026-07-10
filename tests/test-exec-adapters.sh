#!/usr/bin/env bash
# Build executor adapter regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADAPTER_DIR="$FRAMEWORK_ROOT/scripts/exec-adapters"
BUILD_SKILL="$FRAMEWORK_ROOT/skills/build/SKILL.md"
AGENTS_TMPL="$FRAMEWORK_ROOT/templates/AGENTS.md.tmpl"
CLAUDE_TMPL="$FRAMEWORK_ROOT/templates/CLAUDE.md.tmpl"
README="$FRAMEWORK_ROOT/README.md"
CONFIG_TMPL="$FRAMEWORK_ROOT/templates/pm-workflow.config.yml.tmpl"
BUILDER_PROFILE="$FRAMEWORK_ROOT/scripts/builder-profile.py"

_setup_fake_executor() {
  T=$(mktemp -d)
  BUILD_DIR="$T/build"
  PROMPT_FILE="$T/prompt.txt"
  FAKE_BIN="$T/bin"
  FAKE_LOG="$T/fake.log"
  mkdir -p "$BUILD_DIR" "$FAKE_BIN"
  printf 'Build the module from spec and design.\n' > "$PROMPT_FILE"
  export FAKE_LOG
}

_teardown_fake_executor() {
  rm -rf "$T"
}

_install_fake_command() {
  local name="$1"
  cat > "$FAKE_BIN/$name" <<'EOF'
#!/usr/bin/env bash
{
  echo "cmd=$(basename "$0")"
  echo "cwd=$(pwd)"
  printf 'argv='
  for arg in "$@"; do
    printf '<%s>' "$arg"
  done
  echo
} >> "$FAKE_LOG"
EOF
  chmod +x "$FAKE_BIN/$name"
}

test_adapter_files_are_executable() {
  start_test "adapter inventory: claude-code/codex/cursor/gemini/opencode/manual 都可执行"

  for adapter in claude-code codex cursor-agent gemini opencode manual; do
    if [ ! -x "$ADAPTER_DIR/$adapter.sh" ]; then
      _fail "$adapter.sh 不存在或不可执行"
      return
    fi
  done
  pass_test
}

test_builder_profile_helper_resolves_pm_choice() {
  start_test "builder-profile: PM 视图只露工具名（model, thinking），resolve 输出 snapshot"

  if ! python3 "$BUILDER_PROFILE" list "$CONFIG_TMPL" >/tmp/builder-profile.$$ 2>/tmp/builder-profile.err.$$; then
    _fail "builder-profile list should succeed"
    cat /tmp/builder-profile.err.$$ >&2
    rm -f /tmp/builder-profile.$$ /tmp/builder-profile.err.$$
    return
  fi
  assert_file_contains /tmp/builder-profile.$$ "Codex（gpt-5.4, high）" "Codex display should be compact" || {
    rm -f /tmp/builder-profile.$$ /tmp/builder-profile.err.$$; return;
  }
  assert_file_contains /tmp/builder-profile.$$ "OpenCode（deepseek-v4-flash, max）" "OpenCode display should use display_model" || {
    rm -f /tmp/builder-profile.$$ /tmp/builder-profile.err.$$; return;
  }

  if ! python3 "$BUILDER_PROFILE" resolve "$CONFIG_TMPL" \
    --profile opencode \
    --model gpt-5.4 \
    --thinking max >/tmp/builder-profile.$$ 2>/tmp/builder-profile.err.$$; then
    _fail "builder-profile resolve should succeed"
    cat /tmp/builder-profile.err.$$ >&2
    rm -f /tmp/builder-profile.$$ /tmp/builder-profile.err.$$
    return
  fi
  python3 - /tmp/builder-profile.$$ <<'PY' || {
import json, sys
data = json.load(open(sys.argv[1]))
assert data["builder_profile"] == "opencode"
assert data["executor"] == "opencode"
assert data["display"] == "OpenCode（gpt-5.4, max）"
assert data["builder"]["model"] == "gpt-5.4"
assert data["builder"]["thinking"] == "max"
assert data["builder"]["overrides"]["model"] is True
assert data["builder"]["overrides"]["thinking"] is True
PY
    _fail "resolved builder snapshot mismatch"
    cat /tmp/builder-profile.$$ >&2
    rm -f /tmp/builder-profile.$$ /tmp/builder-profile.err.$$
    return
  }

  rm -f /tmp/builder-profile.$$ /tmp/builder-profile.err.$$
  pass_test
}

test_builder_profile_recommends_target_and_handles_legacy_missing_config() {
  start_test "builder-profile: recommend uses target preference and missing config falls back to native"
  _setup_fake_executor
  _install_fake_command codex
  local config="$T/config.yml"
  cat > "$config" <<'YAML'
builder:
  default_profile: claude-code
  prototype_profile: claude-code
  product_profile: codex
  profiles:
    claude-code:
      label: Claude Code
      executor: claude-code
      model: sonnet
      thinking: standard
    codex:
      label: Codex
      executor: codex
      model: gpt-test
      thinking: high
YAML
  local python_bin
  python_bin=$(command -v python3)
  PATH="$FAKE_BIN:/usr/bin:/bin" "$python_bin" "$BUILDER_PROFILE" recommend "$config" --target product > /tmp/builder-profile.$$
  python3 - /tmp/builder-profile.$$ <<'PY' || {
import json, sys
data = json.load(open(sys.argv[1]))
assert data["builder_profile"] == "codex"
assert data["executor"] == "codex"
assert data["builder"]["model"] == "gpt-test"
PY
    _fail "recommend should select the available product profile"
    rm -f /tmp/builder-profile.$$; _teardown_fake_executor; return
  }
  "$python_bin" "$BUILDER_PROFILE" recommend "$T/missing.yml" --target prototype > /tmp/builder-profile.$$
  python3 - /tmp/builder-profile.$$ <<'PY' || {
import json, sys
data = json.load(open(sys.argv[1]))
assert data["builder_profile"] == "native"
assert data["executor"] == "native"
PY
    _fail "missing legacy config should fall back to native"
    rm -f /tmp/builder-profile.$$; _teardown_fake_executor; return
  }
  rm -f /tmp/builder-profile.$$
  _teardown_fake_executor
  pass_test
}

test_claude_code_adapter_invokes_print_mode() {
  start_test "claude-code adapter: 用 claude -p 非交互执行并传 model/prompt"

  _setup_fake_executor
  _install_fake_command claude
  local status_dir="$T/status"
  BUILD_DIR="$BUILD_DIR" PROMPT_FILE="$PROMPT_FILE" EXECUTOR_MODEL="sonnet" \
    EXECUTOR_STATUS_DIR="$status_dir" \
    PATH="$FAKE_BIN:$PATH" bash "$ADAPTER_DIR/claude-code.sh" >/tmp/exec-adapter.$$ 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "adapter 应返回 0，实际 ${rc}：$(cat /tmp/exec-adapter.$$)"
    rm -f /tmp/exec-adapter.$$
    _teardown_fake_executor
    return
  fi
  rm -f /tmp/exec-adapter.$$

  assert_file_contains "$FAKE_LOG" "cmd=claude" "should invoke claude binary" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "cwd=$BUILD_DIR" "should run in BUILD_DIR" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<-p>" "should use print mode" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--permission-mode><bypassPermissions>" "should run unattended" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--output-format><text>" "should request text output" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--no-session-persistence>" "should avoid persisting adapter sessions" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--model><sonnet>" "should pass EXECUTOR_MODEL" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<Build the module from spec and design.>" "should pass prompt body" || { _teardown_fake_executor; return; }
  assert_file_contains "$status_dir/status.json" '"state": "completed"' "should write completed adapter status" || { _teardown_fake_executor; return; }
  assert_file_contains "$status_dir/exit" "0" "should write adapter exit code" || { _teardown_fake_executor; return; }
  _teardown_fake_executor
  pass_test
}

test_gemini_adapter_invokes_yolo_prompt_mode() {
  start_test "gemini adapter: 用 gemini --yolo --prompt 执行并传 model"

  _setup_fake_executor
  _install_fake_command gemini
  BUILD_DIR="$BUILD_DIR" PROMPT_FILE="$PROMPT_FILE" EXECUTOR_MODEL="gemini-3.1-pro" \
    PATH="$FAKE_BIN:$PATH" bash "$ADAPTER_DIR/gemini.sh" >/tmp/exec-adapter.$$ 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "adapter 应返回 0，实际 ${rc}：$(cat /tmp/exec-adapter.$$)"
    rm -f /tmp/exec-adapter.$$
    _teardown_fake_executor
    return
  fi
  rm -f /tmp/exec-adapter.$$

  assert_file_contains "$FAKE_LOG" "cmd=gemini" "should invoke gemini binary" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "cwd=$BUILD_DIR" "should run in BUILD_DIR" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--yolo>" "should run unattended" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--model><gemini-3.1-pro>" "should pass EXECUTOR_MODEL" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--prompt><Build the module from spec and design.>" "should pass prompt body" || { _teardown_fake_executor; return; }
  _teardown_fake_executor
  pass_test
}

test_opencode_adapter_invokes_run_with_profile_args() {
  start_test "opencode adapter: 用 opencode run --dir 执行并传 model/thinking/auto"

  _setup_fake_executor
  _install_fake_command opencode
  BUILD_DIR="$BUILD_DIR" PROMPT_FILE="$PROMPT_FILE" EXECUTOR_MODEL="opencode-go/deepseek-v4-flash" \
    EXECUTOR_THINKING="max" EXECUTOR_AUTO="true" \
    PATH="$FAKE_BIN:$PATH" bash "$ADAPTER_DIR/opencode.sh" >/tmp/exec-adapter.$$ 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "adapter 应返回 0，实际 ${rc}：$(cat /tmp/exec-adapter.$$)"
    rm -f /tmp/exec-adapter.$$
    _teardown_fake_executor
    return
  fi
  rm -f /tmp/exec-adapter.$$

  assert_file_contains "$FAKE_LOG" "cmd=opencode" "should invoke opencode binary" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<run>" "should use run command" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--dir><$BUILD_DIR>" "should run in BUILD_DIR via --dir" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--model><opencode-go/deepseek-v4-flash>" "should pass EXECUTOR_MODEL" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--variant><max>" "should map thinking to variant" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<--auto>" "should pass auto approval when configured" || { _teardown_fake_executor; return; }
  assert_file_contains "$FAKE_LOG" "<Build the module from spec and design.>" "should pass prompt body" || { _teardown_fake_executor; return; }
  _teardown_fake_executor
  pass_test
}

test_build_skill_recommends_then_confirms_builder_profile() {
  start_test "build skill: 推荐 builder profile 后由 PM 确认"

  assert_file_contains "$BUILD_SKILL" "builder-profile.py\" recommend" "build should recommend builder profiles" || return
  assert_file_contains "$BUILD_SKILL" "Claude Code、Codex、Cursor Agent、Gemini 和 OpenCode" "automatic candidates should include all adapters" || return
  assert_file_contains "$BUILD_SKILL" "调整构建工具" "PM should be able to adjust the recommended builder" || return
  assert_file_contains "$BUILD_SKILL" "只有 PM 选择“按这个方案构建”才继续" "build must wait for PM confirmation" || return
  assert_file_contains "$BUILD_SKILL" "不能静默替换 PM 已确认的工具" "builder fallback must be reconfirmed" || return
  pass_test
}

test_build_skill_confirms_only_environment_and_tool_before_editing() {
  start_test "build skill: 建造依据后台固定，只确认工作环境和构建工具"

  assert_file_contains "$BUILD_SKILL" "后台执行 design 的规格编译、范围提交" "dirty design context should be checkpointed automatically" || return
  assert_file_contains "$BUILD_SKILL" "工作环境：<独立环境 | 继续当前独立环境 | 当前环境>" "confirmation card should expose work environment" || return
  assert_file_contains "$BUILD_SKILL" "构建工具：<工具名（model, thinking）>" "confirmation card should expose builder" || return
  assert_file_contains "$BUILD_SKILL" "卡片中禁止出现项目类型、验收方案" "confirmation card should hide project type and acceptance" || return
  assert_file_contains "$BUILD_SKILL" "合同 v2" "build should write the versioned contract" || return
  assert_file_contains "$BUILD_SKILL" "build-contract.py" "build should call the build contract helper" || return
  assert_file_contains "$AGENTS_TMPL" "PM 只确认这两项" "consumer AGENTS should preserve the two-item confirmation" || return
  assert_file_contains "$AGENTS_TMPL" "卡片不得显示项目类型、验收方案" "consumer AGENTS should hide type and acceptance" || return
  assert_file_contains "$AGENTS_TMPL" ".work-meta.json:build" "consumer AGENTS should require build contract handoff" || return
  assert_file_contains "$CLAUDE_TMPL" ".work-meta.json:build" "consumer CLAUDE should require build contract handoff" || return
  pass_test
}

test_build_skill_keeps_executor_noise_out_of_pm_view() {
  start_test "build skill: 执行器过程不刷 PM 屏，失败保留半成品"

  assert_file_contains "$BUILD_SKILL" "PM 窗口只报阶段摘要" "build should keep executor internals out of PM view" || return
  assert_file_contains "$BUILD_SKILL" "默认保留半成品" "build should preserve partial executor output by default" || return
  assert_file_contains "$BUILD_SKILL" '禁止自动 `git restore .` / `git clean -fd`' "build should forbid destructive auto-clean on executor failure" || return
  assert_file_contains "$BUILD_SKILL" "EXECUTOR_STATUS_DIR" "build should use adapter status protocol" || return
  assert_file_contains "$CLAUDE_TMPL" "失败默认保留半成品" "consumer CLAUDE should preserve failure recovery guidance" || return
  pass_test
}

test_build_skill_handles_fallback_design_baseline() {
  start_test "build skill: DESIGN 兜底骨架自动降级但不伪装视觉通过"

  assert_file_contains "$BUILD_SKILL" "视觉基线段未建" "build should detect fallback DESIGN skeleton" || return
  assert_file_contains "$BUILD_SKILL" '自动调用 gstack `/design-consultation`' "build should use design consultation when available" || return
  assert_file_contains "$BUILD_SKILL" '视觉检查只能记为 `limited`' "build should label visual review as limited when baseline is missing" || return
  assert_file_contains "$BUILD_SKILL" "不能输出“视觉一致性通过”" "build should forbid strong visual pass without baseline" || return
  assert_file_contains "$BUILD_SKILL" "不是让 PM 选择工具" "visual fallback must not expose an engineering menu" || return
  pass_test
}

test_consumer_entry_documents_fallback() {
  start_test "consumer AGENTS: 推荐 profile 不可用时重新确认"

  assert_file_contains "$AGENTS_TMPL" "推荐其它可用 profile 或当前主控" "AGENTS should recommend a fallback" || return
  assert_file_contains "$AGENTS_TMPL" "重新让 PM 确认" "AGENTS should require reconfirmation" || return
  pass_test
}

test_readme_lists_build_executors() {
  start_test "README: 依赖表说明 Claude Code / Gemini / Codex / OpenCode 都可作 build 执行器"

  assert_file_contains "$README" '也可作为 `/pmai-build` 执行器' "README should state Claude Code build role" || return
  assert_file_contains "$README" "Gemini CLI" "README should list Gemini CLI" || return
  assert_file_contains "$README" "OpenCode CLI" "README should list OpenCode CLI" || return
  assert_file_contains "$README" "Claude Code / Gemini / OpenCode / cursor-agent / 手动" "README should list non-Codex build fallback" || return
  pass_test
}

test_config_template_uses_port_placeholder() {
  start_test "config template: dev server command carries explicit port placeholder"

  assert_file_contains "$CONFIG_TMPL" "{port}" "config template should make port injection explicit" || return
  assert_file_contains "$BUILD_SKILL" '不临时猜 `-- --hostname`' "build should avoid guessing framework-specific dev flags" || return
  pass_test
}

test_config_template_has_builder_profiles() {
  start_test "config template: builder profiles include compact model/thinking choices"

  assert_file_contains "$CONFIG_TMPL" "default_profile: claude-code" "config should define default builder profile" || return
  assert_file_contains "$CONFIG_TMPL" "model: gpt-5.4" "config should define Codex model" || return
  assert_file_contains "$CONFIG_TMPL" "thinking: high" "config should define thinking depth" || return
  assert_file_contains "$CONFIG_TMPL" "model: opencode-go/deepseek-v4-flash" "config should set OpenCode DeepSeek model" || return
  assert_file_contains "$CONFIG_TMPL" "display_model: deepseek-v4-flash" "config should keep OpenCode PM display short" || return
  assert_file_contains "$CONFIG_TMPL" "variant: max" "config should map OpenCode thinking to max variant" || return
  assert_file_contains "$CONFIG_TMPL" "executor: opencode" "config should define OpenCode executor" || return
  pass_test
}

test_build_skill_avoids_machine_bound_absolute_path_rules() {
  start_test "build skill: 不要求写死机器绑定的本地绝对路径"

  assert_file_contains "$BUILD_SKILL" "运行时变量" "build should anchor paths through runtime variables" || return
  assert_file_contains "$BUILD_SKILL" '禁止写死 `/Users/...`' "build should forbid machine-bound local paths" || return
  if grep -q '所有路径用绝对路径\|绝对路径.*BUILD_DIR/prototype' "$BUILD_SKILL"; then
    _fail "build skill should not require absolute path writes"
    return
  fi
  pass_test
}

test_adapter_files_are_executable
test_builder_profile_helper_resolves_pm_choice
test_builder_profile_recommends_target_and_handles_legacy_missing_config
test_claude_code_adapter_invokes_print_mode
test_gemini_adapter_invokes_yolo_prompt_mode
test_opencode_adapter_invokes_run_with_profile_args
test_build_skill_recommends_then_confirms_builder_profile
test_build_skill_confirms_only_environment_and_tool_before_editing
test_build_skill_keeps_executor_noise_out_of_pm_view
test_build_skill_handles_fallback_design_baseline
test_consumer_entry_documents_fallback
test_readme_lists_build_executors
test_config_template_uses_port_placeholder
test_config_template_has_builder_profiles
test_build_skill_avoids_machine_bound_absolute_path_rules

report_results "exec-adapters"
