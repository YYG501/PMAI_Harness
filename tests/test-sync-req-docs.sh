#!/usr/bin/env bash
# sync-req-docs.sh tests
#
# 验证：
# - 项目级文件（CLAUDE.md / DESIGN.md）同步到 task worktree
# - req 目录递归同步（含 task PM 视图 + 工程合同）
# - sync 不写主仓 .git/index.lock（git show 绕 index）
# - 在 req 分支更新文件后 sync 拿到新版本
# - append req_docs_synced 事件 + payload 含 file_count / hash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

SYNC_SCRIPT="$FRAMEWORK_ROOT/scripts/sync-req-docs.sh"
TASK_EVENTS="$FRAMEWORK_ROOT/scripts/task-events.py"

# -----------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------

# Add a tracked file to req branch's worktree and commit
_req_commit_file() {
  local req_dir="$1"
  local relpath="$2"  # relative to req worktree root
  local content="$3"
  # find req worktree root
  local req_worktree_root="$req_dir"
  while [ "$req_worktree_root" != "/" ] && [ ! -d "$req_worktree_root/.git" ] && [ ! -f "$req_worktree_root/.git" ]; do
    req_worktree_root=$(dirname "$req_worktree_root")
  done
  mkdir -p "$req_worktree_root/$(dirname "$relpath")"
  printf '%s' "$content" > "$req_worktree_root/$relpath"
  (
    cd "$req_worktree_root"
    git add -A
    git commit -q -m "add $relpath" 2>/dev/null || true
  )
}

# -----------------------------------------------------------------
# Tests
# -----------------------------------------------------------------

test_sync_creates_project_level_files() {
  start_test "sync pulls CLAUDE.md from req branch into task worktree"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  # Update CLAUDE.md on req branch with distinguishable content
  _req_commit_file "$req_dir" "CLAUDE.md" "# REQ-SPECIFIC CLAUDE"
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  bash "$SYNC_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>&1 || {
    _fail "sync-req-docs.sh exited non-zero"
    fixture_teardown
    return
  }

  if [ ! -f "$task_wt/CLAUDE.md" ]; then
    _fail "CLAUDE.md missing after sync"
    fixture_teardown
    return
  fi
  if ! grep -q "REQ-SPECIFIC" "$task_wt/CLAUDE.md"; then
    _fail "CLAUDE.md content not from req branch (still main version)"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_sync_recurses_req_directory() {
  start_test "sync recurses requirements/active/<req-id>/"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # Add a new file to req branch's req dir AFTER task worktree forked
  _req_commit_file "$req_dir" "requirements/active/req-001-test/solution.md" "# Solution"

  bash "$SYNC_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>&1 || {
    _fail "sync-req-docs.sh exited non-zero"
    fixture_teardown
    return
  }

  if [ ! -f "$task_wt/requirements/active/req-001-test/solution.md" ]; then
    _fail "solution.md missing after sync"
    fixture_teardown
    return
  fi
  if [ ! -f "$task_wt/requirements/active/req-001-test/brief.md" ]; then
    _fail "brief.md missing after sync"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_sync_does_not_write_main_index_lock() {
  start_test "sync does not write main repo .git/index.lock"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  bash "$SYNC_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>&1 || {
    _fail "sync-req-docs.sh exited non-zero"
    fixture_teardown
    return
  }

  # 主仓 .git/index.lock 不应该被 sync 创建（git show 绕 index 的核心保证）
  if [ -f "$FIXTURE_DIR/.git/index.lock" ]; then
    _fail "主仓 .git/index.lock 被创建——sync 写了 index（违反 git show 设计）"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_sync_overwrites_local_modifications() {
  start_test "sync overwrites task worktree's local copy with req branch version"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  _req_commit_file "$req_dir" "CLAUDE.md" "# req version v1"
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # task worktree 本地把 CLAUDE.md 改了
  echo "# task local edit" > "$task_wt/CLAUDE.md"

  # req 分支也升级到 v2
  _req_commit_file "$req_dir" "CLAUDE.md" "# req version v2"

  bash "$SYNC_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>&1 || {
    _fail "sync-req-docs.sh exited non-zero"
    fixture_teardown
    return
  }

  if ! grep -q "req version v2" "$task_wt/CLAUDE.md"; then
    _fail "sync 未覆盖本地修改（应拉到 req v2）"
    cat "$task_wt/CLAUDE.md" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_sync_appends_audit_event() {
  start_test "sync appends req_docs_synced event with file_count + hash"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  bash "$SYNC_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>&1 || {
    _fail "sync-req-docs.sh exited non-zero"
    fixture_teardown
    return
  }

  local task_stem
  task_stem=$(basename "$task" .md)
  local events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  if [ ! -f "$events_file" ]; then
    _fail "事件文件不存在: $events_file"
    fixture_teardown
    return
  fi
  if ! grep -q '"req_docs_synced"' "$events_file"; then
    _fail "req_docs_synced 事件未 append"
    cat "$events_file" >&2
    fixture_teardown
    return
  fi
  if ! grep -q '"file_count"' "$events_file"; then
    _fail "事件 payload 缺 file_count 字段"
    cat "$events_file" >&2
    fixture_teardown
    return
  fi
  if ! grep -q '"hash"' "$events_file"; then
    _fail "事件 payload 缺 hash 字段"
    cat "$events_file" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_sync_idempotent_with_same_inputs() {
  start_test "sync is idempotent: same inputs → same hash across calls"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  bash "$SYNC_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>&1
  bash "$SYNC_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>&1

  local task_stem
  task_stem=$(basename "$task" .md)
  local events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  local hashes
  hashes=$(grep -oE '"hash":\s*"[a-f0-9]+"' "$events_file" | sort -u | wc -l | tr -d ' ')
  if [ "$hashes" != "1" ]; then
    _fail "expected 1 unique hash, got: $hashes"
    cat "$events_file" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_sync_creates_project_level_files
test_sync_recurses_req_directory
test_sync_does_not_write_main_index_lock
test_sync_overwrites_local_modifications
test_sync_appends_audit_event
test_sync_idempotent_with_same_inputs

report_results "sync-req-docs"
