#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
CLOSE="$FRAMEWORK_ROOT/scripts/close-work.sh"
CLEANUP="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"
IMPACT="$FRAMEWORK_ROOT/scripts/doc-impact.py"
CONTEXT_PACK="$FRAMEWORK_ROOT/scripts/context-pack.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-land-v2.XXXXXX")
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  mkdir -p "$T/docs/modules/access" "$T/src" "$T/.worktrees" "$T/.pm-workflow"
  echo '# product' > "$T/PRODUCT.md"
  echo '# state' > "$T/PRODUCT-STATE.md"
  echo '# rules' > "$T/PRODUCT-RULES.md"
  echo '# design' > "$T/DESIGN.md"
  echo '# todo' > "$T/TODO.md"
  echo '# modules' > "$T/docs/modules/INDEX.md"
  echo '# access spec' > "$T/docs/modules/access/spec.md"
  echo '# discussion' > "$T/docs/modules/access/discussion.md"
  echo '# decisions' > "$T/docs/modules/access/decisions.md"
  cat > "$T/docs/modules/access/.work-meta.json" <<'JSON'
{"id":"work-access","name":"access","branch":"build-access","stage":1,"status":"active","lifecycle_state":"designing"}
JSON
  printf '.worktrees/\n.pm-workflow/context/\n.runs/\n' > "$T/.gitignore"
  python3 "$PROJECT_DEFINITION" write "$T" \
    --source docs/modules/access/spec.md --type product \
    --root src --entrypoint src/access \
    --language typescript --runtime node --framework test --package-manager none >/dev/null
  git -C "$T" add -A && git -C "$T" commit -q -m 'design basis'
  PACK="$T/.pm-workflow/context/access.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$T/docs/modules/access" --output "$PACK" >/dev/null
  SOURCE_HASH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$PACK")
  CHECKPOINT=$(git -C "$T" rev-parse HEAD)
  python3 "$CONTRACT" ready "$T/docs/modules/access" \
    --approved-source-hash "$SOURCE_HASH" --checkpoint-commit "$CHECKPOINT" \
    --context-pack "$PACK" --target-path src/access --design-revision 1 >/dev/null
  git -C "$T" add -- docs/modules/access/.work-meta.json
  git -C "$T" commit -q -m 'mark access ready'
  BASE=$(git -C "$T" rev-parse HEAD)
  git -C "$T" worktree add -q -b build-access "$T/.worktrees/build-access" main
  WT="$T/.worktrees/build-access"
  MODULE="$WT/docs/modules/access"
  python3 "$CONTRACT" start "$MODULE" --anchor docs/modules/access/spec.md \
    --mode worktree --executor codex --branch build-access --worktree .worktrees/build-access \
    --baseline-sha "$BASE" --target-kind product --target-path src/access --entrypoint src/access \
    --approved-source-hash "$SOURCE_HASH" --required-check tests >/dev/null
  git -C "$WT" add -A && git -C "$WT" commit -q -m 'start build contract'
  mkdir -p "$WT/src/access"
  echo 'export const access = true' > "$WT/src/access/index.ts"
  git -C "$WT" add -A && git -C "$WT" commit -q -m 'build(access): implementation'
  IMPL=$(git -C "$WT" rev-parse HEAD)
  python3 "$CONTRACT" commit "$MODULE" --implementation-commit "$IMPL" >/dev/null
  python3 "$CONTRACT" request-finalization "$MODULE" >/dev/null
  python3 "$CONTRACT" record-evidence "$MODULE" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit "$IMPL" >/dev/null
  python3 "$CONTRACT" review-ready "$MODULE" >/dev/null
  python3 "$CONTRACT" accept "$MODULE" >/dev/null
}

teardown_fixture() {
  git -C "$T" worktree remove "$WT" --force >/dev/null 2>&1 || true
  rm -rf "$T"
}

