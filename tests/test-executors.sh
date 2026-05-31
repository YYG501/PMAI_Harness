#!/usr/bin/env bash
# Tests for executor replaceability (batches 4-9 scripts).
#
# Covers:
#   - resolve-executor.py (inheritance, validation, enum)
#   - build-execution-prompt.py (6-section contract)
#   - task-transition.py --fail-execution / --cancel-manual / --snooze-manual
#   - manual.sh adapter (pending file schema)
#   - skill-preamble manual aggregation
#   - status-view manual section
#
# codex.sh / cursor-agent.sh live tests are gated behind SKIP_LIVE_TESTS=0.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKIP_LIVE_TESTS="${SKIP_LIVE_TESTS:-1}"

PASS=0
FAIL=0
FAILURES=()

pass_test() { PASS=$((PASS + 1)); echo "  ✅ $CURRENT_TEST"; }
fail_test() {
  FAIL=$((FAIL + 1))
  FAILURES+=("$CURRENT_TEST: $*")
  echo "  ❌ $CURRENT_TEST: $*"
}
start_test() { CURRENT_TEST="$1"; echo "  RUN  $1"; }

report_results() {
  echo ""
  echo "═════════════════════════════════════════"
  echo "  Suite: $1"
  echo "  Passed: $PASS"
  echo "  Failed: $FAIL"
  echo "═════════════════════════════════════════"
  if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failures:"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
    exit 1
  fi
}

make_sandbox() {
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/pmexec.XXXXXX")
  mkdir -p "$SANDBOX/.claude"
  ln -s "$FRAMEWORK_ROOT/scripts" "$SANDBOX/.claude/scripts"
  mkdir -p "$SANDBOX/.runs/events"
  mkdir -p "$SANDBOX/requirements/active/req-001-test/tasks"
  (
    cd "$SANDBOX"
    git init -b main -q
    git config user.email "test@test.local"
    git config user.name "Test"
    echo ".runs/" > .gitignore
    git add .gitignore
    git commit -q -m "init"
  )
}

teardown_sandbox() {
  rm -rf "$SANDBOX"
}

write_task_file() {
  local path="$1" executor="$2" model="$3"
  cat > "$path" <<EOF
# Task 001: smoke

**状态：** 待执行
**审查工具：** /review
**executor：** $executor
**executor_model：** $model
**分支：** task-001-smoke

## 启动前必读（按顺序，读完再执行）

1. docs/PRODUCT.md

## 任务描述
最小测试 task。

## 执行范围
- 新建：hello.txt

## 验收标准
- [ ] hello.txt 存在
EOF
}

write_settings_json() {
  local dir="$1"
  cat > "$dir/.claude/settings.json" <<'EOF'
{
  "executor": {
    "default": "claude-code",
    "models": {
      "codex": "gpt-5.4",
      "cursor-agent": "gemini-3.1-pro"
    },
    "claude_code_model_allowlist": ["opus", "sonnet", "haiku"]
  }
}
EOF
}

# ======================================================================
# resolve-executor.py tests
# ======================================================================

_has_field() {
  # Helper: check JSON output contains "key": "value" (with optional whitespace)
  local out="$1" key="$2" val="$3"
  echo "$out" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get('$key')=='$val' else 1)"
}

test_resolver_task_field() {
  start_test "resolver: task field wins"
  make_sandbox
  write_settings_json "$SANDBOX"
  write_task_file "$SANDBOX/task.md" "codex" ""
  out=$(cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task.md)
  if _has_field "$out" executor codex && _has_field "$out" source_executor task; then
    pass_test
  else
    fail_test "expected codex/task, got: $out"
  fi
  teardown_sandbox
}

test_resolver_settings_default() {
  start_test "resolver: settings.default wins when task empty"
  make_sandbox
  cat > "$SANDBOX/.claude/settings.json" <<'EOF'
{ "executor": { "default": "codex", "models": {"codex": "gpt-5.4"} } }
EOF
  write_task_file "$SANDBOX/task.md" "" ""
  out=$(cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task.md)
  if _has_field "$out" executor codex && _has_field "$out" source_executor settings; then
    pass_test
  else
    fail_test "expected codex/settings, got: $out"
  fi
  teardown_sandbox
}

