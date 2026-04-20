#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_TASK="$FRAMEWORK_ROOT/scripts/close-task.sh"

# Helper: mark a task as 已完成
_mark_task_done() {
  local task_file="$1"
  sed -i.bak 's|^\*\*状态：\*\*.*|\*\*状态：\*\* 已完成|' "$task_file"
  rm -f "$task_file.bak"
}

# Helper: clear 文档偏差 section (replace "无偏差" default)
_set_doc_diff_empty() {
  local task_file="$1"
  # "无偏差" placeholder kept -- script treats as OK
  :
}

# Helper: inject real 文档偏差 content (should trigger rejection)
_inject_doc_diff() {
  local task_file="$1"
  # Replace '无偏差' line with real content
  sed -i.bak 's|^无偏差$|docs/modules/foo.md 写的是 A，实际实现 B|' "$task_file"
  rm -f "$task_file.bak"
}

# =================================================
# I-CT1: task status must be 已完成
# =================================================
test_reject_if_status_not_done() {
  start_test "I-CT1 reject when task status is not 已完成"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  fixture_create_task_worktree "$task" "req-001-test" >/dev/null

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should have rejected when status is 执行中"
  else
    if grep -q "已完成" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing expected message about 已完成"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT1: status 待验收 also rejected
# =================================================
test_reject_if_status_pending_review() {
  start_test "I-CT1 reject when task status is 待验收"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "002" "review" "待验收" "/qa")
  fixture_create_task_worktree "$task" "req-001-test" >/dev/null

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should have rejected when status is 待验收"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT2: task branch does not exist → reject
# =================================================
test_reject_if_task_branch_missing() {
  start_test "I-CT2 reject when task branch does not exist"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "003" "nobranch" "待确认" "/qa")
  # Do NOT create worktree/branch for this task
  _mark_task_done "$task"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when task branch missing"
  else
    if grep -q "分支" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing branch-missing message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT2: req worktree does not exist → reject
# =================================================
test_reject_if_req_worktree_missing() {
  start_test "I-CT2 reject when req worktree is missing"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "004" "noreqwt" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  _mark_task_done "$task"

  # task 文件在 task worktree 里也有副本（经 req 分支 checkout 而来）
  # 同步 mark_done 到 task worktree 的副本，并 commit 到 task 分支
  task_in_wt="$task_wt/requirements/active/req-001-test/tasks/task-004-noreqwt.md"
  sed -i.bak 's|^\*\*状态：\*\*.*|\*\*状态：\*\* 已完成|' "$task_in_wt"
  rm -f "$task_in_wt.bak"
  (cd "$task_wt" && git add -A && git commit -q -m "mark done")

  # Remove the req worktree directory
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"

  # 用 task worktree 里的 task 文件路径（req worktree 已删）
  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task_in_wt") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when req worktree missing"
  else
    if grep -q "req worktree" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing req worktree message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT2: task worktree has uncommitted changes → reject
# =================================================
test_reject_if_task_worktree_dirty() {
  start_test "I-CT2 reject when task worktree has uncommitted changes"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "005" "dirty" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  _mark_task_done "$task"

  # Create uncommitted file in task worktree
  echo "dirty work" > "$task_wt/uncommitted.txt"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when task worktree is dirty"
  else
    if grep -q "未提交" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing uncommitted-changes message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT3: merge conflict → reject
# =================================================
test_reject_on_merge_conflict() {
  start_test "I-CT3 reject when merge has conflicts"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "006" "conflict" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # Create conflicting file in req worktree
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "from req side" > shared.txt
    git add shared.txt
    git commit -q -m "req: add shared.txt"
  )

  # Create conflicting file in task worktree (same path, different content)
  (
    cd "$task_wt"
    echo "from task side" > shared.txt
    git add shared.txt
    git commit -q -m "task: add shared.txt"
  )

  _mark_task_done "$task"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject on merge conflict"
  else
    # Either merge fails or ancestor check fails — either way we exit non-zero
    if grep -qE "(merge|冲突|conflict)" /tmp/err.$$ /tmp/out.$$; then
      pass_test
    else
      _fail "stderr missing merge-conflict hint"
      cat /tmp/err.$$ >&2
      cat /tmp/out.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT6: 文档偏差 not processed → reject
# =================================================
test_reject_if_doc_diff_not_processed() {
  start_test "I-CT6 reject when 文档偏差 section has content"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "007" "docdiff" "待确认" "/qa")
  fixture_create_task_worktree "$task" "req-001-test" >/dev/null

  _mark_task_done "$task"
  _inject_doc_diff "$task"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when doc diff present"
  else
    if grep -q "文档偏差" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing doc-diff message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Happy path: full close succeeds; archive committed, branch/worktree deleted
# =================================================
test_happy_path_close_task() {
  start_test "happy path: close-task succeeds end-to-end"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "008" "happy" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  task_stem=$(basename "$task" .md)

  # Make a real commit on task branch so merge has something to do
  (
    cd "$task_wt"
    echo "task output" > output.txt
    git add output.txt
    git commit -q -m "task: add output"
  )

  _mark_task_done "$task"

  # Create fake runtime files to exercise archive path
  mkdir -p "$FIXTURE_DIR/.runs/events"
  echo '{"task":"'"$task_stem"'"}' > "$FIXTURE_DIR/.runs/$task_stem.json"
  echo '{"event":"started"}' > "$FIXTURE_DIR/.runs/events/$task_stem.jsonl"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    # Verify task branch deleted
    if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$task_stem"; then
      _fail "task branch should be deleted but still exists"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify task worktree removed
    if [ -d "$FIXTURE_DIR/.worktrees/$task_stem" ]; then
      _fail "task worktree should be removed"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify archive file is tracked on req branch (I-CT4)
    req_wt="$FIXTURE_DIR/.worktrees/req-001-test"
    archive_rel="requirements/active/req-001-test/tasks/_archived/$task_stem/$task_stem.json"
    if ! git -C "$req_wt" ls-files --error-unmatch "$archive_rel" >/dev/null 2>&1; then
      _fail "archive file not tracked on req branch: $archive_rel"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify there's an archive commit in req branch history
    if ! git -C "$req_wt" log --oneline | grep "archive: runtime for $task_stem" >/dev/null; then
      _fail "no archive commit found in req branch log"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify .runs/ originals cleaned
    if [ -f "$FIXTURE_DIR/.runs/$task_stem.json" ]; then
      _fail ".runs/ original should be cleaned"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    pass_test
  else
    _fail "close-task failed on happy path"
    echo "--- stdout ---" >&2
    cat /tmp/out.$$ >&2
    echo "--- stderr ---" >&2
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Run all tests
# =================================================
test_reject_if_status_not_done
test_reject_if_status_pending_review
test_reject_if_task_branch_missing
test_reject_if_req_worktree_missing
test_reject_if_task_worktree_dirty
test_reject_on_merge_conflict
test_reject_if_doc_diff_not_processed
test_happy_path_close_task

report_results "close-task"
