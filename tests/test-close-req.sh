#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_REQ="$FRAMEWORK_ROOT/scripts/close-req.sh"

# Helper: set req stage in meta.json
_set_req_stage() {
  local req_dir="$1"
  local stage="$2"
  python3 -c "
import json
p = '$req_dir/.req-meta.json'
with open(p) as f:
    meta = json.load(f)
meta['stage'] = $stage
with open(p, 'w') as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
"
  # Also commit the change on req branch so it's current
  local req_branch
  req_branch=$(python3 -c "import json; print(json.load(open('$req_dir/.req-meta.json'))['branch'])")
  (
    cd "$FIXTURE_DIR/.worktrees/$req_branch"
    git add -A
    git commit -q -m "stage: bump to $stage" 2>/dev/null || true
  )
}

# =================================================
# I-CR1: reject when stage is not 7
# =================================================
test_reject_if_stage_not_7() {
  start_test "I-CR1 reject when req stage is not 7"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 5)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when stage is not 7"
  else
    if grep -q "stage" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing stage message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR2: reject when there are open tasks
# =================================================
test_reject_if_open_tasks_exist() {
  start_test "I-CR2 reject when there are open tasks"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)
  # Create a task with status 执行中 (open)
  task=$(fixture_create_task "$req_dir" "001" "stillopen" "执行中" "/qa")
  # Commit the task file
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    git add -A
    git commit -q -m "add open task"
  )

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when task is still open"
  else
    if grep -q "尚未关闭" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing open-tasks message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR3: reject when req branch does not exist
