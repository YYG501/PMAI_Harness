#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/active-build-fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$REPO_ROOT/hooks/active-build-guard.cjs"
CLAUDE_HOOK_TEMPLATE="$REPO_ROOT/templates/settings.json.tmpl"
CODEX_HOOK_TEMPLATE="$REPO_ROOT/templates/codex-hooks.json.tmpl"
KIMI_HOOK_MANAGER="$REPO_ROOT/scripts/manage-kimi-hooks.py"
GENERATOR_CLAUDE_HOOKS="$REPO_ROOT/.claude/settings.json"
GENERATOR_CODEX_HOOKS="$REPO_ROOT/.codex/hooks.json"

run_guard() {
  local prompt="$1"
  run_guard_for_cwd "$ACTIVE_BUILD_FIXTURE" "$prompt"
}

run_guard_for_cwd() {
  local cwd="$1"
  local prompt="$2"
  run_guard_with_process_cwd "$cwd" "$cwd" "$prompt"
}

run_guard_with_process_cwd() {
  local process_cwd="$1"
  local payload_cwd="$2"
  local prompt="$3"
  node -e 'process.stdout.write(JSON.stringify({cwd: process.argv[1], prompt: process.argv[2]}))' \
    "$payload_cwd" "$prompt" | (cd "$process_cwd" && node "$GUARD")
}

write_explicit_guard_payload_at_size() {
  local target_bytes="$1"
  node -e '
const targetBytes = Number(process.argv[1]);
const prefix = Buffer.from(JSON.stringify({prompt: "/pmai-status"}));
if (!Number.isSafeInteger(targetBytes) || targetBytes < prefix.length) process.exit(2);
process.stdout.write(prefix);
process.stdout.write(Buffer.alloc(targetBytes - prefix.length, 0x20));
' "$target_bytes"
}

run_guard_with_status_stub() {
  local mode="$1"
  local prompt="$2"
  local tmp
  tmp=$(mktemp -d)
  cat > "$tmp/python3" <<'SH'
#!/usr/bin/env bash
case "${PMAI_TEST_STATUS_MODE:-}" in
  bad-json) printf '{bad json'; exit 0 ;;
  nonzero) echo 'fixture status failure' >&2; exit 7 ;;
  timeout) sleep 1; printf '{"status":"none"}'; exit 0 ;;
  empty) exit 0 ;;
  *) exit 9 ;;
esac
SH
  chmod +x "$tmp/python3"
  (
    export PATH="$tmp:$PATH"
    export PMAI_TEST_STATUS_MODE="$mode"
    export PMAI_ACTIVE_BUILD_CONTEXT_TIMEOUT_MS=30
    run_guard "$prompt"
  )
  rm -rf "$tmp"
}

guard_additional_context() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'
}

test_natural_language_resumes_prototype_build() {
  start_test "active-build guard: 自然语言查看问题续接 prototype build"
  active_build_fixture_setup prototype iterating
  local out
  out=$(run_guard "启动起来看看，现在还有什么没有解决的问题吗" | guard_additional_context)
  if echo "$out" | grep -q "ACTIVE BUILD 续接护栏" \
     && echo "$out" | grep -q "interactive-simulation" \
     && echo "$out" | grep -q "simulate_by_default" \
     && echo "$out" | grep -q "不得转成无范围约束的通用 QA" \
     && echo "$out" | grep -q "规格已有的要求直接作为覆盖要求" \
     && echo "$out" | grep -q "不得重新包装成 PM 待确认问题"; then
    pass_test
  else
    _fail "prototype continuation context missing: $out"
  fi
  active_build_fixture_teardown
}

test_no_active_build_is_silent() {
  start_test "active-build guard: 无 active build 静默"
  active_build_fixture_setup prototype designing
  local out
  out=$(run_guard "启动起来看看")
  if [ -z "$out" ]; then
    pass_test
  else
    _fail "guard should be silent without resumable build: $out"
  fi
  active_build_fixture_teardown
}

