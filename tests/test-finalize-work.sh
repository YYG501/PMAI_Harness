#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FINALIZE="$FRAMEWORK_ROOT/scripts/finalize-work.py"
CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
CONTEXT="$FRAMEWORK_ROOT/scripts/context-pack.py"
PROJECT="$FRAMEWORK_ROOT/scripts/project-definition.py"
TIMING="$FRAMEWORK_ROOT/scripts/build-timing.py"
DOC_IMPACT="$FRAMEWORK_ROOT/scripts/doc-impact.py"
FINAL_VALIDATION="$FRAMEWORK_ROOT/scripts/final-validation.py"
CLEANUP="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"

setup_fixture() {
  local build_command="$1"
  local work_id="${WORK_ID_OVERRIDE:-work-demo}"
  shift
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-finalize-work.XXXXXX")
  MODULE="$T/docs/modules/demo"
  mkdir -p "$MODULE" "$T/prototypes/src"
  write_equivalent_product_baseline "$T"
  printf '# Rules\n' > "$T/PRODUCT-RULES.md"
  printf '# Design\n' > "$T/DESIGN.md"
  printf '# Todo\n' > "$T/TODO.md"
  printf '# Modules\n' > "$T/docs/modules/INDEX.md"
  printf '# Demo\n' > "$MODULE/spec.md"
  printf '# Decisions\n' > "$MODULE/decisions.md"
  printf '# Discussion\n' > "$MODULE/discussion.md"
  printf '{}\n' > "$T/prototypes/package.json"
  printf 'export const demo = true\n' > "$T/prototypes/src/index.ts"
  printf '.pm-workflow/context/\n' > "$T/.gitignore"
  printf '{"id":"%s","name":"demo","status":"active","lifecycle_state":"designing"}\n' \
    "$work_id" > "$MODULE/.work-meta.json"
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  python3 "$PROJECT" write "$T" --source docs/modules/demo/spec.md --type product \
    --root prototypes --entrypoint prototypes/src --language typescript --runtime node \
    --framework nextjs --package-manager pnpm --test-command "$build_command" \
    --typecheck-command "$build_command" --build-command "$build_command" >/dev/null
  git -C "$T" add -A
  git -C "$T" commit -qm design
  PACK="$T/.pm-workflow/context/demo.json"
  python3 "$CONTEXT" --repo-root "$T" --module "$MODULE" --output "$PACK" >/dev/null
  SOURCE_HASH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$PACK")
  CHECKPOINT=$(git -C "$T" rev-parse HEAD)
  python3 "$CONTRACT" ready "$MODULE" --approved-source-hash "$SOURCE_HASH" \
    --checkpoint-commit "$CHECKPOINT" --context-pack "$PACK" \
    --target-path prototypes/src --design-revision 1 >/dev/null
  START_ARGS=(
    start "$MODULE" --anchor docs/modules/demo/spec.md --mode main --executor codex
    --baseline-sha "$CHECKPOINT" --target-kind product --target-path prototypes/src
    --entrypoint prototypes/src --approved-source-hash "$SOURCE_HASH"
  )
  local check
  for check in "$@"; do START_ARGS+=(--final-check "$check"); done
  python3 "$CONTRACT" "${START_ARGS[@]}" >/dev/null
  git -C "$T" add -A
  git -C "$T" commit -qm 'start build'
  printf 'export const demo = "done"\n' > "$T/prototypes/src/index.ts"
  git -C "$T" add prototypes/src/index.ts
  git -C "$T" commit -qm implementation
  IMPLEMENTATION=$(git -C "$T" rev-parse HEAD)
  python3 "$CONTRACT" commit "$MODULE" --implementation-commit "$IMPLEMENTATION" >/dev/null
}

teardown_fixture() { rm -rf "$T"; }