# =================================================
test_reject_if_req_branch_missing() {
  start_test "I-CR3 reject when req branch does not exist (suggest cancel-req)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)

  # Copy req dir to main repo so script can find meta even with branch gone
  main_req_dir="$FIXTURE_DIR/requirements/active/req-001-test"
  mkdir -p "$(dirname "$main_req_dir")"
  cp -R "$req_dir" "$main_req_dir"

  # Delete req branch + worktree
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"
  git -C "$FIXTURE_DIR" branch -D "req-001-test" 2>/dev/null || true

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$main_req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when req branch missing"
  else
    if grep -qE "(分支.*不存在|cancel-req)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing branch-missing / cancel-req message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR4: reject when req worktree does not exist
# =================================================
test_reject_if_req_worktree_missing() {
  start_test "I-CR4 reject when req worktree does not exist"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)

  # Copy meta to main repo so we can pass a valid path
  main_req_dir="$FIXTURE_DIR/requirements/active/req-001-test"
  mkdir -p "$(dirname "$main_req_dir")"
  cp -R "$req_dir" "$main_req_dir"

  # Remove worktree directory but keep branch
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$main_req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when req worktree missing"
  else
    if grep -q "worktree" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing worktree message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR9: merge conflict → should not leave half-complete state
# =================================================
test_reject_on_merge_conflict_no_partial_state() {
  start_test "I-CR9 merge conflict does not leave partial state on main"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)

  # Modify main branch to create a conflict with what req branch will do
  (
    cd "$FIXTURE_DIR"
    # main currently is a fresh init. Add a file that req branch has also modified.
    echo "main version" > conflict.txt
    git add conflict.txt
    git commit -q -m "main: conflict.txt"
  )

  # Modify same file on req branch
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "req version" > conflict.txt
    git add conflict.txt
    git commit -q -m "req: conflict.txt"
  )

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    # It might still "succeed" if it auto-resolves, but the point is no partial state
    :
  fi

  # Verify main does NOT have req-001-test under closed/ without being actually merged
  # If merge failed, closed/req-001-test should not exist on main
  (
    cd "$FIXTURE_DIR"
    git checkout main -q 2>/dev/null || true
  )

  # Check: on main, if closed/req-001-test exists, then merge must have truly succeeded
  # (meaning active/req-001-test must NOT exist and status is closed). Otherwise we have
  # a half state.
  if [ -d "$FIXTURE_DIR/requirements/closed/req-001-test" ]; then
    # If in closed, verify meta.status is closed — otherwise it's half-state
    status=$(python3 -c "import json; print(json.load(open('$FIXTURE_DIR/requirements/closed/req-001-test/.req-meta.json'))['status'])" 2>/dev/null || echo "unknown")
    if [ "$status" = "closed" ]; then
      pass_test
    else
      _fail "main has closed/req-001-test but status=$status (half state)"
    fi
  else
    # If not in closed/, make sure main also doesn't have a half-merged state where
    # the req branch was deleted but archive never landed.
    if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/req-001-test"; then
      # req branch still exists — a clean retry-able state. Good.
      pass_test
    else
      # Branch deleted but nothing in closed/ — half state
      _fail "req branch deleted but closed/req-001-test missing (half state)"
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR5: archive must be committed on req branch before merge
# (verified via happy path: after close, main branch log should contain the archive commit)
# =================================================
test_archive_committed_before_merge() {
  start_test "I-CR5 archive commit lands before merge (happy path verifies order)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    # After close, main should contain the archive commit "close: archive req-001"
    if git -C "$FIXTURE_DIR" log main --oneline | grep "close: archive req-001" >/dev/null; then
      pass_test
    else
      _fail "archive commit not found on main branch log"
      git -C "$FIXTURE_DIR" log main --oneline >&2
    fi
  else
    _fail "close-req failed unexpectedly"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Happy path: full close-req succeeds
# =================================================
test_happy_path_close_req() {
  start_test "happy path: close-req succeeds and main has closed/req"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    # Verify: main branch has requirements/closed/req-001-test
    closed_dir="$FIXTURE_DIR/requirements/closed/req-001-test"
    if [ ! -d "$closed_dir" ]; then
      _fail "requirements/closed/req-001-test missing on main"
      ls "$FIXTURE_DIR/requirements" >&2 2>&1 || true
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify meta.status = closed
    status=$(python3 -c "import json; print(json.load(open('$closed_dir/.req-meta.json'))['status'])" 2>/dev/null || echo "unknown")
    if [ "$status" != "closed" ]; then
      _fail "expected meta.status=closed, got $status"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify active/req-001-test no longer on main
    if [ -d "$FIXTURE_DIR/requirements/active/req-001-test" ]; then
      _fail "active/req-001-test should not exist on main after close"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # close-req.sh 在 cwd=主仓时直接删 worktree + branch（无 pending-cleanup 中转）
    if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/req-001-test"; then
      _fail "req branch should be deleted by close-req.sh"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi
    if [ -d "$FIXTURE_DIR/.worktrees/req-001-test" ]; then
      _fail "req worktree should be removed by close-req.sh"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify current branch is main
    cur=$(git -C "$FIXTURE_DIR" branch --show-current)
    if [ "$cur" != "main" ]; then
      _fail "expected to land on main, got $cur"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    pass_test
  else
    _fail "close-req failed on happy path"
    echo "--- stdout ---" >&2
    cat /tmp/out.$$ >&2
    echo "--- stderr ---" >&2
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Extra: happy path with a closed task archive present
# =================================================
test_happy_path_with_completed_task() {
  start_test "happy path: close-req works when req has a 已完成 task"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)
  task=$(fixture_create_task "$req_dir" "001" "done" "已完成" "/qa")
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    git add -A
    git commit -q -m "add completed task"
  )

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    # closed dir should have the task too
    closed_task="$FIXTURE_DIR/requirements/closed/req-001-test/tasks/task-001-done.md"
    if [ -f "$closed_task" ]; then
      pass_test
    else
      _fail "task file not preserved in closed/"
    fi
  else
    _fail "close-req failed with completed task present"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR9b: on merge failure, req branch is reset to pre-close (not left in closed/)
# =================================================
test_merge_failure_rolls_back_req_branch() {
  start_test "I-CR9b merge failure rolls req branch back to pre-close state"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)

  # Create conflict: same file on main and on req branch with different content
  (
    cd "$FIXTURE_DIR"
    echo "main" > clash.txt && git add clash.txt && git commit -q -m "main: clash"
  )
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "req" > clash.txt && git add clash.txt && git commit -q -m "req: clash"
  )

  # Should fail
  (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$ && \
    { _fail "close-req should have failed on conflict"; rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  # On req branch: active/req-001-test must still exist (pre-close state)
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"
  if [ ! -d "$req_wt/requirements/active/req-001-test" ]; then
    _fail "req branch should be rolled back to active/ (not left at closed/)"
    ls "$req_wt/requirements" >&2 2>&1 || true
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # On req branch: closed/req-001-test must NOT exist
  if [ -d "$req_wt/requirements/closed/req-001-test" ]; then
    _fail "closed/req-001-test should not exist on req branch after rollback"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR10: reject when cwd is inside the req worktree
# =================================================
test_reject_when_cwd_inside_req_worktree() {
  start_test "I-CR10 reject when cwd is inside req worktree"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"

  if (cd "$req_wt" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when cwd is inside req worktree"
  else
    if grep -qE "(cwd 在 req worktree|切到主仓窗口)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing cwd-in-worktree message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_if_req_worktree_has_unrelated_dirty_changes() {
  start_test "I-CR11 reject unrelated dirty changes in req worktree"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 7)
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"
  mkdir -p "$req_wt/prototypes"
  echo "leak" > "$req_wt/prototypes/unrelated.txt"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject unrelated dirty file instead of committing it"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q "当前 req 目录外" /tmp/err.$$; then
    _fail "stderr missing unrelated dirty guidance"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if git -C "$FIXTURE_DIR" show main:prototypes/unrelated.txt >/dev/null 2>&1; then
    _fail "unrelated dirty file leaked into main"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Run all tests
# =================================================
test_reject_if_stage_not_7
test_reject_if_open_tasks_exist
test_reject_if_req_branch_missing
test_reject_if_req_worktree_missing
test_reject_when_cwd_inside_req_worktree
test_reject_if_req_worktree_has_unrelated_dirty_changes
test_reject_on_merge_conflict_no_partial_state
test_archive_committed_before_merge
test_happy_path_close_req
test_happy_path_with_completed_task
test_merge_failure_rolls_back_req_branch

report_results "close-req"
