#!/usr/bin/env bash
# check-req-doc-drift.sh + apply-req-doc.sh tests（4.5f）
#
# 替代 4.5e 决议「sync 静默覆盖」方案。新机制：
#   check-req-doc-drift.sh → 列 req 分支与 task worktree 之间的 hash 差异
#   apply-req-doc.sh → PM 决定采用 req 版本时单文件 git show 写入
#
# 验证：
# - drift 检测无变更时 drift_count=0（fork 直后即此态）
# - drift 检测发现 req 分支变更（项目级 + req 目录）
# - drift 跳过 task own 文件（PM 视图 + 工程合同）
# - drift 报兄弟 task 的变更
# - drift stdout 是 JSON
# - apply 单文件写入 worktree + append req_doc_applied 事件
# - apply 事件 payload 含 path / before_hash / after_hash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

DRIFT_SCRIPT="$FRAMEWORK_ROOT/scripts/check-req-doc-drift.sh"
APPLY_SCRIPT="$FRAMEWORK_ROOT/scripts/apply-req-doc.sh"

# -----------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------

# 在 req 分支 worktree 修改并提交一个文件
_req_commit_file() {
  local req_dir="$1"
  local relpath="$2"
  local content="$3"
  local req_worktree_root="$req_dir"
  while [ "$req_worktree_root" != "/" ] && [ ! -d "$req_worktree_root/.git" ] && [ ! -f "$req_worktree_root/.git" ]; do
    req_worktree_root=$(dirname "$req_worktree_root")
  done
  mkdir -p "$req_worktree_root/$(dirname "$relpath")"
  printf '%s' "$content" > "$req_worktree_root/$relpath"
  (
    cd "$req_worktree_root"
    git add -A
    git commit -q -m "modify $relpath" 2>/dev/null || true
  )
}

# 跑 drift 脚本捕获 stdout JSON
_run_drift() {
  local task_wt="$1"
  local req_branch="$2"
  local task_file="$3"
  bash "$DRIFT_SCRIPT" "$task_wt" "$req_branch" "$task_file" 2>/tmp/drift.err
}

# -----------------------------------------------------------------
# Tests
# -----------------------------------------------------------------