assert_active_cleanup_queue() {
  local queue="$1"
  local expected_worktree="$2"
  local branch_oid
  branch_oid=$(git -C "$T" rev-parse refs/heads/build-demo) || return 1
  git -C "$T" merge-base --is-ancestor "$branch_oid" refs/heads/main || return 1
  python3 - "$queue" "$expected_worktree" "$branch_oid" <<'PY'
import json
import os
import sys

queue, expected_worktree, branch_oid = sys.argv[1:]
entries = json.load(open(queue, encoding="utf-8"))
assert len(entries) == 1, entries
entry = entries[0]
assert entry["kind"] == "work", entry
assert entry["branch"] == "build-demo", entry
assert entry["phase"] == "active", entry
assert entry["worktree"] == os.path.realpath(expected_worktree), entry
assert entry["integration_ref"] == "refs/heads/main", entry
assert entry["branch_oid"] == branch_oid, entry
assert entry["activation"] == "main_meta_landed", entry
assert entry["module_meta"] == "docs/modules/demo/.work-meta.json", entry
PY
}

setup_worktree_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-finalize-worktree.XXXXXX")
  MAIN_MODULE="$T/docs/modules/demo"
  mkdir -p "$MAIN_MODULE" "$T/prototypes/src"
  write_equivalent_product_baseline "$T"
  printf '# Rules\n' > "$T/PRODUCT-RULES.md"
  printf '# Design\n' > "$T/DESIGN.md"
  printf '# Todo\n' > "$T/TODO.md"
  printf '# Modules\n' > "$T/docs/modules/INDEX.md"
  printf '# Demo\n' > "$MAIN_MODULE/spec.md"
  printf '# Decisions\n' > "$MAIN_MODULE/decisions.md"
  printf '# Discussion\n' > "$MAIN_MODULE/discussion.md"
  printf '{}\n' > "$T/prototypes/package.json"
  printf 'export const demo = true\n' > "$T/prototypes/src/index.ts"
  printf '.worktrees/\n.pm-workflow/context/\n.runs/\n' > "$T/.gitignore"
  cat > "$MAIN_MODULE/.work-meta.json" <<'JSON'
{"id":"work-demo","name":"demo","status":"active","lifecycle_state":"designing"}
JSON
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  python3 "$PROJECT" write "$T" --source docs/modules/demo/spec.md --type product \
    --root prototypes --entrypoint prototypes/src --language typescript --runtime node \
    --framework nextjs --package-manager pnpm \
    --test-command "test -f package.json" >/dev/null
  git -C "$T" add -A
  git -C "$T" commit -qm design
  PACK="$T/.pm-workflow/context/demo.json"
  python3 "$CONTEXT" --repo-root "$T" --module "$MAIN_MODULE" --output "$PACK" >/dev/null
  SOURCE_HASH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$PACK")
  CHECKPOINT=$(git -C "$T" rev-parse HEAD)
  python3 "$CONTRACT" ready "$MAIN_MODULE" --approved-source-hash "$SOURCE_HASH" \
    --checkpoint-commit "$CHECKPOINT" --context-pack "$PACK" \
    --target-path prototypes/src --design-revision 1 >/dev/null
  git -C "$T" add docs/modules/demo/.work-meta.json
  git -C "$T" commit -qm ready
  BASE=$(git -C "$T" rev-parse HEAD)
  WT="$T/.worktrees/build-demo"
  git -C "$T" worktree add -q -b build-demo "$WT" main
  MODULE="$WT/docs/modules/demo"
  python3 "$CONTRACT" start "$MODULE" --anchor docs/modules/demo/spec.md \
    --mode worktree --executor codex --branch build-demo --worktree .worktrees/build-demo \
    --baseline-sha "$BASE" --target-kind product --target-path prototypes/src \
    --entrypoint prototypes/src --approved-source-hash "$SOURCE_HASH" \
    --final-check tests >/dev/null
  git -C "$WT" add docs/modules/demo/.work-meta.json
  git -C "$WT" commit -qm 'start build'
  printf 'export const demo = "landed"\n' > "$WT/prototypes/src/index.ts"
  git -C "$WT" add prototypes/src/index.ts
  git -C "$WT" commit -qm implementation
  IMPLEMENTATION=$(git -C "$WT" rev-parse HEAD)
  python3 "$CONTRACT" commit "$MODULE" --implementation-commit "$IMPLEMENTATION" >/dev/null
}