test_resolver_default_claude_code() {
  start_test "resolver: fallback to claude-code when nothing set"
  make_sandbox
  # No settings
  write_task_file "$SANDBOX/task.md" "" ""
  out=$(cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task.md)
  if _has_field "$out" executor claude-code && _has_field "$out" source_executor default; then
    pass_test
  else
    fail_test "expected claude-code/default, got: $out"
  fi
  teardown_sandbox
}

test_resolver_gemini_task() {
  start_test "resolver: gemini executor from task field"
  make_sandbox
  write_settings_json "$SANDBOX"
  write_task_file "$SANDBOX/task.md" "gemini" ""
  out=$(cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task.md)
  if _has_field "$out" executor gemini && _has_field "$out" source_executor task; then
    pass_test
  else
    fail_test "expected gemini/task, got: $out"
  fi
  teardown_sandbox
}

test_resolver_invalid_executor() {
  start_test "resolver: invalid executor → exit 1 with human message"
  make_sandbox
  write_settings_json "$SANDBOX"
  write_task_file "$SANDBOX/task.md" "cursor_agent" ""  # wrong spelling
  if cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task.md >/dev/null 2>/tmp/err.$$; then
    fail_test "should have failed"
  else
    if grep -q "无效 executor" /tmp/err.$$ && grep -q "合法值" /tmp/err.$$; then
      pass_test
    else
      fail_test "stderr missing human message: $(cat /tmp/err.$$)"
    fi
  fi
  rm -f /tmp/err.$$
  teardown_sandbox
}

test_resolver_claude_code_model_valid() {
  start_test "resolver: claude-code + opus passes"
  make_sandbox
  write_settings_json "$SANDBOX"
  write_task_file "$SANDBOX/task.md" "claude-code" "opus"
  out=$(cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task.md)
  if _has_field "$out" model opus; then
    pass_test
  else
    fail_test "expected model opus, got: $out"
  fi
  teardown_sandbox
}

test_resolver_claude_code_model_invalid() {
  start_test "resolver: claude-code + gpt-5.4 → rejected with suggestion"
  make_sandbox
  write_settings_json "$SANDBOX"
  write_task_file "$SANDBOX/task.md" "claude-code" "gpt-5.4"
  if cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task.md >/dev/null 2>/tmp/err.$$; then
    fail_test "should have failed"
  else
    if grep -q "只支持" /tmp/err.$$ && grep -qE "codex|cursor-agent" /tmp/err.$$; then
      pass_test
    else
      fail_test "stderr missing human message: $(cat /tmp/err.$$)"
    fi
  fi
  rm -f /tmp/err.$$
  teardown_sandbox
}

# ======================================================================
# build-execution-prompt.py tests
# ======================================================================

test_prompt_envelope_legacy_singlefile() {
  start_test "prompt: 旧单文件 task → 信封含 PM 视图路径 + 退化指令 + git ban"
  make_sandbox
  write_task_file "$SANDBOX/task.md" "codex" ""
  out=$(cd "$SANDBOX" && python3 .claude/scripts/build-execution-prompt.py task.md)
  missing=""
  grep -q "执行上下文" <<< "$out" || missing="$missing 上下文"
  grep -q "执行指令" <<< "$out" || missing="$missing 指令"
  grep -q "PM 视图（业务真相）" <<< "$out" || missing="$missing PM路径"
  grep -q "工程合同：（不存在" <<< "$out" || missing="$missing 退化提示"
  # 只匹配 basename：mktemp 路径在 macOS 上 /var → /private/var symlink，全路径 grep 不稳
  grep -qE "/task\.md\b" <<< "$out" || missing="$missing 文件路径"
  grep -q "禁止.*git.*commit" <<< "$out" || missing="$missing git-ban"
  if [ -z "$missing" ]; then pass_test; else fail_test "missing in envelope:$missing"; fi
  teardown_sandbox
}

