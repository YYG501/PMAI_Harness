#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
CLOSE="$FRAMEWORK_ROOT/scripts/close-work.sh"
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
  printf '.worktrees/\n.pm-workflow/context/\n' > "$T/.gitignore"
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
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
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

test_cleanup_failure_is_queued_without_blocking_docs() {
  start_test "land v2: worktree cleanup failure is queued and docs still start"
  setup_fixture
  REAL_GIT=$(command -v git)
  mkdir -p "$T/fakebin"
  cat > "$T/fakebin/git" <<'SH'
#!/usr/bin/env bash
if [ "${3:-}" = "worktree" ] && [ "${4:-}" = "remove" ]; then
  echo "simulated worktree cleanup failure" >&2
  exit 1
fi
exec "$REAL_GIT_FOR_TEST" "$@"
SH
  chmod +x "$T/fakebin/git"

  if ! (cd "$T" && PATH="$T/fakebin:$PATH" REAL_GIT_FOR_TEST="$REAL_GIT" bash "$CLOSE" "$MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "cleanup failure should not block landing or docs start"
    cat /tmp/land-v2.err.$$ >&2
    teardown_fixture; return
  fi
  MAIN_MODULE="$T/docs/modules/access"
  state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MAIN_MODULE/.work-meta.json")
  if [ "$state" != "documenting" ]; then
    _fail "cleanup failure should still reach documenting"
  elif [ ! -f "$T/.runs/pending-cleanup.json" ]; then
    _fail "cleanup failure should create a pending cleanup entry"
  elif ! git -C "$T" show-ref --verify --quiet refs/heads/build-access; then
    _fail "queued cleanup should preserve the merged branch for later cleanup"
  elif [ ! -f "$T/src/access/index.ts" ]; then
    _fail "implementation should already be landed before cleanup is queued"
  else
    pass_test
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
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

test_land_then_document_then_complete
test_merge_conflict_keeps_final_check_and_worktree
test_landed_docs_collision_preserves_wip_and_skips_remerge
test_cleanup_failure_is_queued_without_blocking_docs
test_landing_commit_failure_rolls_back_and_retries_once
test_untracked_incoming_path_fails_before_merge
report_results "land-work-v2"