test_product_keeps_production_depth() {
  start_test "active-build guard: product 保持 production implementation"
  active_build_fixture_setup product iterating
  local out
  out=$(run_guard "看看还有什么问题" | guard_additional_context)
  if echo "$out" | grep -q "production-implementation" \
     && echo "$out" | grep -q "product 仍按 production-implementation 检查"; then
    pass_test
  else
    _fail "product continuation context missing: $out"
  fi
  active_build_fixture_teardown
}

test_multiple_active_builds_require_module() {
  start_test "active-build guard: 多个 active build 不猜模块"
  active_build_fixture_setup prototype iterating
  active_build_fixture_add_second
  local out
  out=$(run_guard "启动看看" | guard_additional_context)
  if echo "$out" | grep -q '"status": "ambiguous"' \
     && echo "$out" | grep -q "只让 PM 指明本轮要继续看的模块"; then
    pass_test
  else
    _fail "multiple builds should inject ambiguity: $out"
  fi
  active_build_fixture_teardown
}

test_explicit_new_work_does_not_force_active_build() {
  start_test "active-build guard: prompt 开头的 PMAI 命令不强制当前 build"
  active_build_fixture_setup prototype iterating
  local prompt out
  for prompt in \
    "/pmai-design 新建一个无关模块" \
    "/pmai-build-cancel" \
    "/pmai-status" \
    "  /pmai-status" \
    '$pmai-humanize' \
    "/skill:pmai-upgrade" \
    "/skill:pmai-future-command"; do
    out=$(run_guard "$prompt")
    if [ -n "$out" ]; then
      _fail "explicit PMAI entry should bypass active build guard ($prompt): $out"
      active_build_fixture_teardown
      return
    fi
  done
  pass_test
  active_build_fixture_teardown
}

test_similar_paths_are_not_explicit_entries() {
  start_test "active-build guard: 否定、引用、代码和路径不伪装成 PMAI 入口"
  active_build_fixture_setup prototype iterating
  local prompt out
  for prompt in \
    "不要运行 /pmai-status" \
    "请运行/pmai-status，先看当前状态" \
    '帮我执行 $pmai-status 查看现状' \
    '引用“/pmai-status”只是文档示例' \
    '`/pmai-status` 是行内代码' \
    $'```\n/pmai-status\n```' \
    "现在改为 /skill:pmai-upgrade。" \
    "检查 docs/pmai-status.md 的描述" \
    "打开 https://example.com/pmai-status" \
    "检查 prefix/pmai-status 的内容"; do
    out=$(run_guard "$prompt" | guard_additional_context)
    if ! echo "$out" | grep -q "ACTIVE BUILD 续接护栏"; then
      _fail "non-entry text should remain inside active build guard ($prompt): $out"
      active_build_fixture_teardown
      return
    fi
  done
  pass_test
  active_build_fixture_teardown
}

test_explicit_entry_bypasses_repository_lookup() {
  start_test "active-build guard: 显式 PMAI 入口在 Git 定位前直接放行"
  local out
  out=$(run_guard_with_process_cwd "$REPO_ROOT" "/definitely/not/a/repo" "/pmai-status")
  if [ -z "$out" ]; then
    pass_test
  else
    _fail "explicit PMAI entry should not depend on cwd or Git state: $out"
  fi
}

test_context_reader_failures_are_not_silent() {
  start_test "active-build guard: build context 超时/非零/空输出/坏 JSON 全部失败关闭"
  active_build_fixture_setup prototype iterating
  local mode out

  for mode in timeout nonzero empty bad-json; do
    out=$(run_guard_with_status_stub "$mode" "看看还有什么问题")
    if ! echo "$out" | guard_additional_context | grep -q "ACTIVE BUILD 续接护栏不可用"; then
      _fail "status failure should inject fail-closed context ($mode): $out"
      active_build_fixture_teardown
      return
    fi
  done

  pass_test
  active_build_fixture_teardown
}