test_prompt_envelope_two_files() {
  start_test "prompt: 新两文件 task → 信封同时引用 PM 视图 + 工程合同 + 工程合同指令"
  make_sandbox
  write_task_file "$SANDBOX/task-001-foo.md" "codex" ""
  cat > "$SANDBOX/task-001-foo.engineering.md" <<'EOF'
# Task 001 Engineering: foo

## 1. 元信息扩展（agent 用）

**executor：** codex
**executor_model：**
**审查工具：** /review

## 3. 启动前必读

1. docs/PRODUCT.md
EOF
  out=$(cd "$SANDBOX" && python3 .claude/scripts/build-execution-prompt.py task-001-foo.md)
  missing=""
  grep -q "PM 视图（业务真相）" <<< "$out" || missing="$missing PM路径"
  grep -q "工程合同（实现真相）" <<< "$out" || missing="$missing eng路径"
  # 只匹配 basename：mktemp 路径在 macOS 上 /var → /private/var symlink，全路径 grep 不稳
  grep -qE "/task-001-foo\.md\b" <<< "$out" || missing="$missing PM文件名"
  grep -qE "/task-001-foo\.engineering\.md\b" <<< "$out" || missing="$missing eng文件名"
  grep -q "工程合同 §3.*启动前必读" <<< "$out" || missing="$missing eng指令"
  grep -q "task: task-001" <<< "$out" || missing="$missing taskID"
  # 退化提示在新格式下不应出现
  if grep -q "工程合同：（不存在" <<< "$out"; then missing="$missing 误判旧格式"; fi
  if [ -z "$missing" ]; then pass_test; else fail_test "missing/wrong in envelope:$missing"; fi
  teardown_sandbox
}

test_prompt_envelope_no_section_splice() {
  start_test "prompt: 信封不再 splice section 内容（hello.txt 不应出现在信封里）"
  make_sandbox
  write_task_file "$SANDBOX/task.md" "codex" ""
  out=$(cd "$SANDBOX" && python3 .claude/scripts/build-execution-prompt.py task.md)
  # write_task_file 在 task.md 里写了 "hello.txt"（执行范围 + 验收标准）
  # 信封改造后不再 inject 这些 section，所以 hello.txt 不应该出现
  if grep -q "hello.txt" <<< "$out"; then
    fail_test "信封仍在 splice section 内容（hello.txt 出现在输出）"
  else
    pass_test
  fi
  teardown_sandbox
}

test_resolver_reads_engineering_contract() {
  start_test "resolver: 优先读 .engineering.md §1 的 executor 字段"
  make_sandbox
  write_settings_json "$SANDBOX"
  # PM 视图字段写 cursor-agent，工程合同写 codex —— 应取工程合同的值
  write_task_file "$SANDBOX/task-001-foo.md" "cursor-agent" ""
  cat > "$SANDBOX/task-001-foo.engineering.md" <<'EOF'
# Task 001 Engineering

## 1. 元信息扩展

**executor：** codex
**executor_model：**
EOF
  out=$(cd "$SANDBOX" && python3 .claude/scripts/resolve-executor.py task-001-foo.md)
  if _has_field "$out" executor codex; then
    pass_test
  else
    fail_test "expected codex (from eng contract), got: $out"
  fi
  teardown_sandbox
}

# ======================================================================
# classify-failure.sh tests
# ======================================================================

test_classify_exit_10() {
  start_test "classify: exit 10 → sandbox_denied"
  out=$(bash "$FRAMEWORK_ROOT/scripts/classify-failure.sh" 10)
  [ "$out" = "sandbox_denied" ] && pass_test || fail_test "got $out"
}

