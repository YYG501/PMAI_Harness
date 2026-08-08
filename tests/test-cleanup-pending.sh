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

test_preamble_consumes_pending_cleanup_from_main() {
  start_test "C9 main preamble automatically consumes pending cleanup"
  fixture_setup
  fixture_create_work "work-009" "preamble" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-009-preamble"
  work_branch="build-work-009-preamble"
  _write_pending_work_entry "$work_branch" "$work_wt"

  if ! out=$(cd "$FIXTURE_DIR" && PMAI_HOME="$FRAMEWORK_ROOT" bash -c \
    'set -e; source "$PMAI_HOME/scripts/skill-preamble.sh"; echo CALLER_CONTINUED' 2>&1); then
    _fail "main preamble should consume cleanup without failing"
    echo "$out" >&2
  elif [ -d "$work_wt" ] \
    || git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "main preamble should remove the queued worktree, branch, and queue entry"
  elif ! printf '%s\n' "$out" | grep -q "CALLER_CONTINUED"; then
    _fail "preamble cleanup should return control to the caller"
  else
    pass_test
  fi

  fixture_teardown
}

test_preamble_defers_cleanup_inside_build_worktree() {
  start_test "C10 build worktree preamble defers pending cleanup"
  fixture_setup
  fixture_create_work "work-010" "unsafe-cwd" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-010-unsafe-cwd"
  work_branch="build-work-010-unsafe-cwd"
  _write_pending_work_entry "$work_branch" "$work_wt"

  if ! out=$(cd "$work_wt" && PMAI_HOME="$FRAMEWORK_ROOT" bash -c \
    'set -e; source "$PMAI_HOME/scripts/skill-preamble.sh"; echo CALLER_CONTINUED' 2>&1); then
    _fail "preamble should remain usable inside a pending build worktree"
    echo "$out" >&2
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "preamble must defer cleanup while cwd is inside the pending worktree"
  elif ! printf '%s\n' "$out" | grep -q "CALLER_CONTINUED"; then
    _fail "deferred cleanup should return control to the caller"
  else
    pass_test
  fi

  fixture_teardown
}

test_preamble_cleanup_failure_is_nonblocking() {
  start_test "C11 failed background cleanup preserves queue and caller"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/.runs"
  printf '{not-json\n' > "$FIXTURE_DIR/.runs/pending-cleanup.json"

  if ! out=$(cd "$FIXTURE_DIR" && PMAI_HOME="$FRAMEWORK_ROOT" bash -c \
    'set -e; source "$PMAI_HOME/scripts/skill-preamble.sh"; echo CALLER_CONTINUED' 2>&1); then
    _fail "cleanup failure must not exit the sourced caller"
    echo "$out" >&2
  elif ! printf '%s\n' "$out" | grep -q "CALLER_CONTINUED"; then
    _fail "caller did not continue after cleanup failure"
  elif ! printf '%s\n' "$out" | grep -q "后续会自动重试"; then
    _fail "preamble should report a concise nonblocking retry notice"
  elif [ "$(cat "$FIXTURE_DIR/.runs/pending-cleanup.json")" != "{not-json" ]; then
    _fail "failed background cleanup should preserve the queue for diagnosis and retry"
  else
    pass_test
  fi

  fixture_teardown
}

test_cleanup_defers_while_another_process_uses_worktree() {
  start_test "C12 cross-session cwd keeps cleanup queued until the worktree is unused"
  fixture_setup
  fixture_create_work "work-012" "cross-session" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-012-cross-session"
  work_branch="build-work-012-cross-session"
  _write_pending_work_entry "$work_branch" "$work_wt"

  (cd "$work_wt" && exec sleep 30) &
  holder=$!
  sleep 1

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should defer while another process cwd is inside the worktree"
  elif [ ! -d "$work_wt" ] \
    || [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ] \
    || ! grep -q "still used as cwd" /tmp/out.$$; then
    _fail "busy worktree or its cleanup entry was not preserved"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    holder=""
    if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
      _fail "cleanup should retry successfully after the other process exits"
    elif [ -d "$work_wt" ] \
      || git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
      || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
      _fail "successful retry should remove the worktree, branch, and queue entry"
    else
      pass_test
    fi
  fi

  if [ -n "${holder:-}" ]; then
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
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
test_preamble_consumes_pending_cleanup_from_main
test_preamble_defers_cleanup_inside_build_worktree
test_preamble_cleanup_failure_is_nonblocking
test_cleanup_defers_while_another_process_uses_worktree

report_results "cleanup-pending"
