#!/usr/bin/env bash
# v2 「文档输出深度指引」硬约束 lint 测试
#
# 验证 scripts/check-engineering-doc-size.py 的行为：
# 1. prototype 档：solution.engineering.md > 300 行 → 报错（exit 1）
# 2. prototype 档：solution.engineering.md ≤ 300 行 → 通过（exit 0）
# 3. prototype 档：task-NNN.engineering.md > 200 行 → 报错（exit 1）
# 4. prototype 档：task-NNN.engineering.md ≤ 200 行 → 通过（exit 0）
# 5. system 档：所有文件不检查（exit 0）
# 6. custom 档：所有文件不检查（exit 0）
# 7. unknown 档：所有文件不检查（exit 0）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/check-engineering-doc-size.py"

# Setup tmpdir + 切换到模拟仓
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# ── Tests ──────────────────────────────────────────────

# run_in_repo <gear> <solution_lines> [task_lines] [expected_exit]
# 在 tmpdir 创建仓 + req 目录，cd 进去跑 lint，返回退出码
run_lint() {
  local gear="$1"
  local solution_lines="$2"
  local task_lines="${3:-0}"
  local repo="$TMPDIR/repo-$gear-$RANDOM"
  mkdir -p "$repo"
  ( cd "$repo" && git init -q )
  if [ "$gear" = "unknown" ]; then
    cat > "$repo/CLAUDE.md" <<'EOF'
# Test repo (unknown gear)
## Some other section
EOF
  else
    cat > "$repo/CLAUDE.md" <<EOF
# Test repo
<!-- auto-detected: $gear — PM 可改 -->
## 工程结构约束（${gear}档（${gear}））
EOF
  fi
  ( cd "$repo" && git add . && git commit -q -m "init" 2>/dev/null )
  local req_dir="$repo/requirements/active/req-test"
  mkdir -p "$req_dir"
  python3 -c "print('# header'); [print(f'line {i}') for i in range($solution_lines - 1)]" > "$req_dir/solution.engineering.md"
  if [ "$task_lines" -gt 0 ]; then
    mkdir -p "$req_dir/tasks"
    python3 -c "print('# header'); [print(f'line {i}') for i in range($task_lines - 1)]" > "$req_dir/tasks/task-001-test.engineering.md"
  fi
  ( cd "$repo" && python3 "$LINT" --req-dir "$req_dir" ) >/tmp/lint.out 2>&1
  echo $?
}

test_prototype_solution_over_limit_fails() {
  start_test "prototype 档 solution.engineering.md 超 300 行 → 报错"
  local rc
  rc=$(run_lint prototype 350)
  if [ "$rc" != "1" ]; then
    _fail "expected exit 1, got $rc"
    cat /tmp/lint.out >&2
    return
  fi
  if ! grep -q "350 行 > 300 行上限" /tmp/lint.out; then
    _fail "stderr 未提及超限行数"
    cat /tmp/lint.out >&2
    return
  fi
  pass_test
}

test_prototype_solution_at_limit_passes() {
  start_test "prototype 档 solution.engineering.md = 300 行 → 通过"
  local rc
  rc=$(run_lint prototype 300)
  if [ "$rc" != "0" ]; then
    _fail "expected exit 0, got $rc"
    cat /tmp/lint.out >&2
    return
  fi
  pass_test
}

test_prototype_task_over_limit_fails() {
  start_test "prototype 档 task-NNN.engineering.md 超 200 行 → 报错"
  local rc
  rc=$(run_lint prototype 100 250)
  if [ "$rc" != "1" ]; then
    _fail "expected exit 1, got $rc"
    cat /tmp/lint.out >&2
    return
  fi
  if ! grep -q "250 行 > 200 行上限" /tmp/lint.out; then
    _fail "stderr 未提及 task 超限"
    cat /tmp/lint.out >&2
    return
  fi
  pass_test
}

test_prototype_task_under_limit_passes() {
  start_test "prototype 档 task-NNN.engineering.md = 200 行 → 通过"
  local rc
  rc=$(run_lint prototype 100 200)
  if [ "$rc" != "0" ]; then
    _fail "expected exit 0, got $rc"
    cat /tmp/lint.out >&2
    return
  fi
  pass_test
}

test_system_gear_skipped() {
  start_test "system 档不检查（exit 0 + 跳过提示）"
  local rc
  rc=$(run_lint system 1500)
  if [ "$rc" != "0" ]; then
    _fail "system 档应 exit 0 即使文件超大，got $rc"
    cat /tmp/lint.out >&2
    return
  fi
  if ! grep -q "档位非 prototype" /tmp/lint.out; then
    _fail "stdout 未给出跳过提示"
    cat /tmp/lint.out >&2
    return
  fi
  pass_test
}

test_custom_gear_skipped() {
  start_test "custom 档不检查（exit 0）"
  local rc
  rc=$(run_lint custom 2000)
  if [ "$rc" != "0" ]; then
    _fail "custom 档应 exit 0, got $rc"
    cat /tmp/lint.out >&2
    return
  fi
  pass_test
}

test_unknown_gear_skipped() {
  start_test "unknown 档不检查（exit 0）"
  local rc
  rc=$(run_lint unknown 5000)
  if [ "$rc" != "0" ]; then
    _fail "unknown 档应 exit 0, got $rc"
    cat /tmp/lint.out >&2
    return
  fi
  pass_test
}

# ── Run ────────────────────────────────────────────────

test_prototype_solution_over_limit_fails
test_prototype_solution_at_limit_passes
test_prototype_task_over_limit_fails
test_prototype_task_under_limit_passes
test_system_gear_skipped
test_custom_gear_skipped
test_unknown_gear_skipped

cd /
report_results "test-engineering-doc-size"