test_classify_exit_99_log_scan() {
  start_test "classify: exit 99 + log with 'rate limit' → network"
  log=$(mktemp)
  echo "ERROR: rate limit exceeded" > "$log"
  out=$(bash "$FRAMEWORK_ROOT/scripts/classify-failure.sh" 99 "$log")
  [ "$out" = "network" ] && pass_test || fail_test "got $out"
  rm -f "$log"
}

test_classify_exit_99_unknown() {
  start_test "classify: exit 99 + empty log → unknown"
  log=$(mktemp); : > "$log"
  out=$(bash "$FRAMEWORK_ROOT/scripts/classify-failure.sh" 99 "$log")
  [ "$out" = "unknown" ] && pass_test || fail_test "got $out"
  rm -f "$log"
}

test_classify_cli_arg_echo_not_sandbox() {
  start_test "classify: log 仅含 '--sandbox workspace-write' CLI 回显 → unknown（不假阳性）"
  log=$(mktemp)
  cat > "$log" <<'EOF'
codex.sh: CLAUDE_PLUGIN_ROOT not set; falling back to plain 'codex exec --sandbox workspace-write'
codex exec --sandbox workspace-write --model gpt-test "test prompt"
some unrelated stack trace here
EOF
  out=$(bash "$FRAMEWORK_ROOT/scripts/classify-failure.sh" 99 "$log")
  [ "$out" = "unknown" ] && pass_test || fail_test "expected unknown, got $out"
  rm -f "$log"
}

test_classify_real_sandbox_denied() {
  start_test "classify: log 含真实 'sandbox denied' 错误 → sandbox_denied"
  log=$(mktemp)
  echo "Error: sandbox denied write to /Users/foo/bar.txt" > "$log"
  out=$(bash "$FRAMEWORK_ROOT/scripts/classify-failure.sh" 99 "$log")
  [ "$out" = "sandbox_denied" ] && pass_test || fail_test "expected sandbox_denied, got $out"
  rm -f "$log"
}

test_classify_permission_denied_is_sandbox() {
  start_test "classify: log 含 'permission denied' → sandbox_denied"
  log=$(mktemp)
  echo "open(/Users/foo/bar.txt): permission denied" > "$log"
  out=$(bash "$FRAMEWORK_ROOT/scripts/classify-failure.sh" 99 "$log")
  [ "$out" = "sandbox_denied" ] && pass_test || fail_test "expected sandbox_denied, got $out"
  rm -f "$log"
}

# ======================================================================
# task-transition.py new flags
# ======================================================================

test_fail_execution_requires_reason() {
  start_test "task-transition --fail-execution without --reason rejected"
  make_sandbox
  write_task_file "$SANDBOX/task.md" "codex" ""
  # Move to 执行中
  cd "$SANDBOX" && python3 .claude/scripts/task-transition.py task.md --to 执行中 --bound-to-execution-event started --executor claude-code >/dev/null 2>&1
  if python3 .claude/scripts/task-transition.py task.md --fail-execution 2>/tmp/err.$$; then
    fail_test "should reject without --reason"
  else
    grep -q "requires --reason" /tmp/err.$$ && pass_test || fail_test "wrong error: $(cat /tmp/err.$$)"
  fi
  rm -f /tmp/err.$$
  teardown_sandbox
}

test_fail_execution_happy() {
  start_test "task-transition --fail-execution --reason → 待执行 + event"
  make_sandbox
  write_task_file "$SANDBOX/task.md" "codex" ""
  cd "$SANDBOX" && python3 .claude/scripts/task-transition.py task.md --to 执行中 --bound-to-execution-event started --executor claude-code >/dev/null 2>&1
  python3 .claude/scripts/task-transition.py task.md --fail-execution --reason "sandbox_denied" >/dev/null 2>&1
  status=$(grep '^\*\*状态：\*\*' task.md | sed 's/.*：\*\* //')
  [ "$status" = "待执行" ] && pass_test || fail_test "status is $status, expected 待执行"
  teardown_sandbox
}