test_no_drift_when_fork_fresh() {
  start_test "fresh fork: drift_count=0（worktree == req 分支）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  out=$(_run_drift "$task_wt" "req-001-test" "$task")
  count=$(echo "$out" | python3 -c 'import json, sys; print(json.load(sys.stdin)["drift_count"])')
  if [ "$count" != "0" ]; then
    _fail "fresh fork 应 drift_count=0，得 $count"
    echo "stdout: $out" >&2
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_drift_detects_project_level_change() {
  start_test "drift 检出 CLAUDE.md 在 req 分支被改"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # task worktree fork 后，PM 才在 req 分支改 CLAUDE.md
  _req_commit_file "$req_dir" "CLAUDE.md" "# CLAUDE updated by PM"

  out=$(_run_drift "$task_wt" "req-001-test" "$task")
  if ! echo "$out" | grep -q '"CLAUDE.md"'; then
    _fail "drift 列表应含 CLAUDE.md，得 $out"
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_drift_detects_req_dir_change() {
  start_test "drift 检出 brief.md 在 req 分支被改"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  _req_commit_file "$req_dir" "requirements/active/req-001-test/brief.md" "# Brief updated"

  out=$(_run_drift "$task_wt" "req-001-test" "$task")
  if ! echo "$out" | grep -q '"requirements/active/req-001-test/brief.md"'; then
    _fail "drift 列表应含 brief.md，得 $out"
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_drift_skips_task_own_pm_view() {
  start_test "drift 跳过 task own PM 视图（即便 req 分支被改）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # PM 在 req 分支改 task own PM 视图（罕见但可能 — 不该让本 task drift）
  _req_commit_file "$req_dir" "requirements/active/req-001-test/tasks/task-001-demo.md" "# Hijacked"

  out=$(_run_drift "$task_wt" "req-001-test" "$task")
  if echo "$out" | grep -q '"requirements/active/req-001-test/tasks/task-001-demo.md"'; then
    _fail "drift 不应含 task own PM 视图，得 $out"
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_drift_skips_task_own_engineering() {
  start_test "drift 跳过 task own 工程合同"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  _req_commit_file "$req_dir" "requirements/active/req-001-test/tasks/task-001-demo.engineering.md" "# Hijacked eng"

  out=$(_run_drift "$task_wt" "req-001-test" "$task")
  if echo "$out" | grep -q 'task-001-demo.engineering.md'; then
    _fail "drift 不应含 task own 工程合同，得 $out"
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_drift_includes_sibling_task() {
  start_test "drift 报兄弟 task 文件的变更"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # task-002 close 后 doc-update 改了 task-002 PM 视图（兄弟 task 改动）
  _req_commit_file "$req_dir" "requirements/active/req-001-test/tasks/task-002-other.md" "# Sibling"

  out=$(_run_drift "$task_wt" "req-001-test" "$task")
  if ! echo "$out" | grep -q 'task-002-other.md'; then
    _fail "drift 应报兄弟 task 的变更，得 $out"
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_drift_stdout_is_json() {
  start_test "drift stdout 是合法 JSON（drift_count + files 数组）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  _req_commit_file "$req_dir" "CLAUDE.md" "# v2"

  out=$(_run_drift "$task_wt" "req-001-test" "$task")
  if ! echo "$out" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert "drift_count" in data, "missing drift_count"
assert "files" in data, "missing files"
assert isinstance(data["files"], list), "files not list"
if data["drift_count"] > 0:
    assert "path" in data["files"][0], "file entry missing path"
    assert "worktree_hash" in data["files"][0], "file entry missing worktree_hash"
    assert "req_hash" in data["files"][0], "file entry missing req_hash"
'; then
    _fail "stdout 不是预期 JSON 格式：$out"
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_apply_writes_file_and_event() {
  start_test "apply 单文件写入 worktree + append req_doc_applied 事件"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # PM 在 req 分支更新 brief
  _req_commit_file "$req_dir" "requirements/active/req-001-test/brief.md" "# Brief APPLIED"

  bash "$APPLY_SCRIPT" "$task_wt" "req-001-test" \
    "requirements/active/req-001-test/brief.md" "$task" >/dev/null 2>/tmp/apply.err || {
    _fail "apply-req-doc.sh exit 非 0"
    cat /tmp/apply.err >&2
    fixture_teardown
    return
  }

  if ! grep -q "Brief APPLIED" "$task_wt/requirements/active/req-001-test/brief.md"; then
    _fail "apply 未把 req 分支版本写入 worktree"
    cat "$task_wt/requirements/active/req-001-test/brief.md" >&2
    fixture_teardown
    return
  fi

  local task_stem
  task_stem=$(basename "$task" .md)
  local events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  if ! grep -q '"req_doc_applied"' "$events_file"; then
    _fail "未 append req_doc_applied 事件"
    cat "$events_file" >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_apply_event_payload_complete() {
  start_test "apply 事件 payload 含 path / before_hash / after_hash"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  _req_commit_file "$req_dir" "CLAUDE.md" "# new content"

  bash "$APPLY_SCRIPT" "$task_wt" "req-001-test" "CLAUDE.md" "$task" >/dev/null 2>/tmp/apply.err

  local task_stem
  task_stem=$(basename "$task" .md)
  local events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  for field in '"path"' '"before_hash"' '"after_hash"'; do
    if ! grep -q "$field" "$events_file"; then
      _fail "事件 payload 缺 $field"
      cat "$events_file" >&2
      fixture_teardown
      return
    fi
  done
  pass_test
  fixture_teardown
}

test_drift_stderr_clean_when_no_drift() {
  start_test "stderr 在无 drift 时输出干净 ✓ 行（不报 integer expression error）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  bash "$DRIFT_SCRIPT" "$task_wt" "req-001-test" "$task" >/dev/null 2>/tmp/drift.err
  if grep -q "integer expression expected" /tmp/drift.err; then
    _fail "stderr 含 'integer expression expected' bash 错误"
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  if ! grep -q "无 drift" /tmp/drift.err; then
    _fail "stderr 应有「无 drift」摘要，实际 stderr："
    cat /tmp/drift.err >&2
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_drift_does_not_modify_worktree() {
  start_test "drift 检测纯只读：不写 worktree 任何文件"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  _req_commit_file "$req_dir" "CLAUDE.md" "# REQ-ONLY"

  # task worktree 的 CLAUDE.md 仍是 fork 时的内容
  before=$(cat "$task_wt/CLAUDE.md")

  _run_drift "$task_wt" "req-001-test" "$task" >/dev/null

  after=$(cat "$task_wt/CLAUDE.md")
  if [ "$before" != "$after" ]; then
    _fail "drift 检测改动了 worktree 上的 CLAUDE.md（应只读）"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_no_drift_when_fork_fresh
test_drift_detects_project_level_change
test_drift_detects_req_dir_change
test_drift_skips_task_own_pm_view
test_drift_skips_task_own_engineering
test_drift_includes_sibling_task
test_drift_stdout_is_json
test_apply_writes_file_and_event
test_apply_event_payload_complete
test_drift_stderr_clean_when_no_drift
test_drift_does_not_modify_worktree

report_results "check-req-doc-drift"
