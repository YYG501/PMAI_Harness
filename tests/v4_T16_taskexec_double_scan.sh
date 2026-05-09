#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

_make_task() {
  local path="$1"
  local status="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
# $(basename "$path" .md)

**状态：** $status
EOF
}

_scan_pending_start_tasks() {
  {
    find requirements/active -path "*/tasks/task-*.md" -type f 2>/dev/null
    find .worktrees -path "*/requirements/active/*/tasks/task-*.md" -type f 2>/dev/null
  } | sort -u | while IFS= read -r task_file; do
    [ -n "$task_file" ] || continue
    status=$(grep -m1 '^\*\*状态：\*\*' "$task_file" | sed 's/.*\*\*状态：\*\* *//')
    stem=$(basename "$task_file" .md)
    if [ "$status" = "待执行" ] && [ -d ".worktrees/$stem" ]; then
      echo "$task_file"
    fi
  done
}

test_scan_main_repo_active_req() {
  start_test "task-execute no-arg scan sees main repo active req"
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/pmaidoublescan.XXXXXX")
  mkdir -p "$sandbox/.worktrees/task-001-main"
  _make_task "$sandbox/requirements/active/req-001/tasks/task-001-main.md" "待执行"

  out=$(cd "$sandbox" && _scan_pending_start_tasks)
  if [ "$out" = "requirements/active/req-001/tasks/task-001-main.md" ]; then
    pass_test
  else
    _fail "expected main active task, got: $out"
  fi
  rm -rf "$sandbox"
}

test_scan_req_worktree_active_req() {
  start_test "task-execute no-arg scan sees req worktree active req"
  sandbox=$(mktemp -d "${TMPDIR:-/tmp}/pmaidoublescan.XXXXXX")
  mkdir -p "$sandbox/.worktrees/task-002-wt"
  _make_task "$sandbox/.worktrees/req-001-feature/requirements/active/req-001/tasks/task-002-wt.md" "待执行"

  out=$(cd "$sandbox" && _scan_pending_start_tasks)
  if [ "$out" = ".worktrees/req-001-feature/requirements/active/req-001/tasks/task-002-wt.md" ]; then
    pass_test
  else
    _fail "expected req worktree active task, got: $out"
  fi
  rm -rf "$sandbox"
}

test_scan_main_repo_active_req
test_scan_req_worktree_active_req

report_results "v4_T16_taskexec_double_scan"