test_plain_to_pending_from_executing_rejected() {
  start_test "task-transition --to 待执行 from 执行中 → rejected (use --fail-execution)"
  make_sandbox
  write_task_file "$SANDBOX/task.md" "codex" ""
  cd "$SANDBOX" && python3 .claude/scripts/task-transition.py task.md --to 执行中 --bound-to-execution-event started --executor claude-code >/dev/null 2>&1
  if python3 .claude/scripts/task-transition.py task.md --to 待执行 2>/tmp/err.$$; then
    fail_test "should reject plain --to 待执行 from 执行中"
  else
    grep -q "非法状态转换" /tmp/err.$$ && pass_test || fail_test "wrong error: $(cat /tmp/err.$$)"
  fi
  rm -f /tmp/err.$$
  teardown_sandbox
}

test_cancel_manual_happy() {
  start_test "task-transition --cancel-manual: remove marker + back to 待执行"
  make_sandbox
  # Use proper task filename so pending_manual_path() extracts task-001
  tf="$SANDBOX/task-001-smoke.md"
  write_task_file "$tf" "manual" ""
  cd "$SANDBOX"
  python3 .claude/scripts/task-transition.py "$tf" --to 执行中 --bound-to-execution-event started --executor claude-code >/dev/null 2>&1
  cat > "$SANDBOX/.runs/.pending-manual-task-001.json" <<EOF
{"task_id":"task-001","started_at":"2026-04-20T10:00:00+00:00","baseline_sha":"abc","snoozed_until":null}
EOF
  python3 .claude/scripts/task-transition.py "$tf" --cancel-manual >/tmp/out.$$ 2>/tmp/err.$$
  status=$(grep '^\*\*状态：\*\*' "$tf" | sed 's/.*：\*\* //')
  if [ "$status" = "待执行" ] && [ ! -f "$SANDBOX/.runs/.pending-manual-task-001.json" ]; then
    pass_test
  else
    fail_test "status=$status, marker=$(test -f "$SANDBOX/.runs/.pending-manual-task-001.json" && echo yes || echo no), err=$(cat /tmp/err.$$)"
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  teardown_sandbox
}

test_snooze_manual_updates_marker() {
  start_test "task-transition --snooze-manual --days 3: marker gains snoozed_until"
  make_sandbox
  tf="$SANDBOX/task-001-smoke.md"
  write_task_file "$tf" "manual" ""
  cat > "$SANDBOX/.runs/.pending-manual-task-001.json" <<EOF
{"task_id":"task-001","started_at":"2026-04-20T10:00:00+00:00","baseline_sha":"abc","snoozed_until":null}
EOF
  cd "$SANDBOX"
  python3 .claude/scripts/task-transition.py "$tf" --snooze-manual --days 3 >/dev/null 2>&1
  snoozed=$(python3 -c "import json; d=json.load(open('$SANDBOX/.runs/.pending-manual-task-001.json')); print(d.get('snoozed_until'))")
  if [ -n "$snoozed" ] && [ "$snoozed" != "None" ] && [ "$snoozed" != "null" ]; then
    pass_test
  else
    fail_test "snoozed_until not set, got: '$snoozed'"
  fi
  teardown_sandbox
}

# ======================================================================
# manual.sh adapter
# ======================================================================

test_manual_adapter_writes_pending() {
  start_test "manual.sh: writes pending file to \$MAIN_REPO_ROOT/.runs with schema"
  make_sandbox
  task="$SANDBOX/requirements/active/req-001-test/tasks/task-001-test.md"
  write_task_file "$task" "manual" ""
  # Create a task worktree stub (use main repo itself for simplicity)
  PROMPT_FILE=$(mktemp)
  echo "test" > "$PROMPT_FILE"

  MAIN_REPO_ROOT="$SANDBOX" \
  TASK_FILE="$task" \
  TASK_WORKTREE="$SANDBOX" \
  PROMPT_FILE="$PROMPT_FILE" \
  EXECUTOR_MODEL="" \
    bash "$FRAMEWORK_ROOT/scripts/exec-adapters/manual.sh" >/dev/null 2>&1

  pf="$SANDBOX/.runs/.pending-manual-task-001.json"
  if [ -f "$pf" ]; then
    if python3 -c "import json,sys; d=json.load(open('$pf')); sys.exit(0 if all(k in d for k in ['task_id','task_file','baseline_sha','started_at','snoozed_until']) else 1)"; then
      pass_test
    else
      fail_test "pending file missing required keys: $(cat "$pf")"
    fi
  else
    fail_test "pending file not written"
  fi
  rm -f "$PROMPT_FILE"
  teardown_sandbox
}

