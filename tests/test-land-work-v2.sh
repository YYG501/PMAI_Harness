#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
CLOSE="$FRAMEWORK_ROOT/scripts/close-work.sh"
IMPACT="$FRAMEWORK_ROOT/scripts/doc-impact.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-land-v2.XXXXXX")
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  mkdir -p "$T/docs/modules" "$T/src" "$T/.worktrees" "$T/.pm-workflow"
  echo '# product' > "$T/PRODUCT.md"
  echo '# state' > "$T/PRODUCT-STATE.md"
  echo '# rules' > "$T/PRODUCT-RULES.md"
  echo '# design' > "$T/DESIGN.md"
  echo '# todo' > "$T/TODO.md"
  echo '# modules' > "$T/docs/modules/INDEX.md"
  echo '.worktrees/' > "$T/.gitignore"
  git -C "$T" add -A && git -C "$T" commit -q -m init
  BASE=$(git -C "$T" rev-parse HEAD)
  git -C "$T" worktree add -q -b build-access "$T/.worktrees/build-access" main
  WT="$T/.worktrees/build-access"
  MODULE="$WT/docs/modules/access"
  mkdir -p "$MODULE"
  echo '# access spec' > "$MODULE/spec.md"
  python3 "$CONTRACT" start "$MODULE" --anchor docs/modules/access/spec.md \
    --mode worktree --executor codex --branch build-access --worktree .worktrees/build-access \
    --baseline-sha "$BASE" --target-kind product --target-path src/access --entrypoint src/access \
    --approved-source-hash source-v1 --required-check tests >/dev/null
  git -C "$WT" add -A && git -C "$WT" commit -q -m 'design checkpoint and contract'
  mkdir -p "$WT/src/access"
  echo 'export const access = true' > "$WT/src/access/index.ts"
  git -C "$WT" add -A && git -C "$WT" commit -q -m 'build(access): implementation'
  IMPL=$(git -C "$WT" rev-parse HEAD)
  python3 "$CONTRACT" commit "$MODULE" --implementation-commit "$IMPL" >/dev/null
  python3 "$CONTRACT" complete "$MODULE" --implementation-commit "$IMPL" >/dev/null
  python3 "$CONTRACT" record-evidence "$MODULE" --name tests --status pass \
    --source-hash source-v1 --commit "$IMPL" >/dev/null
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
  else
    pass_test
  fi
  rm -f /tmp/land-v2.$$ /tmp/land-v2.err.$$
  teardown_fixture
}

test_merge_conflict_keeps_final_check_and_worktree() {
  start_test "land v2: merge conflict keeps final_check and worktree for retry"
  setup_fixture
  echo 'branch value' > "$WT/conflict.txt"
  git -C "$WT" add conflict.txt && git -C "$WT" commit -q -m 'branch conflict'
  NEW_IMPL=$(git -C "$WT" rev-parse HEAD)
  python3 "$CONTRACT" complete "$MODULE" --implementation-commit "$NEW_IMPL" >/dev/null
  python3 "$CONTRACT" record-evidence "$MODULE" --name tests --status pass \
    --source-hash source-v1 --commit "$NEW_IMPL" >/dev/null
  echo 'main value' > "$T/conflict.txt"
  git -C "$T" add conflict.txt && git -C "$T" commit -q -m 'main conflict'
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
  fi
  first_land_count=$(git -C "$T" log --format=%s | grep -c 'build(access): land accepted implementation')
  git -C "$T" restore PRODUCT-STATE.md
  if ! (cd "$T" && bash "$CLOSE" "$MAIN_MODULE") >/tmp/land-v2.$$ 2>/tmp/land-v2.err.$$; then
    _fail "retry should resume documentation"
    cat /tmp/land-v2.err.$$ >&2
  else
    second_land_count=$(git -C "$T" log --format=%s | grep -c 'build(access): land accepted implementation')
    state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["lifecycle_state"])' "$MAIN_MODULE/.work-meta.json")
    if [ "$state" != "documenting" ] || [ "$first_land_count" != "$second_land_count" ]; then
      _fail "retry should enter documenting without another merge commit"
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
report_results "land-work-v2"
