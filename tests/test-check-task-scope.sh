#!/usr/bin/env bash
# check-task-scope.py 越界校验测试
#
# 重点覆盖阶段 4 新增的 implicit_deny：sync 白名单内的路径（项目级
# DESIGN.md / CLAUDE.md，以及 req 目录内别人的 task 文件）即使被显式
# 列入 allowlist 也必须 deny——它们是 sync-req-docs.sh 的同步源。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

CHECKER="$(cd "$SCRIPT_DIR/.." && pwd)/scripts/check-task-scope.py"

# 创建一个含给定 allowlist 的 task PM 视图文件（v1 内联格式即可，parser 兼容）
_make_task_with_scope() {
  local task_file="$1"
  shift
  cat > "$task_file" <<'HEADER'
# Task 001: Test
**状态：** 执行中
**分支：** task-001-test
**worktree：**

## 执行范围
HEADER
  for entry in "$@"; do
    echo "- $entry" >> "$task_file"
  done
  echo "" >> "$task_file"
  echo "## 验收标准" >> "$task_file"
  echo "- [ ] 完成" >> "$task_file"
}

# Run checker with paths via stdin, capture exit code
_run_checker() {
  local task_file="$1"
  shift
  printf "%s\n" "$@" | python3 "$CHECKER" "$task_file" 2>/tmp/scope.err
  echo $?
}

test_implicit_deny_design_md() {
  start_test "implicit deny: DESIGN.md 不能 commit（即使 allowlist 命中）"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  _make_task_with_scope "$task" "新建：DESIGN.md, src/foo.ts"

  rc=$(_run_checker "$task" "DESIGN.md" "src/foo.ts")
  if [ "$rc" != "1" ]; then
    _fail "DESIGN.md 应被 implicit deny 拒，得 exit=$rc"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "项目级文档" /tmp/scope.err; then
    _fail "stderr 应说明 implicit deny 原因"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_implicit_deny_claude_md() {
  start_test "implicit deny: CLAUDE.md 不能 commit"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  _make_task_with_scope "$task" "修改：CLAUDE.md"

  rc=$(_run_checker "$task" "CLAUDE.md")
  if [ "$rc" != "1" ]; then
    _fail "CLAUDE.md 应被 implicit deny 拒，得 exit=$rc"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_implicit_deny_other_req_task_doc() {
  start_test "implicit deny: 同 req 别人的 task 文件不能 commit"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  # 即便 allowlist 显式列了别的 task，也要 deny
  _make_task_with_scope "$task" "修改：requirements/active/req-001/tasks/task-002-other.md"

  rc=$(_run_checker "$task" "requirements/active/req-001/tasks/task-002-other.md")
  if [ "$rc" != "1" ]; then
    _fail "别的 task 文件应被 implicit deny，得 exit=$rc"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "req 目录" /tmp/scope.err; then
    _fail "stderr 应说明 implicit deny 原因"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_implicit_deny_brief_md() {
  start_test "implicit deny: 同 req 的 brief.md 不能 commit"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  _make_task_with_scope "$task" "修改：requirements/active/req-001/brief.md"

  rc=$(_run_checker "$task" "requirements/active/req-001/brief.md")
  if [ "$rc" != "1" ]; then
    _fail "brief.md 应被 implicit deny，得 exit=$rc"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_own_task_pm_view_allowed() {
  start_test "allowed: 自己的 task PM 视图可 commit"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  _make_task_with_scope "$task" "修改：requirements/active/req-001/tasks/task-001-test.md"

  rc=$(_run_checker "$task" "requirements/active/req-001/tasks/task-001-test.md")
  if [ "$rc" != "0" ]; then
    _fail "自己的 PM 视图应被允许，得 exit=$rc"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_own_engineering_contract_allowed() {
  start_test "allowed: 自己的 task 工程合同可 commit"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  _make_task_with_scope "$task" "修改：requirements/active/req-001/tasks/task-001-test.engineering.md"

  rc=$(_run_checker "$task" "requirements/active/req-001/tasks/task-001-test.engineering.md")
  if [ "$rc" != "0" ]; then
    _fail "自己的工程合同应被允许，得 exit=$rc"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_normal_code_path_allowlist_works() {
  start_test "allowed: 普通代码 allowlist 正常通过"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  _make_task_with_scope "$task" "新建：src/auth/login.ts"

  rc=$(_run_checker "$task" "src/auth/login.ts")
  if [ "$rc" != "0" ]; then
    _fail "src/auth/login.ts 应通过，得 exit=$rc"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_implicit_deny_priority_over_empty_allowlist() {
  start_test "implicit deny 优先于 allowlist empty 检查（P2 修复）"
  local tmp=$(mktemp -d)
  local task="$tmp/task-001-test.md"
  # task 不声明 allowlist + 改了 DESIGN.md（双重场景）
  cat > "$task" <<'HEADER'
# Task 001: Test
**状态：** 执行中
**分支：** task-001-test

## 执行范围

## 验收标准
- [ ] 完成
HEADER

  rc=$(_run_checker "$task" "DESIGN.md")
  if [ "$rc" != "1" ]; then
    _fail "应 exit 1，得 exit=$rc"
    rm -rf "$tmp"
    return
  fi
  # 错误信息应是 implicit deny 而不是 allowlist 未声明
  if ! grep -q "项目级文档" /tmp/scope.err; then
    _fail "错误信息应为 implicit deny（项目级文档），但被 allowlist empty 检查抢先"
    cat /tmp/scope.err >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_implicit_deny_design_md
test_implicit_deny_claude_md
test_implicit_deny_other_req_task_doc
test_implicit_deny_brief_md
test_own_task_pm_view_allowed
test_own_engineering_contract_allowed
test_normal_code_path_allowlist_works
test_implicit_deny_priority_over_empty_allowlist

report_results "check-task-scope"
