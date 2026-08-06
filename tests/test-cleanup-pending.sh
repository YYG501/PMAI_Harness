#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLEANUP="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"

# Helper: write a pending-cleanup.json with one work entry for $branch / $worktree
_write_pending_work_entry() {
  local branch="$1"
  local worktree="$2"
  python3 - "$FIXTURE_DIR/.runs/pending-cleanup.json" "$branch" "$worktree" <<'PY'
import json, os, sys
path, branch, worktree = sys.argv[1:4]
os.makedirs(os.path.dirname(path), exist_ok=True)
entries = []
if os.path.exists(path):
    with open(path) as f:
        entries = json.load(f)
entries.append({
    "kind": "work",
    "branch": branch,
    "worktree": worktree,
    "work_dir": "docs/modules/" + branch,
    "queued_at": "2026-04-26T13:00:00+08:00",
})
with open(path, "w") as f:
    json.dump(entries, f, indent=2)
PY
}

# =================================================
# C1: no pending file → exit 0 with friendly message
# =================================================
test_no_pending_file_exits_zero() {
  start_test "C1 no pending file → exit 0"
  fixture_setup

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q "无待清理项" /tmp/out.$$; then
      pass_test
    else
      _fail "expected '无待清理项' on stdout"
      cat /tmp/out.$$ >&2
    fi
  else
    _fail "cleanup should exit 0 when no pending file"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# C2: empty pending list → exit 0
# =================================================
test_empty_pending_list_exits_zero() {
  start_test "C2 empty pending list → exit 0"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/.runs"
  echo "[]" > "$FIXTURE_DIR/.runs/pending-cleanup.json"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "should exit 0 on empty list"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# C3: happy path — pending entry → worktree + branch removed, file cleared
# =================================================
test_happy_path_removes_worktree_branch_and_file() {
  start_test "C3 happy: removes worktree + branch, deletes pending file when list empty"
  fixture_setup

  fixture_create_work "work-001" "happy" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-001-happy"
  work_branch="build-work-001-happy"

  _write_pending_work_entry "$work_branch" "$work_wt"

  if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup failed"
    cat /tmp/out.$$ >&2
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -d "$work_wt" ]; then
    _fail "worktree should be removed: $work_wt"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi
  if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch"; then
    _fail "branch should be deleted: $work_branch"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi
  if [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "pending-cleanup.json should be removed when list becomes empty"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# C4: safety — caller cwd inside a pending worktree → reject
# =================================================
test_reject_when_cwd_inside_pending_worktree() {
  start_test "C4 cwd failure → retry → repeated cleanup stays idempotent"
  fixture_setup

  fixture_create_work "work-002" "trap" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-002-trap"

  _write_pending_work_entry "build-work-002-trap" "$work_wt"

  if (cd "$work_wt" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when cwd is inside pending worktree"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  elif ! grep -q "cwd 在以下待清理 worktree 内" /tmp/err.$$; then
    _fail "stderr missing cwd-in-pending message"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # Pending file must still exist after the failed attempt.
  if [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "pending-cleanup.json should remain after rejection"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should recover when retried from main"
  elif [ -d "$work_wt" ] || \
       git -C "$FIXTURE_DIR" show-ref --verify --quiet refs/heads/build-work-002-trap || \
       [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "successful retry should remove exactly the queued worktree, branch, and entry"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "repeated cleanup should remain a no-op"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# C5: partial — worktree dir already gone → still removes branch, prunes
# =================================================
test_partial_worktree_already_gone() {
  start_test "C5 worktree already removed externally → still cleans branch + entry"
  fixture_setup

  fixture_create_work "work-003" "stale" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-003-stale"
  work_branch="build-work-003-stale"

  _write_pending_work_entry "$work_branch" "$work_wt"

  # Simulate: worktree dir removed by hand (but git metadata still references it)
  rm -rf "$work_wt"

  if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should succeed even if worktree dir already gone"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch"; then
    _fail "branch should be deleted even when worktree dir already gone"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# C6: dry-run lists but does not remove
# =================================================
test_dry_run_does_not_remove() {
  start_test "C6 dry-run lists pending but removes nothing"
  fixture_setup

  fixture_create_work "work-004" "dryrun" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-004-dryrun"
  work_branch="build-work-004-dryrun"

  _write_pending_work_entry "$work_branch" "$work_wt"

  if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP" --dry-run) >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "dry-run should exit 0"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q "dry-run" /tmp/out.$$; then
    _fail "stdout should mention dry-run"
    cat /tmp/out.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ ! -d "$work_wt" ]; then
    _fail "worktree should still exist after dry-run"
  fi
  if ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch"; then
    _fail "branch should still exist after dry-run"
  fi
  if [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "pending-cleanup.json should still exist after dry-run"
  fi

  if [ "$FAIL_COUNT" = "0" ]; then
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# C7: malicious pending entry must not delete arbitrary directories
# =================================================
test_rejects_unregistered_existing_worktree_path() {
  start_test "C7 safety: unregistered existing worktree path is preserved"
  fixture_setup

  victim="$FIXTURE_DIR/not-a-worktree-but-important"
  mkdir -p "$victim"
  echo "keep" > "$victim/keep.txt"
  _write_pending_work_entry "build-work-999-evil" "$victim"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should reject unsafe pending entry"
    cat /tmp/out.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ ! -f "$victim/keep.txt" ]; then
    _fail "unsafe cleanup deleted arbitrary directory: $victim"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi
  if [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "unsafe entry should remain pending for manual inspection"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi
  if ! grep -q "unsafe pending entry" /tmp/out.$$; then
    _fail "stdout should explain unsafe pending entry"
    cat /tmp/out.$$ /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_rejects_corrupt_pending_file() {
  start_test "C8 corrupt pending queue fails closed and is preserved"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/.runs"
  printf '{not-json\n' > "$FIXTURE_DIR/.runs/pending-cleanup.json"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "corrupt pending queue should fail"
  elif ! grep -q "拒绝按空队列继续" /tmp/err.$$; then
    _fail "corrupt queue guidance mismatch"
    cat /tmp/err.$$ >&2
  elif [ "$(cat "$FIXTURE_DIR/.runs/pending-cleanup.json")" != "{not-json" ]; then
    _fail "corrupt queue should not be overwritten or discarded"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
test_no_pending_file_exits_zero
test_empty_pending_list_exits_zero
test_happy_path_removes_worktree_branch_and_file
test_reject_when_cwd_inside_pending_worktree
test_partial_worktree_already_gone
test_dry_run_does_not_remove
test_rejects_unregistered_existing_worktree_path
test_rejects_corrupt_pending_file

report_results "cleanup-pending"