cover_map() {
  local map="$1"
  IDS=()
  while IFS= read -r id; do [ -n "$id" ] && IDS[${#IDS[@]}]="$id"; done < <(
    python3 - "$map" <<'PY'
import json,sys
for item in json.load(open(sys.argv[1]))["items"]: print(item["id"])
PY
  )
  for id in "${IDS[@]}"; do
    python3 "$IMPACT" cover "$map" --item "$id" --status no-change --note "已核对当前事实，无需改动" >/dev/null
  done
}

test_land_then_document_then_complete() {
  start_test "land v2: final_check → merge → documenting → docs commit → complete"
  setup_fixture
  if ! (cd "$T" && bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "v2 landing should succeed"
    cat /tmp/land-v2.err.$$ >&2
    teardown_fixture; return
  fi
  MAIN_MODULE="$T/docs/modules/access"
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  if [ ! -f "$T/src/access/index.ts" ] || [ ! -f "$MAIN_MODULE/.work-meta.json" ] || [ ! -f "$MAP" ]; then
    _fail "implementation, landed meta and doc map should exist on main"
    teardown_fixture; return
  fi
  state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MAIN_MODULE/.work-meta.json")
  if [ "$state" != "documenting" ]; then
    _fail "state should be documenting after landing"
    teardown_fixture; return
  elif [ ! -d "$WT" ] \
    || ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
    _fail "landing should leave the worktree and branch for safe cleanup"
    teardown_fixture; return
  elif ! python3 - "$T/.runs/pending-cleanup.json" <<'PY'
import json, re, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "active", entries
assert entries[0]["integration_ref"] == "refs/heads/main", entries
assert re.fullmatch(r"[0-9a-f]{32}", entries[0]["transaction_id"]), entries
PY
  then
    _fail "landing should persist one active cleanup bound to main"
    teardown_fixture; return
  elif ! (cd "$T" && bash "$CLEANUP") \
    >/tmp/land-v2.cleanup.$$ 2>/tmp/land-v2.cleanup.err.$$; then
    _fail "explicit cleanup should remove the landed isolation environment"
    cat /tmp/land-v2.cleanup.$$ /tmp/land-v2.cleanup.err.$$ >&2
    teardown_fixture; return
  elif [ -d "$WT" ] \
    || git -C "$T" show-ref --verify --quiet refs/heads/build-access \
    || [ -f "$T/.runs/pending-cleanup.json" ]; then
    _fail "cleanup should remove the exact worktree, branch, and queue entry"
    teardown_fixture; return
  fi
  cover_map "$MAP"
  python3 "$CONTRACT" docs-complete "$MAIN_MODULE" >/dev/null
  if ! (cd "$T" && bash "$CLOSE" "$MAIN_MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "post-land docs completion should succeed"
    cat /tmp/land-v2.err.$$ >&2
  elif [ -f "$MAIN_MODULE/.work-meta.json" ]; then
    _fail "complete should remove transient work meta"
  elif ! git -C "$T" log -1 --format=%s | grep -q 'docs(access): sync landed product truth'; then
    _fail "final commit should be the separate documentation commit"
  elif ! git -C "$T" show HEAD:.pm-workflow/audits/access/doc-impact.json >/dev/null 2>&1; then
    _fail "final documentation commit should include doc-impact.json"
  elif ! python3 - "$T/.pm-workflow/audits/access/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
phases = {item["phase"]: item["status"] for item in entries}
assert phases["landing"] == "pass"
assert phases["documentation"] == "pass"
PY
  then
    _fail "timing ledger should include completed landing and documentation"
  elif [ -n "$(git -C "$T" status --short --untracked-files=all)" ]; then
    _fail "completed landing should leave the fixture clean"
  else
    pass_test
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$ \
    /tmp/land-v2.cleanup.$$ /tmp/land-v2.cleanup.err.$$
  teardown_fixture
}

test_merge_conflict_keeps_final_check_and_worktree() {
  start_test "land v2: merge conflict keeps final_check and worktree for retry"
  setup_fixture
  echo 'branch value' > "$WT/src/access/conflict.txt"
  git -C "$WT" add src/access/conflict.txt && git -C "$WT" commit -q -m 'branch conflict'
  NEW_IMPL=$(git -C "$WT" rev-parse HEAD)
  python3 "$CONTRACT" iterating "$MODULE" >/dev/null
  python3 "$CONTRACT" commit "$MODULE" --implementation-commit "$NEW_IMPL" >/dev/null
  python3 "$CONTRACT" record-evidence "$MODULE" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit "$NEW_IMPL" >/dev/null
  python3 "$CONTRACT" review-ready "$MODULE" >/dev/null
  python3 "$CONTRACT" accept "$MODULE" >/dev/null
  mkdir -p "$T/src/access"
  echo 'main value' > "$T/src/access/conflict.txt"
  git -C "$T" add src/access/conflict.txt && git -C "$T" commit -q -m 'main conflict'
  if (cd "$T" && bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "conflicting merge should fail"
  else
    state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MODULE/.work-meta.json")
    if [ "$state" != "final_check" ]; then
      _fail "conflict should keep final_check"
    elif [ ! -d "$WT" ] || ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
      _fail "conflict should keep worktree and branch"
    elif git -C "$T" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
      _fail "merge should be aborted cleanly"
    elif ! python3 - "$WT/.pm-workflow/audits/access/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
assert any(item["phase"] == "landing" and item["status"] == "fail" and item["reason"] == "merge conflict" for item in entries)
PY
    then
      _fail "merge conflict should exit the normal-path timing ledger"
    else
      pass_test
    fi
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
  teardown_fixture
}

test_landed_docs_collision_preserves_wip_and_skips_remerge() {
  start_test "land v2: landed docs collision preserves WIP and resumes without remerge"
  setup_fixture
  python3 "$IMPACT" init "$MODULE" --repo-root "$WT" --base "$BASE" --head "$IMPL" \
    --output "$WT/.pm-workflow/audits/access/doc-impact.json" >/dev/null
  git -C "$WT" add .pm-workflow/audits/access/doc-impact.json
  git -C "$WT" commit -q -m 'build(access): prepare documentation impact draft'
  echo 'user docs wip' >> "$T/PRODUCT-STATE.md"
  if (cd "$T" && bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "pre-existing dirty documentation destination should stop docs phase"
    teardown_fixture; return
  fi
  MAIN_MODULE="$T/docs/modules/access"
  state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MAIN_MODULE/.work-meta.json")
  docs=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["docs_status"])' "$MAIN_MODULE/.work-meta.json")
  if [ "$state" != "landed" ] || [ "$docs" != "pending" ]; then
    _fail "collision should remain landed/docs_pending"
    teardown_fixture; return
  elif ! grep -q 'user docs wip' "$T/PRODUCT-STATE.md"; then
    _fail "existing docs WIP should be preserved"
    teardown_fixture; return
  elif ! python3 - "$T/.pm-workflow/audits/access/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
assert any(item["phase"] == "documentation" and item["status"] == "fail" for item in entries)
PY
  then
    _fail "documentation collision should exit the normal-path timing ledger"
    teardown_fixture; return
  fi
  first_land_count=$(git -C "$T" log --format=%s | grep -c 'build(access): land accepted implementation')
  first_acceptance_count=$(git -C "$T" log --format=%s | grep -c 'build(access): record final acceptance')
  git -C "$T" restore PRODUCT-STATE.md
  if ! (cd "$T" && bash "$CLOSE" "$MAIN_MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "retry should resume documentation"
    cat /tmp/land-v2.err.$$ >&2
  else
    second_land_count=$(git -C "$T" log --format=%s | grep -c 'build(access): land accepted implementation')
    second_acceptance_count=$(git -C "$T" log --format=%s | grep -c 'build(access): record final acceptance')
    state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MAIN_MODULE/.work-meta.json")
    if [ "$state" != "documenting" ] || \
       [ "$first_land_count" != "$second_land_count" ] || \
       [ "$first_acceptance_count" != "$second_acceptance_count" ]; then
      _fail "retry should enter documenting without another acceptance or merge commit"
    else
      pass_test
    fi
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
  teardown_fixture
}

test_land_queues_cleanup_without_blocking_docs() {
  start_test "land v2: landing always queues safe cleanup without blocking docs"
  setup_fixture
  if ! (cd "$T" && bash "$CLOSE" "$MODULE") \
    >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "safe cleanup queueing should not block landing or docs start"
    cat /tmp/land-v2.err.$$ >&2
    teardown_fixture; return
  fi
  MAIN_MODULE="$T/docs/modules/access"
  state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MAIN_MODULE/.work-meta.json")
  if [ "$state" != "documenting" ]; then
    _fail "queued cleanup should still reach documenting"
  elif [ ! -d "$WT" ] \
    || ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
    _fail "landing should not directly delete its worktree or branch"
  elif [ ! -f "$T/src/access/index.ts" ]; then
    _fail "implementation should be landed before cleanup is queued"
  elif ! python3 - "$T/.runs/pending-cleanup.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["kind"] == "work", entries
assert entries[0]["phase"] == "active", entries
assert entries[0]["integration_ref"] == "refs/heads/main", entries
PY
  then
    _fail "landing did not persist the active main-bound cleanup intent"
  else
    pass_test
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
  teardown_fixture
}

test_branch_cleanup_failure_retries_after_worktree_removal() {
  start_test "land v2: CAS branch failure preserves the original cleanup entry"
  setup_fixture
  REAL_GIT=$(command -v git)
  mkdir -p "$T/fakebin"
  cat > "$T/fakebin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "update-ref" ] && [ "${4:-}" = "--stdin" ]; then
  echo "simulated branch cleanup failure" >&2
  exit 1
fi
exec "$REAL_GIT_FOR_TEST" "$@"
SH
  chmod +x "$T/fakebin/git"

  if ! (cd "$T" && bash "$CLOSE" "$MODULE") \
      >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "landing should succeed before the deferred cleanup attempt"
    cat /tmp/land-v2.err.$$ >&2
    teardown_fixture; return
  elif [ ! -d "$WT" ]; then
    _fail "landing directly removed the worktree instead of deferring cleanup"
    teardown_fixture; return
  fi

  if (cd "$T" && PATH="$T/fakebin:$PATH" REAL_GIT_FOR_TEST="$REAL_GIT" \
      bash "$CLEANUP") >/tmp/land-v2.cleanup.$$ 2>/tmp/land-v2.cleanup.err.$$; then
    _fail "simulated CAS deletion failure should keep a retry"
    teardown_fixture; return
  elif [ -d "$WT" ]; then
    _fail "cleanup should remove the worktree before the branch CAS failure"
    teardown_fixture; return
  elif ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
    _fail "failed branch cleanup should preserve the branch for retry"
    teardown_fixture; return
  elif ! python3 - "$T/.runs/pending-cleanup.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["kind"] == "work", entries
assert entries[0]["branch"] == "build-access", entries
assert entries[0]["worktree"], entries
assert entries[0]["branch_oid"], entries
assert entries[0]["integration_ref"] == "refs/heads/main", entries
PY
  then
    _fail "branch cleanup failure should preserve the original stable work entry"
    teardown_fixture; return
  fi

  if ! (cd "$T" && bash "$CLEANUP") \
      >/tmp/land-v2.cleanup.$$ 2>/tmp/land-v2.cleanup.err.$$; then
    _fail "identity-matched branch cleanup should succeed on retry"
    cat /tmp/land-v2.cleanup.err.$$ >&2
  elif git -C "$T" show-ref --verify --quiet refs/heads/build-access \
    || [ -f "$T/.runs/pending-cleanup.json" ]; then
    _fail "successful retry should remove the merged branch and queue entry"
  else
    pass_test
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$ \
    /tmp/land-v2.cleanup.$$ /tmp/land-v2.cleanup.err.$$
  teardown_fixture
}

test_land_from_worktree_cwd_defers_cleanup() {
  start_test "land v2: invocation from build cwd never leaves a dangling cwd"
  setup_fixture

  if ! (cd "$WT" && bash "$CLOSE" "$MODULE") \
    >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "landing from the build worktree cwd should succeed"
    cat /tmp/land-v2.err.$$ >&2
  elif [ ! -d "$WT" ] \
    || ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
    _fail "landing from build cwd deleted the caller's worktree or branch"
  elif ! python3 - "$T/.runs/pending-cleanup.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "active", entries
assert entries[0]["integration_ref"] == "refs/heads/main", entries
PY
  then
    _fail "landing from build cwd did not leave a safe active cleanup intent"
  else
    pass_test
  fi

  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
  teardown_fixture
}

test_landed_cleanup_waits_for_worktree_holder() {
  start_test "land v2: cleanup waits until another worktree cwd holder exits"
  setup_fixture
  local holder
  (cd "$WT" && exec sleep 30) &
  holder=$!
  sleep 1

  if ! (cd "$T" && bash "$CLOSE" "$MODULE") \
    >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "an external cwd holder should not block landing"
    cat /tmp/land-v2.err.$$ >&2
  elif (cd "$T" && bash "$CLEANUP") \
    >/tmp/land-v2.cleanup.$$ 2>/tmp/land-v2.cleanup.err.$$; then
    _fail "cleanup should defer while another process uses the landed worktree"
  elif [ ! -d "$WT" ] \
    || ! git -C "$T" show-ref --verify --quiet refs/heads/build-access \
    || [ ! -f "$T/.runs/pending-cleanup.json" ]; then
    _fail "busy worktree, branch, and queue entry should all be preserved"
  else
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    holder=""
    if ! (cd "$T" && bash "$CLEANUP") \
      >/tmp/land-v2.cleanup.$$ 2>/tmp/land-v2.cleanup.err.$$; then
      _fail "cleanup should recover after the cwd holder exits"
      cat /tmp/land-v2.cleanup.$$ /tmp/land-v2.cleanup.err.$$ >&2
    elif [ -d "$WT" ] \
      || git -C "$T" show-ref --verify --quiet refs/heads/build-access \
      || [ -f "$T/.runs/pending-cleanup.json" ]; then
      _fail "recovered cleanup left the worktree, branch, or queue entry"
    else
      pass_test
    fi
  fi

  if [ -n "${holder:-}" ]; then
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$ \
    /tmp/land-v2.cleanup.$$ /tmp/land-v2.cleanup.err.$$
  teardown_fixture
}

test_landing_commit_failure_rolls_back_and_retries_once() {
  start_test "land v2: main commit failure rolls back and retry does not duplicate landing"
  setup_fixture
  REAL_GIT=$(command -v git)
  mkdir -p "$T/fakebin"
  cat > "$T/fakebin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "commit" ] && [[ "$*" == *"land accepted implementation"* ]]; then
  echo "simulated main landing commit failure" >&2
  exit 1
fi
exec "$REAL_GIT_FOR_TEST" "$@"
SH
  chmod +x "$T/fakebin/git"
  BEFORE=$(git -C "$T" rev-parse HEAD)

  if (cd "$T" && PATH="$T/fakebin:$PATH" REAL_GIT_FOR_TEST="$REAL_GIT" \
      bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "simulated main commit failure should stop landing"
    teardown_fixture; return
  fi
  AFTER=$(git -C "$T" rev-parse HEAD)
  acceptance_count=$(git -C "$WT" log --format=%s | grep -c 'build(access): record final acceptance')
  state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MODULE/.work-meta.json")
  if [ "$BEFORE" != "$AFTER" ]; then
    _fail "failed landing commit should restore the original main HEAD"
  elif git -C "$T" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    _fail "failed landing commit should abort the pending merge"
  elif [ "$state" != "final_check" ] || [ ! -d "$WT" ] || [ "$acceptance_count" != "1" ]; then
    _fail "failed landing should preserve one accepted build and its worktree"
  elif ! (cd "$T" && bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "landing should recover on retry"
    cat /tmp/land-v2.err.$$ >&2
  else
    land_count=$(git -C "$T" log --format=%s | grep -c 'build(access): land accepted implementation')
    acceptance_count=$(git -C "$T" log --format=%s | grep -c 'build(access): record final acceptance')
    if [ "$land_count" != "1" ] || [ "$acceptance_count" != "1" ]; then
      _fail "retry should produce exactly one acceptance commit and one landing commit"
    else
      pass_test
    fi
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
  teardown_fixture
}

test_untracked_incoming_path_fails_before_merge() {
  start_test "land v2: incoming path colliding with main untracked file fails before merge"
  setup_fixture
  mkdir -p "$T/src/access"
  echo 'main untracked work' > "$T/src/access/index.ts"
  local before after state
  before=$(git -C "$T" rev-parse HEAD)
  if (cd "$T" && bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "untracked incoming collision should stop landing"
  else
    after=$(git -C "$T" rev-parse HEAD)
    state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MODULE/.work-meta.json")
    if [ "$before" != "$after" ]; then
      _fail "preflight collision must happen before any main commit"
    elif [ "$state" != "final_check" ]; then
      _fail "preflight collision should preserve final_check"
    elif ! grep -q "main untracked work" "$T/src/access/index.ts"; then
      _fail "main untracked file should be preserved"
    elif ! grep -q "merge 前发现" /tmp/land-v2.err.$$; then
      _fail "preflight collision guidance mismatch"
      cat /tmp/land-v2.err.$$ >&2
    elif ! python3 - "$WT/.pm-workflow/audits/access/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
assert any(item["phase"] == "landing" and item["status"] == "fail" and item["reason"] == "main untracked path collision" for item in entries)
PY
    then
      _fail "preflight collision should exit the normal-path timing ledger"
    else
      pass_test
    fi
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
  teardown_fixture
}

test_cleanup_prepare_failure_stops_before_merge() {
  start_test "land v2: cleanup prepare failure stops before main merge"
  setup_fixture
  local fake_bin real_python before after
  fake_bin="$T/fakebin"
  real_python=$(command -v python3)
  before=$(git -C "$T" rev-parse HEAD)
  mkdir -p "$fake_bin"
  cat > "$fake_bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == *"pending_cleanup.py" ]] && [ "${2:-}" = "prepare" ]; then
  echo "simulated cleanup prepare failure" >&2
  exit 1
fi
exec "$PMAI_TEST_REAL_PYTHON" "$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$T" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_PYTHON="$real_python" \
    bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "landing should stop when it cannot persist the cleanup intent"
  else
    after=$(git -C "$T" rev-parse HEAD)
    if [ "$before" != "$after" ]; then
      _fail "main changed before cleanup prepare succeeded"
    elif [ -f "$T/src/access/index.ts" ]; then
      _fail "implementation merged despite cleanup prepare failure"
    elif [ ! -d "$WT" ] \
      || ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
      _fail "prepare failure did not preserve the accepted worktree and branch"
    elif [ -f "$T/.runs/pending-cleanup.json" ]; then
      _fail "failed prepare left a partial cleanup record"
    elif ! (cd "$T" && bash "$CLOSE" "$MODULE") \
      >/tmp/land-v2.retry.$$ 2>/tmp/land-v2.retry.err.$$; then
      _fail "landing did not recover after the prepare writer returned"
      cat /tmp/land-v2.retry.err.$$ >&2
    else
      pass_test
    fi
  fi

  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$ \
    /tmp/land-v2.retry.$$ /tmp/land-v2.retry.err.$$
  teardown_fixture
}

test_cleanup_activation_interruption_recovers_from_landed_truth() {
  start_test "land v2: activation interruption recovers from landed main truth"
  setup_fixture
  local fake_bin real_python queue
  fake_bin="$T/fakebin"
  real_python=$(command -v python3)
  queue="$T/.runs/pending-cleanup.json"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == *"pending_cleanup.py" ]] && [ "${2:-}" = "activate" ]; then
  echo "simulated cleanup activation interruption" >&2
  exit 1
fi
exec "$PMAI_TEST_REAL_PYTHON" "$@"
SH
  chmod +x "$fake_bin/python3"

  if ! (cd "$T" && PATH="$fake_bin:$PATH" PMAI_TEST_REAL_PYTHON="$real_python" \
    bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "durable prepared cleanup should not block landed documentation"
    cat /tmp/land-v2.err.$$ >&2
  elif [ ! -f "$T/src/access/index.ts" ]; then
    _fail "implementation was not committed before activation interruption"
  elif [ ! -d "$WT" ] \
    || ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
    _fail "activation failure should skip immediate destructive cleanup"
  elif ! python3 - "$queue" <<'PY'
import json, re, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "prepared", entries
assert entries[0]["activation"] == "main_meta_landed", entries
assert entries[0]["integration_ref"] == "refs/heads/main", entries
assert re.fullmatch(r"[0-9a-f]{32}", entries[0]["transaction_id"]), entries
PY
  then
    _fail "activation interruption did not preserve the prepared record"
  elif ! grep -q "仍处于 prepared" /tmp/land-v2.err.$$; then
    _fail "activation failure was swallowed instead of being reported as recoverable"
  elif ! (cd "$T" && bash "$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh") \
    >/tmp/land-v2.cleanup.$$ 2>/tmp/land-v2.cleanup.err.$$; then
    _fail "main cleanup did not auto-promote the landed record"
    cat /tmp/land-v2.cleanup.$$ /tmp/land-v2.cleanup.err.$$ >&2
  elif [ -d "$WT" ] \
    || git -C "$T" show-ref --verify --quiet refs/heads/build-access \
    || [ -f "$queue" ]; then
    _fail "recovered landed cleanup left its worktree, branch, or queue entry"
  else
    pass_test
  fi

  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$ \
    /tmp/land-v2.cleanup.$$ /tmp/land-v2.cleanup.err.$$
  teardown_fixture
}

test_land_then_document_then_complete
test_merge_conflict_keeps_final_check_and_worktree
test_landed_docs_collision_preserves_wip_and_skips_remerge
test_land_queues_cleanup_without_blocking_docs
test_branch_cleanup_failure_retries_after_worktree_removal
test_land_from_worktree_cwd_defers_cleanup
test_landed_cleanup_waits_for_worktree_holder
test_landing_commit_failure_rolls_back_and_retries_once
test_untracked_incoming_path_fails_before_merge
test_cleanup_prepare_failure_stops_before_merge
test_cleanup_activation_interruption_recovers_from_landed_truth
report_results "land-work-v2"
