#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

TASK_TRANSITION="$FRAMEWORK_ROOT/scripts/task-transition.py"

_write_deps() {
  local task_file="$1"
  local dep_line="$2"
  local tmp="${task_file}.tmp"
  awk -v dep="$dep_line" '
    /^## 依赖/ && !done {
      print
      print dep
      done=1
      in_dep=1
      next
    }
    in_dep && /^---/ {
      in_dep=0
      print
      next
    }
    in_dep { next }
    { print }
  ' "$task_file" > "$tmp"
  mv "$tmp" "$task_file"
}

_dependency_gate() {
  local task_file="$1"
  local deps dep dep_file dep_status
  deps=$(awk '
    /^## 依赖/{flag=1; next}
    /^## / && flag{flag=0}
    flag{print}
  ' "$task_file" | grep -Eo 'task-[0-9]{3}' | sort -u)

  for dep in $deps; do
    dep_file=$(find "$(dirname "$task_file")" -maxdepth 1 -name "${dep}-*.md" -type f | sort | head -1)
    if [ -z "$dep_file" ]; then
      echo "❌ $(basename "$task_file" .md) 依赖未完成：$dep 未找到。" >&2
      return 1
    fi
    dep_status=$(python3 "$TASK_TRANSITION" "$dep_file" --get-status 2>/dev/null || echo "未知")
    if [ "${dep_status}" != "已完成" ]; then
      echo "❌ $(basename "$task_file" .md) 依赖未完成：${dep} 当前状态为「${dep_status}」。" >&2
      echo "请先 close 依赖 task，再重新运行 /task-confirm <task-file>。" >&2
      return 1
    fi
  done
  return 0
}

_set_status() {
  local task_file="$1"
  local status="$2"
  sed -i.bak "s|^\*\*状态：\*\*.*|\*\*状态：\*\* $status|" "$task_file"
  rm -f "$task_file.bak"
}

_setup_dependency_fixture() {
  fixture_setup
  REQ_DIR=$(fixture_create_req "req-001" "deps" 6)
  DEP_TASK=$(fixture_create_task "$REQ_DIR" "001" "base" "执行中")
  TARGET_TASK=$(fixture_create_task "$REQ_DIR" "002" "dependent" "待确认")
  _write_deps "$TARGET_TASK" "- task-001 (基础能力)"
  export REQ_DIR DEP_TASK TARGET_TASK
}

test_task_confirm_dependency_gate() {
  start_test "task-confirm dependency gate blocks unfinished dependency then passes"
  _setup_dependency_fixture

  if _dependency_gate "$TARGET_TASK" >/tmp/v4_t23.out.$$ 2>/tmp/v4_t23.err.$$; then
    _fail "dependency gate should fail while task-001 is 执行中"
    fixture_teardown
    return
  fi
  if ! grep -F -q "task-001 当前状态为「执行中」" /tmp/v4_t23.err.$$; then
    _fail "dependency gate error missing unfinished dependency status"
    cat /tmp/v4_t23.err.$$ >&2
    fixture_teardown
    return
  fi

  _set_status "$DEP_TASK" "已完成"
  if _dependency_gate "$TARGET_TASK" >/tmp/v4_t23.out.$$ 2>/tmp/v4_t23.err.$$; then
    pass_test
  else
    _fail "dependency gate should pass after dependency is 已完成"
    cat /tmp/v4_t23.err.$$ >&2
  fi

  rm -f /tmp/v4_t23.out.$$ /tmp/v4_t23.err.$$
  fixture_teardown
}

test_task_execute_dependency_gate() {
  start_test "task-execute fallback dependency gate matches task-confirm gate"
  _setup_dependency_fixture

  if _dependency_gate "$TARGET_TASK" >/tmp/v4_t23_exec.out.$$ 2>/tmp/v4_t23_exec.err.$$; then
    _fail "fallback dependency gate should fail while task-001 is 执行中"
    fixture_teardown
    return
  fi
  if ! grep -F -q "请先 close 依赖 task，再重新运行 /task-confirm <task-file>。" /tmp/v4_t23_exec.err.$$; then
    _fail "fallback dependency gate error missing recovery instruction"
    cat /tmp/v4_t23_exec.err.$$ >&2
    fixture_teardown
    return
  fi

  _set_status "$DEP_TASK" "已完成"
  if _dependency_gate "$TARGET_TASK" >/tmp/v4_t23_exec.out.$$ 2>/tmp/v4_t23_exec.err.$$; then
    pass_test
  else
    _fail "fallback dependency gate should pass after dependency is 已完成"
    cat /tmp/v4_t23_exec.err.$$ >&2
  fi

  rm -f /tmp/v4_t23_exec.out.$$ /tmp/v4_t23_exec.err.$$
  fixture_teardown
}

test_task_confirm_dependency_gate
test_task_execute_dependency_gate

report_results "v4_T23_dependency_gate"