# ======================================================================
# status-view manual section
# ======================================================================

test_status_view_shows_manual() {
  start_test "status-view: renders Manual 等待中 section when pending exists"
  make_sandbox
  mkdir -p "$SANDBOX/.runs"
  cat > "$SANDBOX/.runs/.pending-manual-task-003.json" <<EOF
{"task_id":"task-003","task_file":"req/tasks/task-003-demo.md","started_at":"2026-04-20T10:00:00+00:00","baseline_sha":"abc","snoozed_until":null}
EOF
  out=$(cd "$SANDBOX" && python3 .claude/scripts/status-view.py 2>&1)
  if echo "$out" | grep -q "Manual 等待中" && echo "$out" | grep -q "task-003" && echo "$out" | grep -q "cancel-manual"; then
    pass_test
  else
    fail_test "expected Manual section with task-003 + cancel-manual hint, got: $out"
  fi
  teardown_sandbox
}

test_status_view_respects_snooze() {
  start_test "status-view: hides snoozed manual task"
  make_sandbox
  mkdir -p "$SANDBOX/.runs"
  future=$(python3 -c "from datetime import datetime,timezone,timedelta; print((datetime.now(timezone.utc)+timedelta(days=2)).isoformat())")
  cat > "$SANDBOX/.runs/.pending-manual-task-003.json" <<EOF
{"task_id":"task-003","task_file":"x.md","started_at":"2026-04-20T10:00:00+00:00","baseline_sha":"abc","snoozed_until":"$future"}
EOF
  out=$(cd "$SANDBOX" && python3 .claude/scripts/status-view.py 2>&1)
  if echo "$out" | grep -q "Manual 等待中"; then
    fail_test "should hide snoozed task, output: $out"
  else
    pass_test
  fi
  teardown_sandbox
}

# ======================================================================
# skill-preamble manual aggregation
# ======================================================================

test_preamble_aggregates_manual() {
  start_test "skill-preamble: aggregates 2 manual tasks into one line"
  make_sandbox
  mkdir -p "$SANDBOX/.runs"
  cat > "$SANDBOX/.runs/.pending-manual-task-001.json" <<EOF
{"task_id":"task-001","started_at":"2026-04-22T10:00:00+00:00","snoozed_until":null}
EOF
  cat > "$SANDBOX/.runs/.pending-manual-task-002.json" <<EOF
{"task_id":"task-002","started_at":"2026-04-22T10:00:00+00:00","snoozed_until":null}
EOF
  out=$(cd "$SANDBOX" && bash "$FRAMEWORK_ROOT/scripts/skill-preamble.sh" 2>&1)
  if echo "$out" | grep -q "有 2 个 manual task"; then
    pass_test
  else
    fail_test "expected aggregate line, got: $out"
  fi
  teardown_sandbox
}

# ======================================================================
# Adapter shim tests (no real codex / cursor-agent binary needed)
# Regression for: bash 3.2 + set -u + 空 EXECUTOR_MODEL → "${MODEL_ARGS[@]}"
# unbound variable → adapter 在调到 CLI 前就 exit 1
# ======================================================================

# Build a fake CLI shim under $SANDBOX/shim/<name> that records args and exits 0.
# Caller pre-pends $SANDBOX/shim to PATH.
_make_cli_shim() {
  local name="$1"
  mkdir -p "$SANDBOX/shim"
  cat > "$SANDBOX/shim/$name" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$SANDBOX/.shim-args"
exit 0
EOF
  chmod +x "$SANDBOX/shim/$name"
}

