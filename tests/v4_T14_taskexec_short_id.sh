#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

_make_sandbox() {
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/pmaishortid.XXXXXX")
  mkdir -p "$SANDBOX/requirements/active/req-001/tasks" "$SANDBOX/.worktrees/task-005-foo"
  cat > "$SANDBOX/requirements/active/req-001/tasks/task-005-foo.md" <<'EOF'
# Task 005: foo

**状态：** 待执行
EOF
  export SANDBOX
}

_cleanup_sandbox() {
  rm -rf "${SANDBOX:-}"
  unset SANDBOX
}

_resolve_short_id() {
  local arg="$1"
  local matches count
  matches=$(find requirements/active -name "${arg}-*.md" -type f 2>/dev/null | sort)
  count=$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$count" = "1" ]; then
    echo "🎯 短 ID 匹配: $matches"
    return 0
  fi
  echo "❌ 短 ID $arg 匹配到 $count 个 task，请传完整 task 文件路径。" >&2
  [ -n "$matches" ] && echo "$matches" >&2
  return 1
}

test_short_id_unique_match() {
  start_test "task-execute short ID unique match succeeds"
  _make_sandbox

  out=$(cd "$SANDBOX" && _resolve_short_id "task-005" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -F -q "🎯 短 ID 匹配: requirements/active/req-001/tasks/task-005-foo.md"; then
    pass_test
  else
    _fail "expected unique match success. rc=$rc output=$out"
  fi

  _cleanup_sandbox
}

test_short_id_zero_match() {
  start_test "task-execute short ID zero match fails"
  _make_sandbox

  out=$(cd "$SANDBOX" && _resolve_short_id "task-006" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -F -q "匹配到 0 个 task"; then
    pass_test
  else
    _fail "expected zero match failure. rc=$rc output=$out"
  fi

  _cleanup_sandbox
}

test_short_id_multi_match() {
  start_test "task-execute short ID multiple matches fail"
  _make_sandbox
  cat > "$SANDBOX/requirements/active/req-001/tasks/task-005-bar.md" <<'EOF'
# Task 005: bar

**状态：** 待执行
EOF

  out=$(cd "$SANDBOX" && _resolve_short_id "task-005" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -F -q "匹配到 2 个 task"; then
    pass_test
  else
    _fail "expected multiple match failure. rc=$rc output=$out"
  fi

  _cleanup_sandbox
}

test_short_id_unique_match
test_short_id_zero_match
test_short_id_multi_match

report_results "v4_T14_taskexec_short_id"