test_invalid_hook_input_fails_closed() {
  start_test "active-build guard: 非法宿主 stdin 注入失败关闭上下文"
  local out
  out=$(printf '{not-json' | node "$GUARD")
  if echo "$out" | guard_additional_context | grep -q "宿主 hook 输入不是合法 JSON" \
    && echo "$out" | guard_additional_context | grep -q "ACTIVE BUILD 续接护栏不可用"; then
    pass_test
  else
    _fail "invalid host input should fail closed: $out"
  fi
}

test_git_lookup_failure_is_not_silent() {
  start_test "active-build guard: 项目 Git 定位失败时失败关闭"
  local out
  out=$(run_guard_with_process_cwd "$REPO_ROOT" "/definitely/not/a/pmai/repo" "看看还有什么问题")
  if echo "$out" | guard_additional_context | grep -q "Git 仓库定位" \
    && echo "$out" | guard_additional_context | grep -q "ACTIVE BUILD 续接护栏不可用"; then
    pass_test
  else
    _fail "git lookup failure should inject fail-closed context: $out"
  fi
}

test_payload_cwd_cannot_switch_repositories() {
  start_test "active-build guard: payload cwd 不能切换到其它有效 Git 仓"
  active_build_fixture_setup prototype iterating
  local other_repo out
  other_repo=$(mktemp -d)
  git -C "$other_repo" init -q -b main

  out=$(run_guard_with_process_cwd "$ACTIVE_BUILD_FIXTURE" "$other_repo" "看看还有什么问题")
  rm -rf "$other_repo"
  if echo "$out" | guard_additional_context | grep -q "payload cwd 与 hook 进程所在 Git 仓库不一致" \
    && echo "$out" | guard_additional_context | grep -q "ACTIVE BUILD 续接护栏不可用"; then
    pass_test
  else
    _fail "cross-repo payload cwd should fail closed: $out"
  fi
  active_build_fixture_teardown
}

test_stdin_timeout_is_not_silent() {
  start_test "active-build guard: stdin 超时也注入失败关闭上下文"
  local out
  out=$({ printf ''; sleep 0.2; } | PMAI_ACTIVE_BUILD_STDIN_TIMEOUT_MS=30 node "$GUARD")
  if echo "$out" | guard_additional_context | grep -q "宿主 hook 输入在读取期限内未结束" \
    && echo "$out" | guard_additional_context | grep -q "ACTIVE BUILD 续接护栏不可用"; then
    pass_test
  else
    _fail "stdin timeout should inject fail-closed context: $out"
  fi
}

test_stdin_limit_allows_exactly_four_mib() {
  start_test "active-build guard: stdin 恰好 4 MiB 仍可正常处理"
  local out
  out=$(write_explicit_guard_payload_at_size "$((4 * 1024 * 1024))" | (cd "$REPO_ROOT" && node "$GUARD"))
  if [ -z "$out" ]; then
    pass_test
  else
    _fail "exactly 4 MiB should remain within the stdin limit: $out"
  fi
}

test_stdin_limit_fails_closed_before_lookup() {
  start_test "active-build guard: stdin 超过 4 MiB 立即失败关闭且不查询项目"
  local tmp marker out context
  tmp=$(mktemp -d)
  marker="$tmp/lookup-called"
  cat > "$tmp/git" <<'SH'
#!/usr/bin/env bash
printf 'git\n' >> "$PMAI_TEST_LOOKUP_MARKER"
exit 99
SH
  cat > "$tmp/python3" <<'SH'
#!/usr/bin/env bash
printf 'status\n' >> "$PMAI_TEST_LOOKUP_MARKER"
exit 99
SH
  chmod +x "$tmp/git" "$tmp/python3"

  out=$(
    write_explicit_guard_payload_at_size "$((4 * 1024 * 1024 + 1))" |
      (
        export PATH="$tmp:$PATH"
        export PMAI_TEST_LOOKUP_MARKER="$marker"
        cd "$REPO_ROOT" && node "$GUARD"
      )
  )
  context=$(printf '%s' "$out" | guard_additional_context 2>/dev/null || true)
  if echo "$context" | grep -q "宿主 hook 输入超过 4 MiB 上限" \
    && echo "$context" | grep -q "ACTIVE BUILD 续接护栏不可用" \
    && [ ! -e "$marker" ]; then
    pass_test
  else
    _fail "oversized stdin should fail closed before git/status lookup: marker=$(test -e "$marker" && cat "$marker") out=$out"
  fi
  rm -rf "$tmp"
}