# Run an adapter with $EXECUTOR_MODEL set or empty.
# Leaves the shim's received args (one per line) at $SANDBOX/.shim-args if
# adapter actually reached the CLI call. Adapter exit code is intentionally
# ignored — these tests cover only "did adapter reach the CLI?", not e2e.
# Sub-shell wraps the call so the parent shell's cwd stays valid across tests.
_run_adapter_with_shim() {
  local adapter="$1" cli_name="$2" model_value="$3"
  local task="$SANDBOX/requirements/active/req-001-test/tasks/task-001-shim.md"
  write_task_file "$task" "${adapter%%.sh}" "$model_value"
  (cd "$SANDBOX" && python3 .claude/scripts/task-transition.py "$task" --to 执行中 --bound-to-execution-event started --executor claude-code >/dev/null 2>&1)

  local prompt_file="$SANDBOX/.prompt"
  echo "test prompt" > "$prompt_file"

  _make_cli_shim "$cli_name"

  (
    cd "$SANDBOX"
    # Force codex.sh's plain-`codex` fallback path — that's where the original
    # "${MODEL_ARGS[@]}"-on-empty-array bug lived.
    unset CLAUDE_PLUGIN_ROOT
    PATH="$SANDBOX/shim:$PATH" \
    MAIN_REPO_ROOT="$SANDBOX" \
    TASK_FILE="$task" \
    TASK_WORKTREE="$SANDBOX" \
    PROMPT_FILE="$prompt_file" \
    EXECUTOR_MODEL="$model_value" \
      bash "$FRAMEWORK_ROOT/scripts/exec-adapters/$adapter" \
      >"$SANDBOX/.adapter-stdout" 2>"$SANDBOX/.adapter-stderr" || true
  )
}

# When the original bug fires, adapter dies in `set -u` at the array expansion
# *before* reaching the CLI shim, so .shim-args never gets written. That is the
# regression signal we test for.
_assert_shim_invoked_without_model_flag() {
  if ! [ -f "$SANDBOX/.shim-args" ]; then
    fail_test "shim never invoked → adapter died before CLI. stderr=$(cat "$SANDBOX/.adapter-stderr")"
    return
  fi
  if grep -q '^--model$' "$SANDBOX/.shim-args"; then
    fail_test "shim received --model unexpectedly: $(tr '\n' ' ' < "$SANDBOX/.shim-args")"
  else
    pass_test
  fi
}

_assert_shim_received_model() {
  local expected="$1"
  if ! [ -f "$SANDBOX/.shim-args" ]; then
    fail_test "shim never invoked. stderr=$(cat "$SANDBOX/.adapter-stderr")"
    return
  fi
  if grep -q '^--model$' "$SANDBOX/.shim-args" && grep -q "^${expected}$" "$SANDBOX/.shim-args"; then
    pass_test
  else
    fail_test "shim args missing --model $expected: $(tr '\n' ' ' < "$SANDBOX/.shim-args")"
  fi
}

test_codex_adapter_empty_model_reaches_cli() {
  start_test "codex.sh: EXECUTOR_MODEL='' 时 adapter 仍能调到 codex CLI（不 unbound 死掉）"
  make_sandbox
  write_settings_json "$SANDBOX"
  _run_adapter_with_shim codex.sh codex ""
  _assert_shim_invoked_without_model_flag
  teardown_sandbox
}

test_codex_adapter_filled_model_passes_through() {
  start_test "codex.sh: EXECUTOR_MODEL='gpt-test' 透传 --model gpt-test 到 codex CLI"
  make_sandbox
  write_settings_json "$SANDBOX"
  _run_adapter_with_shim codex.sh codex "gpt-test"
  _assert_shim_received_model "gpt-test"
  teardown_sandbox
}

