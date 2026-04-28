#!/usr/bin/env bash
# Tests for scripts/run-bg.sh.
# 这是逃生工具的最小验证，不验证 SKILL.md 集成。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_BG="$FRAMEWORK_ROOT/scripts/run-bg.sh"

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
  echo "  Suite: run-bg"
  echo "  Passed: $PASS"
  echo "  Failed: $FAIL"
  echo "═════════════════════════════════════════"
  if [ "$FAIL" -gt 0 ]; then
    echo "Failures:"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
    exit 1
  fi
}

# 等 EXIT_FILE 出现，超时 10 秒就算 fail
wait_for_exit_file() {
  local exit_file="$1"
  local i=0
  while [ ! -f "$exit_file" ] && [ "$i" -lt 100 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -f "$exit_file" ]
}

test_happy_path() {
  start_test "run-bg.sh: cmd 退 0 → EXIT_FILE 内容是 0"
  local sandbox; sandbox=$(mktemp -d "${TMPDIR:-/tmp}/runbg.XXXXXX")
  local log="$sandbox/log"
  bash "$RUN_BG" "$log" bash -c 'sleep 0.2; echo hello' >/dev/null
  if wait_for_exit_file "$log.exit" && [ "$(cat "$log.exit")" = "0" ]; then
    grep -q hello "$log" && pass_test || fail_test "log 缺 'hello'"
  else
    fail_test "EXIT_FILE 未出现或内容不为 0：$(cat "$log.exit" 2>/dev/null)"
  fi
  rm -rf "$sandbox"
}

test_nonzero_exit() {
  start_test "run-bg.sh: cmd 退 7 → EXIT_FILE 内容是 7"
  local sandbox; sandbox=$(mktemp -d "${TMPDIR:-/tmp}/runbg.XXXXXX")
  local log="$sandbox/log"
  bash "$RUN_BG" "$log" bash -c 'sleep 0.2; exit 7' >/dev/null
  if wait_for_exit_file "$log.exit" && [ "$(cat "$log.exit")" = "7" ]; then
    pass_test
  else
    fail_test "EXIT_FILE 内容应为 7，实际：$(cat "$log.exit" 2>/dev/null)"
  fi
  rm -rf "$sandbox"
}

test_atomic_exit_file() {
  start_test "run-bg.sh: EXIT_FILE 出现时内容已完整（mv 原子）"
  local sandbox; sandbox=$(mktemp -d "${TMPDIR:-/tmp}/runbg.XXXXXX")
  local log="$sandbox/log"
  bash "$RUN_BG" "$log" bash -c 'sleep 0.2' >/dev/null
  wait_for_exit_file "$log.exit"
  # 确认 .exit.tmp 已不存在（mv 完成），.exit 内容非空
  if [ ! -f "$log.exit.tmp" ] && [ -s "$log.exit" ]; then
    pass_test
  else
    fail_test ".exit.tmp 残留或 .exit 为空：tmp=$([ -f "$log.exit.tmp" ] && echo yes || echo no), size=$(wc -c < "$log.exit" 2>/dev/null)"
  fi
  rm -rf "$sandbox"
}

test_returns_immediately() {
  start_test "run-bg.sh: 立即返回（不等 cmd 完成）"
  local sandbox; sandbox=$(mktemp -d "${TMPDIR:-/tmp}/runbg.XXXXXX")
  local log="$sandbox/log"
  local start_ts; start_ts=$(date +%s)
  bash "$RUN_BG" "$log" bash -c 'sleep 3' >/dev/null
  local elapsed=$(( $(date +%s) - start_ts ))
  if [ "$elapsed" -le 2 ]; then
    # cmd 还在跑，EXIT_FILE 应不存在
    if [ ! -f "$log.exit" ]; then
      pass_test
    else
      fail_test "立即返回 OK 但 EXIT_FILE 已出现（cmd 应仍在跑）"
    fi
  else
    fail_test "返回耗时 ${elapsed}s，应 ≤2s（fire-and-forget 失效）"
  fi
  # 等 cmd 跑完清场，避免后台 sleep 泄漏
  wait_for_exit_file "$log.exit" || true
  rm -rf "$sandbox"
}

echo "▶ Running test-run-bg.sh"
echo "─────────────────────────────────────────"
test_happy_path
test_nonzero_exit
test_atomic_exit_file
test_returns_immediately
report_results