test_stdin_error_fails_closed() {
  start_test "active-build guard: stdin 读取错误注入失败关闭上下文"
  local tmp out
  tmp=$(mktemp -d)
  cat > "$tmp/stdin-error.cjs" <<'JS'
process.nextTick(() => process.stdin.emit('error', new Error('fixture stdin failure')));
JS
  out=$(NODE_OPTIONS="--require=$tmp/stdin-error.cjs" node "$GUARD" </dev/null)
  rm -rf "$tmp"
  if echo "$out" | guard_additional_context | grep -q "宿主 hook 输入读取失败" \
    && echo "$out" | guard_additional_context | grep -q "ACTIVE BUILD 续接护栏不可用"; then
    pass_test
  else
    _fail "stdin errors should inject fail-closed context: $out"
  fi
}

test_cumulative_slow_path_finishes_within_host_budget() {
  start_test "active-build guard: 累计慢路径服从共享总预算并在宿主超时前阻断"
  active_build_fixture_setup prototype iterating
  local tmp real_git out elapsed
  tmp=$(mktemp -d)
  real_git=$(command -v git)
  cat > "$tmp/git" <<'SH'
#!/usr/bin/env bash
sleep 0.6
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  cat > "$tmp/python3" <<'SH'
#!/usr/bin/env bash
sleep 2
printf '{"status":"none"}'
SH
  chmod +x "$tmp/git" "$tmp/python3"

  SECONDS=0
  out=$(
    export PATH="$tmp:$PATH"
    export PMAI_TEST_REAL_GIT="$real_git"
    export PMAI_ACTIVE_BUILD_GIT_TIMEOUT_MS=2000
    export PMAI_ACTIVE_BUILD_CONTEXT_TIMEOUT_MS=5000
    export PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS=1200
    run_guard "看看还有什么问题"
  )
  elapsed=$SECONDS
  rm -rf "$tmp"
  if [ "$elapsed" -lt 3 ] \
    && echo "$out" | guard_additional_context | grep -q "ACTIVE BUILD 续接护栏不可用" \
    && echo "$out" | guard_additional_context | grep -q "超时"; then
    pass_test
  else
    _fail "slow path should fail closed before outer hook timeout (elapsed=${elapsed}s): $out"
  fi
  active_build_fixture_teardown
}