test_cursor_agent_adapter_empty_model_reaches_cli() {
  start_test "cursor-agent.sh: EXECUTOR_MODEL='' 时 adapter 仍能调到 cursor-agent CLI"
  make_sandbox
  write_settings_json "$SANDBOX"
  _run_adapter_with_shim cursor-agent.sh cursor-agent ""
  _assert_shim_invoked_without_model_flag
  teardown_sandbox
}

test_cursor_agent_adapter_filled_model_passes_through() {
  start_test "cursor-agent.sh: EXECUTOR_MODEL='gemini-test' 透传 --model gemini-test"
  make_sandbox
  write_settings_json "$SANDBOX"
  _run_adapter_with_shim cursor-agent.sh cursor-agent "gemini-test"
  _assert_shim_received_model "gemini-test"
  teardown_sandbox
}

# gemini.sh adapter 走与 cursor-agent.sh 逐字同构的路径（source _gate.sh →
# adapter_precheck → CLI → adapter_postcheck）。这里给它同款 shim 用例，覆盖空数组
# 展开 ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"}（codex/cursor 同类 bug 的发源处）。
# 本套已进 run-all（_gate.sh 的 scripts 目录解析改走 BASH_SOURCE 后 4 个 adapter 用例转绿）。

test_gemini_adapter_empty_model_reaches_cli() {
  start_test "gemini.sh: EXECUTOR_MODEL='' 时 adapter 仍能调到 gemini CLI（空数组不 unbound 死掉）"
  make_sandbox
  write_settings_json "$SANDBOX"
  _run_adapter_with_shim gemini.sh gemini ""
  _assert_shim_invoked_without_model_flag
  teardown_sandbox
}

test_gemini_adapter_filled_model_passes_through() {
  start_test "gemini.sh: EXECUTOR_MODEL='gemini-2.5-pro' 透传 --model gemini-2.5-pro"
  make_sandbox
  write_settings_json "$SANDBOX"
  _run_adapter_with_shim gemini.sh gemini "gemini-2.5-pro"
  _assert_shim_received_model "gemini-2.5-pro"
  teardown_sandbox
}

# ======================================================================
# Live adapter tests (SKIP_LIVE_TESTS gated)
# ======================================================================

test_codex_adapter_live() {
  start_test "codex.sh: live execution writes hello.txt"
  if [ "$SKIP_LIVE_TESTS" = "1" ]; then
    echo "  ⏭  skipped (SKIP_LIVE_TESTS=1)"
    return
  fi
  # ... (live codex invocation omitted in MVP)
  echo "  ⏭  not yet implemented"
}

# ======================================================================
# Run
# ======================================================================

echo "▶ Running test-executors.sh"
echo "─────────────────────────────────────────"

test_resolver_task_field
test_resolver_settings_default
test_resolver_default_claude_code
test_resolver_gemini_task
test_resolver_invalid_executor
test_resolver_claude_code_model_valid
test_resolver_claude_code_model_invalid

test_prompt_envelope_legacy_singlefile
test_prompt_envelope_two_files
test_prompt_envelope_no_section_splice
test_resolver_reads_engineering_contract

test_classify_exit_10
test_classify_exit_99_log_scan
test_classify_exit_99_unknown
test_classify_cli_arg_echo_not_sandbox
test_classify_real_sandbox_denied
test_classify_permission_denied_is_sandbox

test_fail_execution_requires_reason
test_fail_execution_happy
test_plain_to_pending_from_executing_rejected
test_cancel_manual_happy
test_snooze_manual_updates_marker

test_manual_adapter_writes_pending
test_status_view_shows_manual
test_status_view_respects_snooze
test_preamble_aggregates_manual

test_codex_adapter_empty_model_reaches_cli
test_codex_adapter_filled_model_passes_through
test_cursor_agent_adapter_empty_model_reaches_cli
test_cursor_agent_adapter_filled_model_passes_through
test_gemini_adapter_empty_model_reaches_cli
test_gemini_adapter_filled_model_passes_through

test_codex_adapter_live

report_results "executors"
