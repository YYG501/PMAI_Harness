#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLEANUP="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"
PENDING_QUEUE_HELPER="$FRAMEWORK_ROOT/scripts/_lib/pending_cleanup.py"

# Helper: write a pending-cleanup.json with one work entry for $branch / $worktree
_write_pending_work_entry() {
  local branch="$1"
  local worktree="$2"
  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$FIXTURE_DIR/.runs/pending-cleanup.json" \
    --kind work \
    --branch "$branch" \
    --worktree "$worktree" \
    --work-dir "docs/modules/$branch"
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

test_enqueue_missing_branch_records_empty_identity() {
  start_test "C6b enqueue: missing branch records an empty stable identity"
  fixture_setup
  local branch queue
  branch="build-missing-at-enqueue"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"

  if ! python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$queue" \
    --kind work \
    --branch "$branch" \
    --worktree "$FIXTURE_DIR/.worktrees/$branch" \
    --work-dir "docs/modules/missing-at-enqueue"; then
    _fail "enqueue should accept an already-missing branch"
  elif ! python3 - "$queue" "$branch" <<'PY'
import json
import sys

entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["branch"] == sys.argv[2], entries
assert entries[0]["branch_oid"] == "", entries
PY
  then
    _fail "missing branch enqueue did not persist an empty identity"
  else
    pass_test
  fi

  fixture_teardown
}

test_enqueue_git_query_error_preserves_queue() {
  start_test "C6c enqueue: fatal Git query preserves the existing queue"
  fixture_setup
  local queue sentinel_branch fake_bin real_git out rc
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  sentinel_branch="build-enqueue-sentinel"
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  git -C "$FIXTURE_DIR" branch "$sentinel_branch"
  _write_pending_work_entry "$sentinel_branch" "$FIXTURE_DIR/.worktrees/$sentinel_branch"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "show-ref" ]; then
  echo "simulated fatal ref query" >&2
  exit 2
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  out=$(PATH="$fake_bin:$PATH" PMAI_TEST_REAL_GIT="$real_git" \
    python3 "$PENDING_QUEUE_HELPER" enqueue \
      --file "$queue" \
      --kind work \
      --branch build-query-failure \
      --worktree "$FIXTURE_DIR/.worktrees/build-query-failure" \
      --work-dir "docs/modules/query-failure" 2>&1)
  rc=$?
  if [ "$rc" = "0" ]; then
    _fail "enqueue should fail closed on a fatal Git ref query"
  elif ! echo "$out" | grep -q "无法读取待清理分支身份"; then
    _fail "enqueue did not report the fatal Git ref query: $out"
  elif ! python3 - "$queue" "$sentinel_branch" <<'PY'
import json
import sys

entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["branch"] == sys.argv[2], entries
PY
  then
    _fail "fatal Git ref query changed the existing queue"
  else
    pass_test
  fi

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

test_rejects_unregistered_missing_worktree_for_live_branch() {
  start_test "C7b safety: missing path cannot authorize deleting an unrelated build branch"
  fixture_setup
  local victim_branch missing_path
  victim_branch="build-victim-branch"
  missing_path="$FIXTURE_DIR/.worktrees/missing-worktree"
  git -C "$FIXTURE_DIR" branch "$victim_branch"
  _write_pending_work_entry "$victim_branch" "$missing_path"
  python3 - "$FIXTURE_DIR/.runs/pending-cleanup.json" <<'PY'
import json, sys
path = sys.argv[1]
entries = json.load(open(path, encoding="utf-8"))
entries[0].pop("branch_oid", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(entries, handle, indent=2)
PY

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should reject a missing path without Git worktree binding"
  elif ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$victim_branch"; then
    _fail "unbound queue entry deleted an unrelated live branch"
  elif [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "unbound queue entry should remain for manual inspection"
  elif ! grep -q "live branch has no recorded identity" /tmp/out.$$; then
    _fail "cleanup should explain the missing branch identity failure"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_rejects_unmerged_branch_only_cleanup() {
  start_test "C7c safety: branch-only cleanup requires the branch to be merged"
  fixture_setup
  local victim_branch
  victim_branch="build-unmerged-branch"
  git -C "$FIXTURE_DIR" switch -q -c "$victim_branch"
  echo "unmerged" > "$FIXTURE_DIR/unmerged.txt"
  git -C "$FIXTURE_DIR" add unmerged.txt
  git -C "$FIXTURE_DIR" commit -q -m "unmerged work"
  git -C "$FIXTURE_DIR" switch -q main
  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$FIXTURE_DIR/.runs/pending-cleanup.json" \
    --kind branch \
    --branch "$victim_branch" \
    --worktree "" \
    --work-dir "docs/modules/unmerged"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "branch-only cleanup should reject an unmerged branch"
  elif ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$victim_branch"; then
    _fail "branch-only cleanup deleted unmerged work"
  elif [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "rejected branch-only cleanup should remain queued"
  elif ! grep -q "not merged into refs/heads/main" /tmp/out.$$; then
    _fail "cleanup should explain why the branch-only retry is unsafe"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_work_cleanup_recovers_after_branch_delete_failure() {
  start_test "C7d worktree removed + branch delete failed remains recoverable"
  fixture_setup
  fixture_create_work "work-007d" "resume" 4 >/dev/null
  local work_wt work_branch fake_bin real_git
  work_wt="$FIXTURE_DIR/.worktrees/build-work-007d-resume"
  work_branch="build-work-007d-resume"
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  _write_pending_work_entry "$work_branch" "$work_wt"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "update-ref" ] && [ "${4:-}" = "--stdin" ]; then
  echo "simulated branch delete failure" >&2
  exit 1
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_GIT="$real_git" \
    bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "first cleanup should report the simulated branch deletion failure"
  elif [ -d "$work_wt" ]; then
    _fail "worktree should already be removed after the partial cleanup"
  elif ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch"; then
    _fail "failed branch deletion should leave the exact queued branch"
  elif ! python3 - "$FIXTURE_DIR/.runs/pending-cleanup.json" <<'PY'
import json, re, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert re.fullmatch(r"[0-9a-f]{40,64}", entries[0]["branch_oid"]), entries
PY
  then
    _fail "partial cleanup did not retain a stable branch identity"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "retry should remove the identity-matched branch"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "successful retry should clear the branch and queue entry"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_legacy_work_cleanup_persists_oid_before_interrupted_remove() {
  start_test "C7e legacy queue persists branch identity before destructive removal"
  fixture_setup
  fixture_create_work "work-007e" "interrupted" 4 >/dev/null
  local work_wt work_branch expected_oid fake_bin real_git
  work_wt="$FIXTURE_DIR/.worktrees/build-work-007e-interrupted"
  work_branch="build-work-007e-interrupted"
  expected_oid=$(git -C "$FIXTURE_DIR" rev-parse "$work_branch")
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  mkdir -p "$FIXTURE_DIR/.runs" "$fake_bin"
  python3 - "$FIXTURE_DIR/.runs/pending-cleanup.json" "$work_branch" "$work_wt" <<'PY'
import json
import sys

queue, branch, worktree = sys.argv[1:]
with open(queue, "w", encoding="utf-8") as handle:
    json.dump(
        [
            {
                "kind": "work",
                "branch": branch,
                "worktree": worktree,
                "work_dir": "docs/modules/interrupted",
            }
        ],
        handle,
        indent=2,
    )
PY
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "worktree" ] && [ "${4:-}" = "remove" ]; then
  "$PMAI_TEST_REAL_GIT" "$@"
  status=$?
  if [ "$status" -eq 0 ]; then
    kill -KILL "$PPID"
  fi
  exit "$status"
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_GIT="$real_git" \
    bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "interrupted cleanup should not report success"
  elif [ -d "$work_wt" ]; then
    _fail "fixture did not reach the destructive worktree removal"
  elif ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch"; then
    _fail "interruption should occur before branch deletion"
  elif ! python3 - "$FIXTURE_DIR/.runs/pending-cleanup.json" "$expected_oid" <<'PY'
import json
import sys

entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0].get("branch_oid") == sys.argv[2], entries
PY
  then
    _fail "legacy queue identity was not persisted before destructive removal"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "persisted identity should authorize cleanup recovery"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "recovered cleanup should remove the exact branch and queue entry"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_branch_only_uses_main_when_current_feature_contains_unmerged_target() {
  start_test "C7f branch-only never treats current feature HEAD as integration baseline"
  fixture_setup
  local target current
  target="build-unmerged-target"
  current="build-current-descendant"
  git -C "$FIXTURE_DIR" switch -q -c "$target"
  echo "target only" > "$FIXTURE_DIR/target-only.txt"
  git -C "$FIXTURE_DIR" add target-only.txt
  git -C "$FIXTURE_DIR" commit -q -m "target only"
  git -C "$FIXTURE_DIR" switch -q -c "$current"
  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$FIXTURE_DIR/.runs/pending-cleanup.json" \
    --kind branch --branch "$target" --worktree "" \
    --work-dir "docs/modules/unmerged-target"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "branch-only cleanup should reject work absent from main"
  elif ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$target"; then
    _fail "current feature ancestry incorrectly authorized branch deletion"
  elif ! grep -q "not merged into refs/heads/main" /tmp/out.$$; then
    _fail "cleanup did not report the main integration baseline"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_branch_only_can_delete_main_merged_target_from_older_feature() {
  start_test "C7g branch-only uses main even when current feature lacks the merged target"
  fixture_setup
  local base target current
  base=$(git -C "$FIXTURE_DIR" rev-parse main)
  target="build-main-merged-target"
  current="build-older-feature"
  git -C "$FIXTURE_DIR" switch -q -c "$target"
  echo "merged target" > "$FIXTURE_DIR/merged-target.txt"
  git -C "$FIXTURE_DIR" add merged-target.txt
  git -C "$FIXTURE_DIR" commit -q -m "merged target"
  git -C "$FIXTURE_DIR" switch -q main
  git -C "$FIXTURE_DIR" merge -q --ff-only "$target"
  git -C "$FIXTURE_DIR" switch -q -c "$current" "$base"
  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$FIXTURE_DIR/.runs/pending-cleanup.json" \
    --kind branch --branch "$target" --worktree "" \
    --work-dir "docs/modules/main-merged-target"

  if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "main-merged branch should be removable from an older feature checkout"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$target" \
    || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "main-merged branch-only cleanup did not complete"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_queue_stage_namespace_does_not_overlap_preamble_markers() {
  start_test "C7h queue transaction stage avoids .pending-* recovery namespace"
  fixture_setup
  if python3 - "$PENDING_QUEUE_HELPER" "$FIXTURE_DIR/.runs/pending-cleanup.json" <<'PY'
import importlib.util
import sys
from pathlib import Path

helper = Path(sys.argv[1])
queue = Path(sys.argv[2])
queue.parent.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location("pending_cleanup_test", helper)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
original = module.tempfile.mkstemp
seen = []

def recording_mkstemp(*args, **kwargs):
    seen.append(kwargs.get("prefix", ""))
    return original(*args, **kwargs)

module.tempfile.mkstemp = recording_mkstemp
module.replace_pending_entries(queue, [{"kind": "branch", "branch": "build-stage"}])
assert seen == [".cleanup-queue."], seen
assert not seen[0].startswith(".pending-")
PY
  then
    pass_test
  else
    _fail "queue writer reused the preamble interrupt-marker namespace"
  fi
  fixture_teardown
}

test_rejects_corrupt_pending_file() {
  start_test "C8 corrupt pending queue fails closed and is preserved"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/.runs"
  printf '{not-json\n' > "$FIXTURE_DIR/.runs/pending-cleanup.json"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "corrupt pending queue should fail"
  elif ! grep -q "待清理队列无法安全读取" /tmp/err.$$; then
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

test_dirty_worktree_is_preserved() {
  start_test "C13 dirty worktree is never force-removed"
  fixture_setup
  fixture_create_work "work-013" "dirty" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-013-dirty"
  work_branch="build-work-013-dirty"
  printf '%s\n' "unsaved" > "$work_wt/UNSAVED.txt"
  _write_pending_work_entry "$work_branch" "$work_wt"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup must fail closed for a dirty worktree"
  elif [ ! -f "$work_wt/UNSAVED.txt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "dirty worktree, branch, and queue entry must all be preserved"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif ! grep -q "uncommitted changes" /tmp/out.$$; then
    _fail "cleanup should explain that uncommitted changes blocked deletion"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_ignored_worktree_files_are_preserved() {
  start_test "C14 ignored untracked files are never removed with the worktree"
  fixture_setup
  fixture_create_work "work-014" "ignored" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-014-ignored"
  work_branch="build-work-014-ignored"
  printf '%s\n' "ignored.log" > "$work_wt/.gitignore"
  git -C "$work_wt" add .gitignore
  git -C "$work_wt" commit -q -m "test: ignore runtime output"
  printf '%s\n' "must survive" > "$work_wt/ignored.log"
  _write_pending_work_entry "$work_branch" "$work_wt"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup must fail closed when ignored files would be deleted"
  elif [ ! -f "$work_wt/ignored.log" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "ignored file, worktree branch, and queue entry must all be preserved"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif ! grep -q "ignored untracked files" /tmp/out.$$; then
    _fail "cleanup should explain that ignored files blocked deletion"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_read_only_preamble_preserves_cleanup_queue() {
  start_test "C15 read-only preamble never consumes pending cleanup"
  fixture_setup
  fixture_create_work "work-014" "readonly" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-014-readonly"
  work_branch="build-work-014-readonly"
  _write_pending_work_entry "$work_branch" "$work_wt"

  if ! out=$(cd "$FIXTURE_DIR" && PMAI_HOME="$FRAMEWORK_ROOT" \
    PMAI_PREAMBLE_READ_ONLY=1 bash -c \
    'set -e; source "$PMAI_HOME/scripts/skill-preamble.sh"; echo CALLER_CONTINUED' 2>&1); then
    _fail "read-only preamble should remain usable"
    echo "$out" >&2
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "read-only preamble mutated the pending worktree, branch, or queue"
  elif ! printf '%s\n' "$out" | grep -q "CALLER_CONTINUED"; then
    _fail "read-only preamble did not return control to the caller"
  else
    pass_test
  fi

  fixture_teardown
}

test_read_only_preamble_preserves_interrupt_markers() {
  start_test "C16 read-only preamble preserves interrupt markers"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/.runs"
  printf '%s\n' '{"skill":"pmai-build","started_at":""}' \
    > "$FIXTURE_DIR/.runs/.pending-build"

  if ! (cd "$FIXTURE_DIR" && PMAI_HOME="$FRAMEWORK_ROOT" \
    PMAI_PREAMBLE_READ_ONLY=1 bash -c \
    'set -e; source "$PMAI_HOME/scripts/skill-preamble.sh" >/dev/null'); then
    _fail "read-only preamble should remain usable with an interrupt marker"
  elif [ ! -f "$FIXTURE_DIR/.runs/.pending-build" ]; then
    _fail "read-only preamble deleted an interrupt marker"
  else
    pass_test
  fi

  fixture_teardown
}

test_preamble_treats_pending_json_as_data() {
  start_test "C17 pending marker values cannot inject Python during read-only preamble"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/.runs"
  sentinel="$FIXTURE_DIR/preamble-sentinel"
  python3 - "$FIXTURE_DIR/.runs/.pending-build" "$sentinel" <<'PY'
import json, sys
marker, sentinel = sys.argv[1:3]
payload = "'); __import__('pathlib').Path(" + repr(sentinel) + ").touch(); #"
with open(marker, "w", encoding="utf-8") as handle:
    json.dump({"skill": "pmai-build", "started_at": payload}, handle)
PY

  if ! (cd "$FIXTURE_DIR" && PMAI_HOME="$FRAMEWORK_ROOT" \
    PMAI_PREAMBLE_READ_ONLY=1 bash -c \
    'set -e; source "$PMAI_HOME/scripts/skill-preamble.sh" >/dev/null'); then
    _fail "read-only preamble should safely parse an invalid started_at value"
  elif [ -e "$sentinel" ]; then
    _fail "repository-controlled pending JSON executed as Python source"
  elif [ ! -f "$FIXTURE_DIR/.runs/.pending-build" ]; then
    _fail "read-only preamble should preserve the inspected marker"
  else
    pass_test
  fi

  fixture_teardown
}

test_status_skill_opts_into_read_only_preamble() {
  start_test "C18 status skill opts into read-only preamble"

  if ! grep -q 'PMAI_PREAMBLE_READ_ONLY=1' \
    "$FRAMEWORK_ROOT/skills/status/SKILL.md"; then
    _fail "pmai-status must explicitly run the shared preamble in read-only mode"
  else
    pass_test
  fi
}

test_concurrent_enqueue_survives_cleanup() {
  start_test "C19 cleanup 与入队并发时不丢失新条目"
  fixture_setup
  fixture_create_work "work-019" "locked" 4 >/dev/null
  local work_wt work_branch fake_bin marker continue_file real_git cleanup_pid enqueue_pid
  work_wt="$FIXTURE_DIR/.worktrees/build-work-019-locked"
  work_branch="build-work-019-locked"
  fake_bin="$FIXTURE_DIR/fakebin"
  marker="$FIXTURE_DIR/cleanup-holds-lock"
  continue_file="$FIXTURE_DIR/continue-cleanup"
  real_git=$(command -v git)
  _write_pending_work_entry "$work_branch" "$work_wt"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "worktree" ] && [ "${4:-}" = "list" ]; then
  : > "$PMAI_TEST_CLEANUP_LOCKED"
  while [ ! -f "$PMAI_TEST_CLEANUP_CONTINUE" ]; do
    sleep 0.05
  done
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  (
    cd "$FIXTURE_DIR" || exit 99
    PATH="$fake_bin:$PATH" \
      PMAI_TEST_CLEANUP_LOCKED="$marker" \
      PMAI_TEST_CLEANUP_CONTINUE="$continue_file" \
      PMAI_TEST_REAL_GIT="$real_git" \
      bash "$CLEANUP"
  ) >/tmp/out.$$ 2>/tmp/err.$$ &
  cleanup_pid=$!

  local attempts=0
  while [ ! -f "$marker" ] && [ "$attempts" -lt 100 ]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  if [ ! -f "$marker" ]; then
    _fail "cleanup did not reach the locked Git query"
    kill "$cleanup_pid" 2>/dev/null || true
    wait "$cleanup_pid" 2>/dev/null || true
    fixture_teardown
    return
  fi

  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$FIXTURE_DIR/.runs/pending-cleanup.json" \
    --kind work \
    --branch build-concurrent-new \
    --worktree "$FIXTURE_DIR/.worktrees/build-concurrent-new" \
    --work-dir "$FIXTURE_DIR/docs/modules/concurrent-new" &
  enqueue_pid=$!
  sleep 0.2
  if ! kill -0 "$enqueue_pid" 2>/dev/null; then
    _fail "enqueue should wait while cleanup owns the queue lock"
    touch "$continue_file"
    wait "$cleanup_pid" 2>/dev/null || true
    wait "$enqueue_pid" 2>/dev/null || true
    fixture_teardown
    return
  fi

  touch "$continue_file"
  if ! wait "$cleanup_pid"; then
    _fail "locked cleanup failed"
    cat /tmp/out.$$ /tmp/err.$$ >&2
    wait "$enqueue_pid" 2>/dev/null || true
  elif ! wait "$enqueue_pid"; then
    _fail "enqueue failed after cleanup released the queue lock"
  elif ! python3 - "$FIXTURE_DIR/.runs/pending-cleanup.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert [entry["branch"] for entry in entries] == ["build-concurrent-new"], entries
PY
  then
    _fail "concurrent enqueue was lost or stale cleanup entry survived"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_git_worktree_query_error_preserves_queue() {
  start_test "C20 git worktree list 致命错误时不删除任何目标"
  fixture_setup
  fixture_create_work "work-020" "git-error" 4 >/dev/null
  local work_wt work_branch fake_bin real_git
  work_wt="$FIXTURE_DIR/.worktrees/build-work-020-git-error"
  work_branch="build-work-020-git-error"
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  _write_pending_work_entry "$work_branch" "$work_wt"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "worktree" ] && [ "${4:-}" = "list" ]; then
  echo "simulated worktree query failure" >&2
  exit 2
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_GIT="$real_git" \
    bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "fatal worktree query should fail cleanup"
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "fatal worktree query mutated the worktree, branch, or queue"
  elif ! grep -q "worktree list 查询失败" /tmp/err.$$; then
    _fail "cleanup did not report the fatal worktree query"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_git_show_ref_error_preserves_queue() {
  start_test "C21 git show-ref 致命错误在删除前失败关闭"
  fixture_setup
  fixture_create_work "work-021" "ref-error" 4 >/dev/null
  local work_wt work_branch fake_bin real_git
  work_wt="$FIXTURE_DIR/.worktrees/build-work-021-ref-error"
  work_branch="build-work-021-ref-error"
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  _write_pending_work_entry "$work_branch" "$work_wt"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "show-ref" ] \
  && [ "${6:-}" = "refs/heads/build-work-021-ref-error" ]; then
  echo "simulated ref query failure" >&2
  exit 2
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_GIT="$real_git" \
    bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "fatal show-ref query should fail cleanup"
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "fatal show-ref query mutated the worktree, branch, or queue"
  elif ! grep -q "show-ref 查询分支" /tmp/err.$$; then
    _fail "cleanup did not report the fatal show-ref query"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_prepared_cleanup_promotes_durably_after_cancel_commit() {
  start_test "C22 prepared cancel survives interruption and promotes before deletion"
  fixture_setup
  fixture_create_work "work-022" "prepared" 4 >/dev/null
  local work_wt work_branch module_meta queue fake_bin real_git
  work_wt="$FIXTURE_DIR/.worktrees/build-work-022-prepared"
  work_branch="build-work-022-prepared"
  module_meta="docs/modules/prepared/.work-meta.json"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)

  mkdir -p "$FIXTURE_DIR/docs/modules/prepared"
  printf '{"build":{"lifecycle_state":"final_check"}}\n' \
    > "$FIXTURE_DIR/$module_meta"
  git -C "$FIXTURE_DIR" add -- "$module_meta"
  git -C "$FIXTURE_DIR" commit -q -m "track cancel state"
  python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind work --branch "$work_branch" \
    --worktree "$work_wt" --work-dir "docs/modules/prepared" \
    --activation main_meta_absent --module-meta "$module_meta"

  if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "prepared cleanup should wait without failing before the cancel commit"
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || ! python3 - "$queue" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1 and entries[0]["phase"] == "prepared", entries
PY
  then
    _fail "an uncommitted prepared intent became destructive"
    fixture_teardown; return
  fi

  git -C "$FIXTURE_DIR" rm -q -- "$module_meta"
  git -C "$FIXTURE_DIR" commit -q -m "commit cancel state"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "worktree" ] && [ "${4:-}" = "remove" ]; then
  echo "simulated interruption after activation" >&2
  exit 1
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_GIT="$real_git" \
    bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "simulated post-activation interruption should leave a retry"
  elif ! python3 - "$queue" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1 and entries[0]["phase"] == "active", entries
PY
  then
    _fail "automatic promotion was not persisted before deletion"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "active cleanup should recover on the next run"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif [ -d "$work_wt" ] \
    || git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ -f "$queue" ]; then
    _fail "recovered cleanup did not remove the exact worktree, branch, and entry"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_branch_delete_cas_preserves_concurrently_moved_ref() {
  start_test "C23 branch CAS never deletes a concurrently moved ref"
  fixture_setup
  fixture_create_work "work-023" "cas-race" 4 >/dev/null
  local work_wt work_branch old_oid tree_oid new_oid fake_bin real_git queue
  work_wt="$FIXTURE_DIR/.worktrees/build-work-023-cas-race"
  work_branch="build-work-023-cas-race"
  old_oid=$(git -C "$FIXTURE_DIR" rev-parse "$work_branch")
  tree_oid=$(git -C "$FIXTURE_DIR" rev-parse "$work_branch^{tree}")
  new_oid=$(printf '%s\n' "concurrent branch move" | \
    git -C "$FIXTURE_DIR" commit-tree "$tree_oid" -p "$old_oid")
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  _write_pending_work_entry "$work_branch" "$work_wt"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "update-ref" ] && [ "${4:-}" = "--stdin" ]; then
  "$PMAI_TEST_REAL_GIT" -C "$PMAI_TEST_REPO" update-ref \
    "refs/heads/$PMAI_TEST_BRANCH" "$PMAI_TEST_NEW_OID" "$PMAI_TEST_OLD_OID" || exit $?
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" \
    PMAI_TEST_REAL_GIT="$real_git" PMAI_TEST_REPO="$FIXTURE_DIR" \
    PMAI_TEST_BRANCH="$work_branch" PMAI_TEST_OLD_OID="$old_oid" \
    PMAI_TEST_NEW_OID="$new_oid" bash "$CLEANUP") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should report the failed old-OID CAS deletion"
  elif [ -d "$work_wt" ]; then
    _fail "fixture did not reach branch deletion after worktree removal"
  elif [ "$(git -C "$FIXTURE_DIR" rev-parse "$work_branch")" != "$new_oid" ]; then
    _fail "CAS cleanup deleted or rewound the concurrently moved branch"
  elif ! python3 - "$queue" "$old_oid" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["branch_oid"] == sys.argv[2], entries
PY
  then
    _fail "failed CAS deletion should preserve the original queue identity"
  elif (cd "$FIXTURE_DIR" && bash "$CLEANUP") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "a later cleanup must also reject the moved branch identity"
  elif [ "$(git -C "$FIXTURE_DIR" rev-parse "$work_branch")" != "$new_oid" ] \
    || [ ! -f "$queue" ]; then
    _fail "identity mismatch retry mutated the moved branch or dropped its queue entry"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_recorded_master_ref_ignores_stale_main() {
  start_test "C24 recorded master integration ignores a stale main ref"
  fixture_setup
  local target queue
  target="build-master-recorded"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  git -C "$FIXTURE_DIR" switch -q -c master
  git -C "$FIXTURE_DIR" switch -q -c "$target"
  printf '%s\n' "master only" > "$FIXTURE_DIR/master-recorded.txt"
  git -C "$FIXTURE_DIR" add master-recorded.txt
  git -C "$FIXTURE_DIR" commit -q -m "master-only recorded target"
  git -C "$FIXTURE_DIR" switch -q master
  git -C "$FIXTURE_DIR" merge -q --ff-only "$target"
  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$queue" --kind branch --branch "$target" \
    --worktree "" --work-dir "docs/modules/master-recorded" \
    --integration-ref refs/heads/master

  if git -C "$FIXTURE_DIR" merge-base --is-ancestor "$target" main; then
    _fail "fixture main unexpectedly contains the master-only target"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "recorded master integration should authorize cleanup"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$target" \
    || [ -f "$queue" ]; then
    _fail "recorded master cleanup used stale main or left its queue entry"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_legacy_entry_prefers_checked_out_master_over_stale_main() {
  start_test "C25 legacy integration binds durably to checked-out master"
  fixture_setup
  local target queue fake_bin real_git
  target="build-master-legacy"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  git -C "$FIXTURE_DIR" switch -q -c master
  git -C "$FIXTURE_DIR" switch -q -c "$target"
  printf '%s\n' "legacy master only" > "$FIXTURE_DIR/master-legacy.txt"
  git -C "$FIXTURE_DIR" add master-legacy.txt
  git -C "$FIXTURE_DIR" commit -q -m "master-only legacy target"
  git -C "$FIXTURE_DIR" switch -q master
  git -C "$FIXTURE_DIR" merge -q --ff-only "$target"
  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$queue" --kind branch --branch "$target" \
    --worktree "" --work-dir "docs/modules/master-legacy" \
    --integration-ref refs/heads/master
  python3 - "$queue" <<'PY'
import json, sys
path = sys.argv[1]
entries = json.load(open(path, encoding="utf-8"))
entries[0].pop("integration_ref", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(entries, handle, indent=2)
    handle.write("\n")
PY
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "update-ref" ] && [ "${4:-}" = "--stdin" ]; then
  echo "simulated deletion pause after legacy upgrade" >&2
  exit 1
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_GIT="$real_git" \
    bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "simulated branch deletion failure should preserve the upgraded queue"
  elif ! python3 - "$queue" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["integration_ref"] == "refs/heads/master", entries
PY
  then
    _fail "legacy queue did not durably prefer the checked-out master ref"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "master-bound legacy cleanup should recover on retry"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$target" \
    || [ -f "$queue" ]; then
    _fail "recovered legacy master cleanup did not finish"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_prepared_master_ref_promotes_with_stale_main() {
  start_test "C26 prepared cleanup promotes against its recorded master ref"
  fixture_setup
  fixture_create_work "work-026" "master-prepared" 4 >/dev/null
  local work_wt work_branch module_meta queue
  work_wt="$FIXTURE_DIR/.worktrees/build-work-026-master-prepared"
  work_branch="build-work-026-master-prepared"
  module_meta="docs/modules/$work_branch/.work-meta.json"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  python3 - "$work_wt/$module_meta" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["build"]["lifecycle_state"] = "landed"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2)
    handle.write("\n")
PY
  git -C "$work_wt" add -- "$module_meta"
  git -C "$work_wt" commit -q -m "mark master target landed"
  git -C "$FIXTURE_DIR" switch -q -c master
  git -C "$FIXTURE_DIR" merge -q --ff-only "$work_branch"
  python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind work --branch "$work_branch" \
    --worktree "$work_wt" --work-dir "docs/modules/$work_branch" \
    --activation main_meta_landed --module-meta "$module_meta" \
    --integration-ref refs/heads/master

  if git -C "$FIXTURE_DIR" merge-base --is-ancestor "$work_branch" main; then
    _fail "fixture main unexpectedly contains the prepared master target"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "prepared master cleanup should promote and complete"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif [ -d "$work_wt" ] \
    || git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ -f "$queue" ]; then
    _fail "prepared cleanup consulted stale main instead of recorded master"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_preamble_consumes_pending_cleanup_from_master() {
  start_test "C27 master preamble automatically consumes its pending cleanup"
  fixture_setup
  fixture_create_work "work-027" "master-preamble" 4 >/dev/null
  local work_wt work_branch queue out
  work_wt="$FIXTURE_DIR/.worktrees/build-work-027-master-preamble"
  work_branch="build-work-027-master-preamble"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  git -C "$FIXTURE_DIR" switch -q -c master
  git -C "$FIXTURE_DIR" merge -q --ff-only "$work_branch"
  _write_pending_work_entry "$work_branch" "$work_wt"

  if git -C "$FIXTURE_DIR" merge-base --is-ancestor "$work_branch" main; then
    _fail "fixture main unexpectedly contains the master-only preamble target"
  elif ! out=$(cd "$FIXTURE_DIR" && PMAI_HOME="$FRAMEWORK_ROOT" bash -c \
    'set -e; source "$PMAI_HOME/scripts/skill-preamble.sh"; echo CALLER_CONTINUED' 2>&1); then
    _fail "master preamble should consume cleanup without failing"
    echo "$out" >&2
  elif [ -d "$work_wt" ] \
    || git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ -f "$queue" ]; then
    _fail "master preamble left the queued worktree, branch, or entry"
  elif ! printf '%s\n' "$out" | grep -q "CALLER_CONTINUED"; then
    _fail "master preamble cleanup did not return control to the caller"
  else
    pass_test
  fi

  fixture_teardown
}

test_active_landed_cleanup_rechecks_integration_truth() {
  start_test "C28 active landed cleanup stops after the integration ref is reset"
  fixture_setup
  local base work_wt work_branch module_meta queue transaction_id
  base=$(git -C "$FIXTURE_DIR" rev-parse main)
  fixture_create_work "work-028" "land-reset" 4 >/dev/null
  work_wt="$FIXTURE_DIR/.worktrees/build-work-028-land-reset"
  work_branch="build-work-028-land-reset"
  module_meta="docs/modules/$work_branch/.work-meta.json"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  python3 - "$work_wt/$module_meta" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["build"]["lifecycle_state"] = "landed"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2)
    handle.write("\n")
PY
  git -C "$work_wt" add -- "$module_meta"
  git -C "$work_wt" commit -q -m "mark reset target landed"
  git -C "$FIXTURE_DIR" merge -q --ff-only "$work_branch"
  transaction_id=$(python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind work --branch "$work_branch" \
    --worktree "$work_wt" --work-dir "docs/modules/$work_branch" \
    --activation main_meta_landed --module-meta "$module_meta" \
    --integration-ref refs/heads/main)
  python3 "$PENDING_QUEUE_HELPER" activate --file "$queue" \
    --branch "$work_branch" --transaction-id "$transaction_id"
  git -C "$FIXTURE_DIR" reset -q --hard "$base"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should stop when the landed branch is no longer in recorded main"
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$queue" ]; then
    _fail "integration reset should preserve the worktree, branch, and cleanup entry"
  elif ! grep -q "no longer holds" /tmp/out.$$; then
    _fail "cleanup did not explain that the recorded land condition regressed"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_prepared_landed_cleanup_uses_recorded_oid_after_branch_moves() {
  start_test "C29 prepared land promotion uses the recorded OID after branch movement"
  fixture_setup
  fixture_create_work "work-029" "prepared-move" 4 >/dev/null
  local work_wt work_branch module_meta queue
  work_wt="$FIXTURE_DIR/.worktrees/build-work-029-prepared-move"
  work_branch="build-work-029-prepared-move"
  module_meta="docs/modules/$work_branch/.work-meta.json"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  python3 - "$work_wt/$module_meta" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["build"]["lifecycle_state"] = "landed"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle, indent=2)
    handle.write("\n")
PY
  git -C "$work_wt" add -- "$module_meta"
  git -C "$work_wt" commit -q -m "mark moved target landed"
  git -C "$FIXTURE_DIR" merge -q --ff-only "$work_branch"
  python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind work --branch "$work_branch" \
    --worktree "$work_wt" --work-dir "docs/modules/$work_branch" \
    --activation main_meta_landed --module-meta "$module_meta" \
    --integration-ref refs/heads/main
  printf '%s\n' "new unlanded branch tip" > "$work_wt/unlanded-after-prepare.txt"
  git -C "$work_wt" add unlanded-after-prepare.txt
  git -C "$work_wt" commit -q -m "move branch after cleanup prepare"

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup should preserve a branch that moved after its identity was recorded"
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || ! python3 - "$queue" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "active", entries
PY
  then
    _fail "recorded landed OID was not promoted before the moved-ref safety check"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_missing_branch_keeps_original_land_evidence_after_main_reset() {
  start_test "C30 missing branch cannot erase failed original land evidence"
  fixture_setup
  local base target module_meta queue
  base=$(git -C "$FIXTURE_DIR" rev-parse main)
  target="build-missing-land-evidence"
  module_meta="docs/modules/missing-land-evidence/.work-meta.json"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  git -C "$FIXTURE_DIR" switch -q -c "$target"
  printf '%s\n' "land evidence" > "$FIXTURE_DIR/land-evidence.txt"
  git -C "$FIXTURE_DIR" add land-evidence.txt
  git -C "$FIXTURE_DIR" commit -q -m "create land evidence"
  git -C "$FIXTURE_DIR" switch -q main
  git -C "$FIXTURE_DIR" merge -q --ff-only "$target"
  python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind branch --branch "$target" \
    --worktree "" --work-dir "docs/modules/missing-land-evidence" \
    --activation main_meta_landed --module-meta "$module_meta" \
    --integration-ref refs/heads/main
  git -C "$FIXTURE_DIR" update-ref -d "refs/heads/$target"
  git -C "$FIXTURE_DIR" reset -q --hard "$base"

  if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "unsatisfied prepared land evidence should wait without making cleanup fatal"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  elif [ ! -f "$queue" ]; then
    _fail "missing branch plus reset main incorrectly erased the original land evidence"
  elif ! python3 - "$queue" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "prepared", entries
assert entries[0]["branch_oid"], entries
PY
  then
    _fail "original landed OID evidence was not retained in the prepared queue"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_prepared_transactions_are_exclusive_and_cas_bound() {
  start_test "C31 prepared cleanup uses exclusive branch+transaction CAS"
  fixture_setup
  fixture_create_work "work-031" "transaction-cas" 4 >/dev/null
  local work_wt work_branch module_meta queue transaction_id next_id wrong_id
  work_wt="$FIXTURE_DIR/.worktrees/build-work-031-transaction-cas"
  work_branch="build-work-031-transaction-cas"
  module_meta="docs/modules/transaction-cas/.work-meta.json"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"

  transaction_id=$(python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind work --branch "$work_branch" \
    --worktree "$work_wt" --work-dir "docs/modules/transaction-cas" \
    --activation main_meta_absent --module-meta "$module_meta" \
    --integration-ref refs/heads/main)
  wrong_id="00000000000000000000000000000000"
  if [ "$transaction_id" = "$wrong_id" ]; then
    wrong_id="11111111111111111111111111111111"
  fi

  if [[ ! "$transaction_id" =~ ^[0-9a-f]{32}$ ]]; then
    _fail "prepare did not return a stable transaction identity"
  elif python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind work --branch "$work_branch" \
    --worktree "$work_wt" --work-dir "docs/modules/transaction-cas" \
    --activation main_meta_absent --module-meta "$module_meta" \
    --integration-ref refs/heads/main >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "a second prepare overwrote an existing branch transaction"
  elif python3 "$PENDING_QUEUE_HELPER" activate --file "$queue" \
    --branch "$work_branch" --transaction-id "$wrong_id" \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "activate accepted a stale transaction identity"
  elif python3 "$PENDING_QUEUE_HELPER" remove --file "$queue" \
    --branch "$work_branch" --transaction-id "$wrong_id" \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "remove accepted a stale transaction identity"
  elif ! python3 - "$queue" "$transaction_id" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "prepared", entries
assert entries[0]["transaction_id"] == sys.argv[2], entries
PY
  then
    _fail "a failed CAS mutated the original prepared transaction"
  elif ! python3 "$PENDING_QUEUE_HELPER" remove --file "$queue" \
    --branch "$work_branch" --transaction-id "$transaction_id"; then
    _fail "the owning transaction could not remove its prepared intent"
  else
    next_id=$(python3 "$PENDING_QUEUE_HELPER" prepare \
      --file "$queue" --kind work --branch "$work_branch" \
      --worktree "$work_wt" --work-dir "docs/modules/transaction-cas" \
      --activation main_meta_absent --module-meta "$module_meta" \
      --integration-ref refs/heads/main)
    if [ "$next_id" = "$transaction_id" ]; then
      _fail "separate prepares reused the same transaction identity"
    elif ! python3 "$PENDING_QUEUE_HELPER" activate --file "$queue" \
      --branch "$work_branch" --transaction-id "$next_id"; then
      _fail "the owning transaction could not activate its prepared intent"
    elif python3 "$PENDING_QUEUE_HELPER" remove --file "$queue" \
      --branch "$work_branch" --transaction-id "$next_id" \
      >/tmp/out.$$ 2>/tmp/err.$$; then
      _fail "rollback removed an already active cleanup transaction"
    elif ! python3 - "$queue" "$next_id" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "active", entries
assert entries[0]["transaction_id"] == sys.argv[2], entries
PY
    then
      _fail "activation did not retain the exact transaction identity"
    else
      pass_test
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_integration_reset_cannot_race_atomic_branch_delete() {
  start_test "C32 integration reset cannot race the atomic build-ref delete"
  fixture_setup
  local base target landed_oid queue fake_bin real_git
  base=$(git -C "$FIXTURE_DIR" rev-parse main)
  target="build-integration-cas"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  fake_bin="$FIXTURE_DIR/fakebin"
  real_git=$(command -v git)
  git -C "$FIXTURE_DIR" switch -q -c "$target"
  printf '%s\n' "atomic integration evidence" > "$FIXTURE_DIR/integration-cas.txt"
  git -C "$FIXTURE_DIR" add integration-cas.txt
  git -C "$FIXTURE_DIR" commit -q -m "create atomic integration evidence"
  git -C "$FIXTURE_DIR" switch -q main
  git -C "$FIXTURE_DIR" merge -q --ff-only "$target"
  landed_oid=$(git -C "$FIXTURE_DIR" rev-parse main)
  python3 "$PENDING_QUEUE_HELPER" enqueue \
    --file "$queue" --kind branch --branch "$target" \
    --worktree "" --work-dir "docs/modules/integration-cas" \
    --integration-ref refs/heads/main
  mkdir -p "$fake_bin"
  cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "update-ref" ] && [ "${4:-}" = "--stdin" ]; then
  "$PMAI_TEST_REAL_GIT" -C "$PMAI_TEST_REPO" update-ref refs/heads/main \
    "$PMAI_TEST_BASE" "$PMAI_TEST_LANDED" || exit $?
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
  chmod +x "$fake_bin/git"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" \
    PMAI_TEST_REAL_GIT="$real_git" PMAI_TEST_REPO="$FIXTURE_DIR" \
    PMAI_TEST_BASE="$base" PMAI_TEST_LANDED="$landed_oid" \
    bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cleanup ignored an integration ref reset at deletion time"
  elif [ "$(git -C "$FIXTURE_DIR" rev-parse main)" != "$base" ]; then
    _fail "fixture did not move main between validation and deletion"
  elif ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$target" \
    || [ ! -f "$queue" ]; then
    _fail "atomic verification did not preserve the only stable build ref"
  else
    git -C "$FIXTURE_DIR" update-ref refs/heads/main "$landed_oid" "$base"
    if ! (cd "$FIXTURE_DIR" && bash "$CLEANUP") \
      >/tmp/out.$$ 2>/tmp/err.$$; then
      _fail "cleanup did not recover after the exact integration ref returned"
      cat /tmp/out.$$ /tmp/err.$$ >&2
    elif git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$target" \
      || [ -f "$queue" ]; then
      _fail "recovered atomic cleanup left the branch or queue entry"
    else
      pass_test
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_legacy_prepared_entry_without_transaction_fails_closed() {
  start_test "C33 legacy prepared entry without transaction identity fails closed"
  fixture_setup
  fixture_create_work "work-033" "legacy-prepared" 4 >/dev/null
  local work_wt work_branch module_meta queue
  work_wt="$FIXTURE_DIR/.worktrees/build-work-033-legacy-prepared"
  work_branch="build-work-033-legacy-prepared"
  module_meta="docs/modules/legacy-prepared/.work-meta.json"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  python3 "$PENDING_QUEUE_HELPER" prepare \
    --file "$queue" --kind work --branch "$work_branch" \
    --worktree "$work_wt" --work-dir "docs/modules/legacy-prepared" \
    --activation main_meta_absent --module-meta "$module_meta" \
    --integration-ref refs/heads/main >/dev/null
  python3 - "$queue" <<'PY'
import json, sys
path = sys.argv[1]
entries = json.load(open(path, encoding="utf-8"))
entries[0].pop("transaction_id")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(entries, handle, indent=2)
    handle.write("\n")
PY

  if (cd "$FIXTURE_DIR" && bash "$CLEANUP") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "legacy prepared cleanup without a transaction identity was accepted"
  elif [ ! -d "$work_wt" ] \
    || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$work_branch" \
    || [ ! -f "$queue" ]; then
    _fail "legacy prepared cleanup mutated work despite missing transaction identity"
  elif ! grep -q "事务身份" /tmp/out.$$; then
    _fail "legacy prepared rejection did not explain the missing transaction identity"
    cat /tmp/out.$$ /tmp/err.$$ >&2
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
test_enqueue_missing_branch_records_empty_identity
test_enqueue_git_query_error_preserves_queue
test_rejects_unregistered_existing_worktree_path
test_rejects_unregistered_missing_worktree_for_live_branch
test_rejects_unmerged_branch_only_cleanup
test_work_cleanup_recovers_after_branch_delete_failure
test_legacy_work_cleanup_persists_oid_before_interrupted_remove
test_branch_only_uses_main_when_current_feature_contains_unmerged_target
test_branch_only_can_delete_main_merged_target_from_older_feature
test_queue_stage_namespace_does_not_overlap_preamble_markers
test_rejects_corrupt_pending_file
test_preamble_consumes_pending_cleanup_from_main
test_preamble_defers_cleanup_inside_build_worktree
test_preamble_cleanup_failure_is_nonblocking
test_cleanup_defers_while_another_process_uses_worktree
test_dirty_worktree_is_preserved
test_ignored_worktree_files_are_preserved
test_read_only_preamble_preserves_cleanup_queue
test_read_only_preamble_preserves_interrupt_markers
test_preamble_treats_pending_json_as_data
test_status_skill_opts_into_read_only_preamble
test_concurrent_enqueue_survives_cleanup
test_git_worktree_query_error_preserves_queue
test_git_show_ref_error_preserves_queue
test_prepared_cleanup_promotes_durably_after_cancel_commit
test_branch_delete_cas_preserves_concurrently_moved_ref
test_recorded_master_ref_ignores_stale_main
test_legacy_entry_prefers_checked_out_master_over_stale_main
test_prepared_master_ref_promotes_with_stale_main
test_preamble_consumes_pending_cleanup_from_master
test_active_landed_cleanup_rechecks_integration_truth
test_prepared_landed_cleanup_uses_recorded_oid_after_branch_moves
test_missing_branch_keeps_original_land_evidence_after_main_reset
test_prepared_transactions_are_exclusive_and_cas_bound
test_integration_reset_cannot_race_atomic_branch_delete
test_legacy_prepared_entry_without_transaction_fails_closed

report_results "cleanup-pending"
