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
  start_test "adapter inventory: claude-code/codex/cursor/gemini/manual 都可执行"

  for adapter in claude-code codex cursor-agent gemini manual; do
    if [ ! -x "$ADAPTER_DIR/$adapter.sh" ]; then
      _fail "$adapter.sh 不存在或不可执行"
      return
    fi
  done
  pass_test
}

test_claude_code_adapter_invokes_print_mode() {
  start_test "claude-code adapter: 用 claude -p 非交互执行并传 model/prompt"

  _setup_fake_executor
  _install_fake_command claude
  BUILD_DIR="$BUILD_DIR" PROMPT_FILE="$PROMPT_FILE" EXECUTOR_MODEL="sonnet" \
    PATH="$FAKE_BIN:$PATH" bash "$ADAPTER_DIR/claude-code.sh" >/tmp/exec-adapter.$$ 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "adapter 应返回 0，实际 $rc：$(cat /tmp/exec-adapter.$$)"
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
    _fail "adapter 应返回 0，实际 $rc：$(cat /tmp/exec-adapter.$$)"
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

test_build_skill_exposes_claude_and_gemini() {
  start_test "build skill: PM 选项露出 Claude Code + Gemini，并说明 CLI 兜底"

  assert_file_contains "$BUILD_SKILL" "claude-code,codex,cursor-agent,gemini,manual" "executor list should include claude-code and gemini" || return
  assert_file_contains "$BUILD_SKILL" '`label`: `Gemini`' "PM options should expose Gemini" || return
  assert_file_contains "$BUILD_SKILL" "EXECUTOR=gemini" "Gemini option should map to executor" || return
  assert_file_contains "$BUILD_SKILL" "exec-adapters/claude-code.sh" "Claude Code should have CLI adapter fallback" || return
  assert_file_contains "$BUILD_SKILL" '留在 Codex 窗口里选择 `Claude Code`' "Codex-host Claude Code path should be documented" || return
  pass_test
}

test_build_skill_requires_pm_gates_before_editing() {
  start_test "build skill: 未提交上下文不能跳过 PM 执行方式/执行器选择"

  assert_file_contains "$BUILD_SKILL" "两道构建选择是硬门" "build should name the two PM choices as a hard gate" || return
  assert_file_contains "$BUILD_SKILL" "未提交的规格 / mock / 文档不是跳过 PM 选择的理由" "dirty design context should not bypass PM choices" || return
  assert_file_contains "$BUILD_SKILL" '禁止修改 `prototype/`、`Sources/` 或任何业务代码' "build should forbid code edits before both PM choices" || return
  assert_file_contains "$BUILD_SKILL" "禁止默认选“直接在主线上建”" "build should not default to direct-main mode" || return
  assert_file_contains "$BUILD_SKILL" "禁止把当前主控 AI 当默认执行器直接改代码" "build should not default to the current host as executor" || return
  assert_file_contains "$BUILD_SKILL" "build 合同是 build-close 的唯一收尾依据" "build should record a contract for build-close" || return
  assert_file_contains "$BUILD_SKILL" "build-contract.py" "build should call the build contract helper" || return
  assert_file_contains "$AGENTS_TMPL" "必须先完成两道 PM 门" "consumer AGENTS should preserve the build PM gate" || return
  assert_file_contains "$AGENTS_TMPL" "隔离环境拿不到未跟踪文件" "consumer AGENTS should block dirty-context direct-main rationalization" || return
  assert_file_contains "$AGENTS_TMPL" ".work-meta.json:build" "consumer AGENTS should require build contract handoff" || return
  assert_file_contains "$CLAUDE_TMPL" ".work-meta.json:build" "consumer CLAUDE should require build contract handoff" || return
  pass_test
}

test_consumer_entry_documents_fallback() {
  start_test "consumer AGENTS: Codex runtime 下 Claude subagent 不可用时先走 adapter"

  assert_file_contains "$AGENTS_TMPL" "exec-adapters/claude-code.sh" "AGENTS fallback should mention Claude Code adapter" || return
  assert_file_contains "$AGENTS_TMPL" "Codex / Gemini / 手动" "AGENTS fallback should list alternative paths" || return
  pass_test
}

test_readme_lists_build_executors() {
  start_test "README: 依赖表说明 Claude Code / Gemini / Codex 都可作 build 执行器"

  assert_file_contains "$README" '也可作为 `/pmai-build` 执行器' "README should state Claude Code build role" || return
  assert_file_contains "$README" "Gemini CLI" "README should list Gemini CLI" || return
  assert_file_contains "$README" "Claude Code / Gemini / cursor-agent / 手动" "README should list non-Codex build fallback" || return
  pass_test
}

test_adapter_files_are_executable
test_claude_code_adapter_invokes_print_mode
test_gemini_adapter_invokes_yolo_prompt_mode
test_build_skill_exposes_claude_and_gemini
test_build_skill_requires_pm_gates_before_editing
test_consumer_entry_documents_fallback
test_readme_lists_build_executors

report_results "exec-adapters"