test_total_budget_ignores_wall_clock_changes() {
  start_test "active-build guard: Date.now 冻结或回拨不改变共享总预算"
  active_build_fixture_setup prototype iterating
  local tmp real_git out rc
  tmp=$(mktemp -d)
  real_git=$(command -v git)
  cat > "$tmp/date-now.cjs" <<'JS'
const initial = Date.now();
if (process.env.PMAI_TEST_DATE_MODE === 'frozen') {
  Date.now = () => initial;
} else if (process.env.PMAI_TEST_DATE_MODE === 'rollback') {
  let calls = 0;
  Date.now = () => initial - (++calls * 60_000);
}
JS
cat > "$tmp/git" <<'SH'
#!/usr/bin/env bash
sleep 0.5
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  cat > "$tmp/python3" <<'SH'
#!/usr/bin/env bash
sleep 0.4
printf '{"status":"none"}'
SH
  chmod +x "$tmp/git" "$tmp/python3"

  out=$(python3 - "$ACTIVE_BUILD_FIXTURE" "$GUARD" "$tmp" "$real_git" <<'PY' 2>&1
import json
import os
import subprocess
import sys

fixture, guard, fake_bin, real_git = sys.argv[1:]
payload = json.dumps({"cwd": fixture, "prompt": "看看还有什么问题"})

for mode in ("frozen", "rollback"):
    env = os.environ.copy()
    env.update(
        {
            "PATH": fake_bin + os.pathsep + env.get("PATH", ""),
            "NODE_OPTIONS": f"--require={fake_bin}/date-now.cjs",
            "PMAI_TEST_DATE_MODE": mode,
            "PMAI_TEST_REAL_GIT": real_git,
            "PMAI_ACTIVE_BUILD_GIT_TIMEOUT_MS": "1500",
            "PMAI_ACTIVE_BUILD_CONTEXT_TIMEOUT_MS": "5000",
            "PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS": "800",
        }
    )
    result = subprocess.run(
        ["node", guard],
        cwd=fixture,
        env=env,
        input=payload,
        capture_output=True,
        text=True,
        timeout=3,
        check=False,
    )
    assert result.returncode == 0, (mode, result.returncode, result.stdout, result.stderr)
    context = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
    assert "ACTIVE BUILD 续接护栏不可用" in context, (mode, context)
    assert "超时" in context, (mode, context)

print("OK")
PY
  )
  rc=$?
  rm -rf "$tmp"
  if [ "$rc" -eq 0 ] && [ "$out" = "OK" ]; then
    pass_test
  else
    _fail "wall-clock changes escaped the monotonic total budget: rc=$rc out=$out"
  fi
  active_build_fixture_teardown
}

test_host_timeout_budget_has_headroom() {
  start_test "active-build guard: Claude/Codex/Kimi 外层 prompt hook 统一保留 8 秒余量"
  local claude_count codex_count kimi_count generator_claude_count generator_codex_count
  claude_count=$(grep -c '"timeout": 8' "$CLAUDE_HOOK_TEMPLATE")
  codex_count=$(grep -c '"timeout": 8' "$CODEX_HOOK_TEMPLATE")
  kimi_count=$(grep -c '^timeout = 8$' "$KIMI_HOOK_MANAGER")
  generator_claude_count=$(grep -c '"timeout": 8' "$GENERATOR_CLAUDE_HOOKS")
  generator_codex_count=$(grep -c '"timeout": 8' "$GENERATOR_CODEX_HOOKS")
  if [ "$claude_count" = "2" ] && [ "$codex_count" = "2" ] && [ "$kimi_count" = "2" ] \
    && [ "$generator_claude_count" = "2" ] && [ "$generator_codex_count" = "2" ]; then
    pass_test
  else
    _fail "prompt hook timeout budget mismatch: template-claude=$claude_count template-codex=$codex_count kimi=$kimi_count generator-claude=$generator_claude_count generator-codex=$generator_codex_count"
  fi
}

test_natural_language_resumes_prototype_build
test_no_active_build_is_silent
test_product_keeps_production_depth
test_multiple_active_builds_require_module
test_explicit_new_work_does_not_force_active_build
test_similar_paths_are_not_explicit_entries
test_explicit_entry_bypasses_repository_lookup
test_context_reader_failures_are_not_silent
test_invalid_hook_input_fails_closed
test_git_lookup_failure_is_not_silent
test_payload_cwd_cannot_switch_repositories
test_stdin_timeout_is_not_silent
test_stdin_limit_allows_exactly_four_mib
test_stdin_limit_fails_closed_before_lookup
test_stdin_error_fails_closed
test_cumulative_slow_path_finishes_within_host_budget
test_total_budget_ignores_wall_clock_changes
test_host_timeout_budget_has_headroom

report_results "active-build-guard"