test_finalize_runs_missing_mechanical_checks_once_and_resumes() {
  start_test "finalize-work: runs missing mechanical checks once and resumes at final_check"
  setup_fixture "test -f package.json" tests typecheck build
  if ! python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "mechanical finalize should reach final_check"
    cat /tmp/finalize-work.err.$$ >&2
    teardown_fixture; return
  fi
  BEFORE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["started_at"])' \
    "$T/.pm-workflow/audits/demo/final-validation.json")
  if ! python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "final_check resume should be a no-op without landing"
    cat /tmp/finalize-work.err.$$ >&2
  elif ! python3 - "$MODULE/.work-meta.json" "$T/.pm-workflow/audits/demo/final-validation.json" \
    "$T/.pm-workflow/audits/demo/timing.json" "$BEFORE" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
artifact = json.load(open(sys.argv[2]))
timing = json.load(open(sys.argv[3]))
assert meta["build"]["lifecycle_state"] == "final_check"
assert {item["name"] for item in meta["build"]["acceptance"]["evidence"]} == {"tests", "typecheck", "build"}
assert artifact["source_hash"] == meta["build"]["approved_source_hash"]
assert len(artifact["commands"]) == 1
assert artifact["commands"][0]["satisfies"] == ["test", "typecheck", "build"]
assert artifact["started_at"] == sys.argv[4]
phases = [item["phase"] for item in timing["entries"]]
assert phases.count("currentness") == 1
assert phases.count("final-validation") == 1
PY
  then
    _fail "finalize state, dedupe, or resume cursor mismatch"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_new_round_deltas_finalize_in_isolated_audit_dir() {
  start_test "finalize-work: new round validates accepted deltas in its isolated audit directory"
  WORK_ID_OVERRIDE="work-demo-20260810120000-a1b2c3d4" setup_fixture \
    "test -f package.json" tests typecheck build
  AUDIT="$T/.pm-workflow/audits/demo/work-demo-20260810120000-a1b2c3d4"
  python3 "$CONTRACT" add-delta "$MODULE" --kind scoped-adjustment \
    --summary "支持批量处理" --affected-surface "列表页" \
    --scope-attestation approved-module-task-no-model-change \
    --approval-kind pm-confirmation --approval-reference "test:PM accepted batch handling" \
    --accepted-at "2026-08-10T12:00:00+08:00" >/dev/null
  python3 "$CONTRACT" add-delta "$MODULE" --kind scoped-adjustment \
    --summary "失败项可重试" --affected-surface "结果页" \
    --scope-attestation approved-module-task-no-model-change \
    --approval-kind pm-confirmation --approval-reference "test:PM accepted retry behavior" \
    --accepted-at "2026-08-10T12:05:00+08:00" >/dev/null
  python3 "$CONTRACT" commit "$MODULE" \
    --implementation-commit "$IMPLEMENTATION" >/dev/null
  if ! python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "accepted delta chain should finalize"
    cat /tmp/finalize-work.err.$$ >&2
  elif [ ! -f "$AUDIT/finalize-run.json" ] \
    || [ ! -f "$AUDIT/final-validation.json" ] \
    || [ ! -f "$AUDIT/timing.json" ]; then
    _fail "new round finalization artifacts should stay in the work-specific audit directory"
  elif [ -e "$T/.pm-workflow/audits/demo/finalize-run.json" ] \
    || [ -e "$T/.pm-workflow/audits/demo/final-validation.json" ] \
    || [ -e "$T/.pm-workflow/audits/demo/timing.json" ]; then
    _fail "new round finalization must not reuse the legacy module-level audit directory"
  elif ! python3 - "$MODULE/.work-meta.json" "$AUDIT/final-validation.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
artifact = json.load(open(sys.argv[2]))
build = meta["build"]
assert build["lifecycle_state"] == "final_check"
assert len(build["accepted_deltas"]) == 2
assert artifact["source_hash"] == build["approved_source_hash"]
PY
  then
    _fail "new round final state or accepted delta hash mismatch"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_partial_command_artifact_is_extended_without_losing_proof() {
  start_test "finalize-work: same commit/hash command artifact safely extends missing checks"
  setup_fixture "test -f package.json" tests typecheck
  AUDIT="$T/.pm-workflow/audits/demo/final-validation.json"
  python3 "$CONTRACT" request-finalization "$MODULE" >/dev/null
  python3 "$FINAL_VALIDATION" --repo-root "$T" --module-dir "$MODULE" \
    --audit "$AUDIT" --check test >/dev/null
  python3 "$CONTRACT" record-evidence "$MODULE" --name tests --status pass \
    --artifact "$AUDIT" >/dev/null
  if ! python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "runner should extend the current artifact with the missing command check"
    cat /tmp/finalize-work.err.$$ >&2
  elif ! python3 - "$AUDIT" "$MODULE/.work-meta.json" <<'PY'
import json, sys
artifact = json.load(open(sys.argv[1]))
build = json.load(open(sys.argv[2]))["build"]
assert artifact["requested_checks"] == ["test", "typecheck"]
assert artifact["commands"][0]["satisfies"] == ["test", "typecheck"]
assert {item["name"] for item in build["acceptance"]["evidence"]} == {"tests", "typecheck"}
PY
  then
    _fail "extended artifact should retain both old and new proof"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_real_build_failure_exits_normal_path() {
  start_test "finalize-work: real build failure exits the 10-minute normal path"
  setup_fixture "bash -c false" build
  if python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "real production failure must stop finalize"
  else
    SUMMARY=$(python3 "$TIMING" summary --audit-file "$T/.pm-workflow/audits/demo/timing.json")
    if python3 - "$MODULE/.work-meta.json" "$SUMMARY" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
summary = json.loads(sys.argv[2])
assert meta["build"]["lifecycle_state"] == "iterating"
assert summary["normal_path"]["status"] == "exited"
assert summary["normal_path"]["exit_reasons"][0]["phase"] == "final-validation"
PY
    then
      pass_test
    else
      _fail "failed build should remain iterating and mark SLA exited"
    fi
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_semantic_gap_resumes_without_repeating_currentness() {
  start_test "finalize-work: semantic handoff resumes without repeating currentness"
  setup_fixture "test -f package.json" tests coverage
  python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$
  status=$?
  if [ "$status" -ne 3 ]; then
    _fail "missing semantic evidence should return the resumable status 3"
    cat /tmp/finalize-work.err.$$ >&2
    teardown_fixture; return
  fi
  if ! python3 - "$T/.pm-workflow/audits/demo/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
assert any(item["phase"] == "semantic-validation" and item["status"] == "running" for item in entries)
PY
  then
    _fail "semantic handoff should keep an automatic running timing phase"
    teardown_fixture; return
  fi
  python3 "$CONTRACT" record-evidence "$MODULE" --name coverage --status pass \
    --source-hash "$SOURCE_HASH" --commit "$IMPLEMENTATION" >/dev/null
  if ! python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "semantic evidence completion should resume the same finalize attempt"
    cat /tmp/finalize-work.err.$$ >&2
  elif ! python3 - "$T/.pm-workflow/audits/demo/timing.json" \
    "$T/.pm-workflow/audits/demo/finalize-run.json" <<'PY'
import json, sys
timing = json.load(open(sys.argv[1]))
marker = json.load(open(sys.argv[2]))
assert sum(item["phase"] == "currentness" for item in timing["entries"]) == 1
assert sum(item["phase"] == "semantic-validation" and item["status"] == "pass" for item in timing["entries"]) == 1
assert not [item for item in timing["entries"] if item["status"] == "running"]
assert marker["semantic_checks"] == ["coverage"]
assert "semantic-validation" in marker["required_timing_phases"]
PY
  then
    _fail "resume cursor should preserve one currentness run and the semantic handoff"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_pm_feedback_resets_semantic_timing_attempt() {
  start_test "finalize-work: PM feedback exits and resets the semantic timing attempt"
  setup_fixture "test -f package.json" tests coverage
  python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$
  if [ "$?" -ne 3 ]; then
    _fail "first semantic handoff should return 3"
    teardown_fixture; return
  fi
  python3 "$CONTRACT" resume-iteration "$MODULE" >/dev/null
  python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$
  if [ "$?" -ne 3 ]; then
    _fail "new PM finalization request should start a fresh semantic handoff"
  elif ! python3 - "$T/.pm-workflow/audits/demo/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
semantic = [item for item in entries if item["phase"] == "semantic-validation"]
assert sum(item["status"] == "fail" for item in semantic) == 1
assert sum(item["status"] == "running" for item in semantic) == 1
assert sum(item["phase"] == "currentness" for item in entries) == 2
PY
  then
    _fail "PM feedback should fail the old SLA attempt and time the new one"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_pm_feedback_after_semantic_pass_starts_new_phase() {
  start_test "finalize-work: PM feedback cannot reuse a prior semantic pass"
  setup_fixture "test -f package.json" tests coverage
  python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$
  if [ "$?" -ne 3 ]; then
    _fail "first semantic handoff should return 3"
    teardown_fixture; return
  fi
  python3 "$CONTRACT" record-evidence "$MODULE" --name coverage --status pass \
    --source-hash "$SOURCE_HASH" --commit "$IMPLEMENTATION" >/dev/null
  if ! python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "first semantic pass should reach final_check"
    teardown_fixture; return
  fi
  python3 "$CONTRACT" resume-iteration "$MODULE" >/dev/null
  python3 "$FINALIZE" --module-dir "$MODULE" --no-land \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$
  if [ "$?" -ne 3 ]; then
    _fail "PM feedback should require a new semantic handoff"
  elif ! python3 - "$T/.pm-workflow/audits/demo/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
semantic = [item for item in entries if item["phase"] == "semantic-validation"]
assert sum(item["status"] == "pass" for item in semantic) == 1
assert sum(item["status"] == "running" for item in semantic) == 1
assert sum(item["phase"] == "currentness" for item in entries) == 2
PY
  then
    _fail "new PM feedback must not let the old semantic pass satisfy the new attempt"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_iteration_commit_blocks_out_of_scope_path_immediately() {
  start_test "build-contract: iteration commit blocks an out-of-scope path immediately"
  setup_fixture "test -f package.json" build
  mkdir -p "$T/app"
  echo 'unapproved home entry' > "$T/app/page.tsx"
  git -C "$T" add app/page.tsx
  git -C "$T" commit -qm 'unapproved home change'
  OUTSIDE_COMMIT=$(git -C "$T" rev-parse HEAD)
  if python3 "$CONTRACT" commit "$MODULE" --implementation-commit "$OUTSIDE_COMMIT" \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "out-of-scope commit should be rejected at commit time"
  elif ! grep -q "批准范围外路径" /tmp/finalize-work.err.$$; then
    _fail "scope rejection guidance mismatch"
    cat /tmp/finalize-work.err.$$ >&2
  elif ! python3 - "$MODULE/.work-meta.json" "$IMPLEMENTATION" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["implementation_commit"] == sys.argv[2]
PY
  then
    _fail "rejected scope must preserve the prior implementation commit"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$
  teardown_fixture
}

test_worktree_finalize_lands_and_resumes_docs_to_complete() {
  start_test "finalize-work: worktree finalization lands and resumes documenting to complete"
  setup_worktree_fixture
  if ! (cd "$T" && python3 "$FINALIZE" --module-dir "$MODULE") \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "worktree finalize should commit acceptance, merge, and start docs"
    cat /tmp/finalize-work.err.$$ >&2
    teardown_fixture; return
  fi
  MAP="$T/.pm-workflow/audits/demo/doc-impact.json"
  QUEUE="$T/.runs/pending-cleanup.json"
  if [ ! -d "$WT" ] \
    || ! git -C "$T" show-ref --verify --quiet refs/heads/build-demo \
    || [ ! -f "$MAIN_MODULE/.work-meta.json" ] \
    || [ ! -f "$MAP" ]; then
    _fail "landing should preserve the queued isolation environment and documenting state"
    teardown_fixture; return
  elif ! assert_active_cleanup_queue "$QUEUE" "$WT"; then
    _fail "landing should persist one active cleanup record bound to main and the branch OID"
    teardown_fixture; return
  elif ! grep -Eq '^FINALIZE_RESUME_MODULE=.*/docs/modules/demo$' /tmp/finalize-work.$$; then
    _fail "runner should publish the deterministic main-module resume cursor"
    teardown_fixture; return
  elif ! (cd "$T" && bash "$CLEANUP") \
    >/tmp/finalize-cleanup.$$ 2>/tmp/finalize-cleanup.err.$$; then
    _fail "queued isolation cleanup should succeed from the main repository"
    cat /tmp/finalize-cleanup.$$ /tmp/finalize-cleanup.err.$$ >&2
    teardown_fixture; return
  elif [ -d "$WT" ] \
    || git -C "$T" show-ref --verify --quiet refs/heads/build-demo \
    || [ -f "$QUEUE" ]; then
    _fail "safe cleanup should remove the exact worktree, branch, and queue entry"
    teardown_fixture; return
  fi
  ITEM=$(python3 - "$MAP" <<'PY'
import json, sys
items = [item for item in json.load(open(sys.argv[1]))["items"] if item["status"] == "pending"]
assert len(items) == 1
print(items[0]["id"])
PY
  )
  printf '\n- Demo landed.\n' >> "$T/PRODUCT-STATE.md"
  python3 "$DOC_IMPACT" cover "$MAP" --item "$ITEM" --status covered \
    --file PRODUCT-STATE.md >/dev/null
  python3 "$CONTRACT" docs-complete "$MAIN_MODULE" >/dev/null
  if ! (cd "$T" && python3 "$FINALIZE" --module-dir "$MAIN_MODULE") \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "documenting/complete should resume without another merge"
    cat /tmp/finalize-work.err.$$ >&2
  elif [ -f "$MAIN_MODULE/.work-meta.json" ]; then
    _fail "completed docs should clear module work state"
  elif ! python3 - "$T/.pm-workflow/audits/demo/timing.json" <<'PY'
import json, sys
entries = json.load(open(sys.argv[1]))["entries"]
required = {"currentness", "final-validation", "landing", "documentation"}
assert required <= {item["phase"] for item in entries if item["status"] == "pass"}
assert not [item for item in entries if item["status"] == "running"]
PY
  then
    _fail "completed runner timing ledger is incomplete"
  elif [ -z "$(git -C "$T" log --format=%s --grep='^build(demo): record final acceptance$' -1)" ]; then
    _fail "runner should create the controlled final acceptance commit"
  elif [ -n "$(git -C "$T" status --short --untracked-files=all)" ]; then
    _fail "end-to-end finalize should leave main clean"
    git -C "$T" status --short --untracked-files=all >&2
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$ \
    /tmp/finalize-cleanup.$$ /tmp/finalize-cleanup.err.$$
  teardown_fixture
}

test_legacy_v4_final_check_without_runner_audit_lands() {
  start_test "finalize-work: legacy v4 final_check without runner audit lands without migration"
  setup_worktree_fixture
  python3 "$CONTRACT" request-finalization "$MODULE" >/dev/null
  python3 "$CONTRACT" record-evidence "$MODULE" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit "$IMPLEMENTATION" >/dev/null
  python3 "$CONTRACT" review-ready "$MODULE" >/dev/null
  python3 "$CONTRACT" accept "$MODULE" >/dev/null
  if [ -e "$WT/.pm-workflow/audits/demo/finalize-run.json" ] || \
     [ -e "$WT/.pm-workflow/audits/demo/timing.json" ]; then
    _fail "legacy fixture must not contain runner audit state"
    teardown_fixture; return
  fi
  if ! (cd "$T" && python3 "$FINALIZE" --module-dir "$MODULE") \
    >/tmp/finalize-work.$$ 2>/tmp/finalize-work.err.$$; then
    _fail "legacy final_check should land without a runner-state migration"
    cat /tmp/finalize-work.err.$$ >&2
  elif [ ! -d "$WT" ] \
    || ! git -C "$T" show-ref --verify --quiet refs/heads/build-demo \
    || [ ! -f "$MAIN_MODULE/.work-meta.json" ]; then
    _fail "legacy final_check should merge once and queue its isolation environment"
  elif ! assert_active_cleanup_queue "$T/.runs/pending-cleanup.json" "$WT"; then
    _fail "legacy landing should persist one active cleanup record with stable identity"
  elif [ -f "$T/.pm-workflow/audits/demo/finalize-run.json" ]; then
    _fail "legacy recovery must not synthesize a new runner marker"
  elif ! python3 - "$MAIN_MODULE/.work-meta.json" \
    "$T/.pm-workflow/audits/demo/timing.json" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
entries = json.load(open(sys.argv[2]))["entries"]
assert build["contract_version"] == 4
assert build["lifecycle_state"] == "documenting"
assert build["docs_status"] == "pending"
assert not [item for item in entries if item["phase"] in {"currentness", "final-validation"}]
assert any(item["phase"] == "landing" and item["status"] == "pass" for item in entries)
PY
  then
    _fail "legacy recovery should preserve v4 fields and skip new timing requirements"
  elif ! (cd "$T" && bash "$CLEANUP") \
    >/tmp/finalize-cleanup.$$ 2>/tmp/finalize-cleanup.err.$$; then
    _fail "legacy queued cleanup should succeed from the main repository"
    cat /tmp/finalize-cleanup.$$ /tmp/finalize-cleanup.err.$$ >&2
  elif [ -d "$WT" ] \
    || git -C "$T" show-ref --verify --quiet refs/heads/build-demo \
    || [ -f "$T/.runs/pending-cleanup.json" ]; then
    _fail "legacy cleanup should remove the exact worktree, branch, and queue entry"
  else
    pass_test
  fi
  rm -f /tmp/finalize-work.$$ /tmp/finalize-work.err.$$ \
    /tmp/finalize-cleanup.$$ /tmp/finalize-cleanup.err.$$
  teardown_fixture
}

test_finalize_runs_missing_mechanical_checks_once_and_resumes
test_new_round_deltas_finalize_in_isolated_audit_dir
test_partial_command_artifact_is_extended_without_losing_proof
test_real_build_failure_exits_normal_path
test_semantic_gap_resumes_without_repeating_currentness
test_pm_feedback_resets_semantic_timing_attempt
test_pm_feedback_after_semantic_pass_starts_new_phase
test_iteration_commit_blocks_out_of_scope_path_immediately
test_worktree_finalize_lands_and_resumes_docs_to_complete
test_legacy_v4_final_check_without_runner_audit_lands
report_results "finalize-work"
