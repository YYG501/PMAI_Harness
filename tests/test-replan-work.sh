#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REPLAN="$FRAMEWORK_ROOT/scripts/replan-work.py"

setup_replan_work() {
  local lifecycle="$1"
  local work_name="${2:-demo}"
  WORK_ID="work-replan"
  WORK_NAME="$work_name"
  WORK_BRANCH="build-${WORK_ID}-${WORK_NAME}"
  fixture_setup
  BASELINE_SHA=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  WORK_MODULE=$(fixture_create_work "$WORK_ID" "$WORK_NAME" 2)
  WORKTREE="$(cd "$FIXTURE_DIR/.worktrees/$WORK_BRANCH" && pwd -P)"
  MODULE_REL="docs/modules/$WORK_BRANCH"
  MAIN_MODULE="$FIXTURE_DIR/$MODULE_REL"
  mkdir -p "$MAIN_MODULE"
  cp -R "$WORKTREE/$MODULE_REL/." "$MAIN_MODULE/"
  python3 - "$WORKTREE/$MODULE_REL/.work-meta.json" "$FIXTURE_DIR/$MODULE_REL/.work-meta.json" "$lifecycle" "$BASELINE_SHA" <<'PY'
import json
import sys
from pathlib import Path

for raw in sys.argv[1:3]:
    path = Path(raw)
    value = json.loads(path.read_text(encoding="utf-8"))
    build = value["build"]
    build.update({
        "contract_version": 4,
        "mode": "worktree",
        "lifecycle_state": sys.argv[3],
        "baseline_sha": sys.argv[4],
    })
    value["lifecycle_state"] = sys.argv[3]
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$WORKTREE" add -- "$MODULE_REL/.work-meta.json"
  git -C "$WORKTREE" commit -q -m "prepare active build"
  git -C "$FIXTURE_DIR" add -- "$MODULE_REL"
  git -C "$FIXTURE_DIR" commit -q -m "mirror active build metadata"
  CANDIDATE_HEAD=$(git -C "$WORKTREE" rev-parse HEAD)
}

setup_replan_main_work() {
  local lifecycle="$1"
  WORK_ID="work-main-replan"
  WORK_NAME="main-demo"
  WORK_BRANCH="main"
  fixture_setup
  WORK_MODULE=$(fixture_create_main_work "$WORK_ID" "$WORK_NAME" 2)
  WORKTREE="$(cd "$FIXTURE_DIR" && pwd -P)"
  MODULE_REL="docs/modules/build-${WORK_ID}-${WORK_NAME}"
  MAIN_MODULE="$WORKTREE/$MODULE_REL"
  BASELINE_SHA=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"]["baseline_sha"])' \
    "$MAIN_MODULE/.work-meta.json")
  python3 - "$MAIN_MODULE/.work-meta.json" "$lifecycle" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["lifecycle_state"] = sys.argv[2]
value["build"].update({
    "contract_version": 4,
    "lifecycle_state": sys.argv[2],
})
path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  printf 'main candidate implementation\n' > "$WORKTREE/main-candidate.txt"
  git -C "$WORKTREE" add -- "$MODULE_REL/.work-meta.json" main-candidate.txt
  git -C "$WORKTREE" commit -q -m "prepare main mode candidate"
  CANDIDATE_HEAD=$(git -C "$WORKTREE" rev-parse HEAD)
}

write_replan_manifest() {
  local route="$1"
  local mode="${2:-}"
  local manifest="$FIXTURE_DIR/.runs/replan-candidates/$WORK_ID.json"
  mkdir -p "$(dirname "$manifest")"
  python3 - "$manifest" "$WORK_ID" "$WORK_BRANCH" "$WORKTREE" "$MODULE_REL" "$CANDIDATE_HEAD" "$BASELINE_SHA" "$route" "$mode" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = {
    "schema_version": 1,
    "work_id": sys.argv[2],
    "route": sys.argv[8],
    "candidate_head": sys.argv[6],
    "original_baseline_sha": sys.argv[7],
    "branch": sys.argv[3],
    "worktree": sys.argv[4],
    "module": sys.argv[5],
    "main_branch": "main",
    "created_at": "2026-01-01T00:00:00+00:00",
}
if sys.argv[9]:
    value["mode"] = sys.argv[9]
path.write_text(json.dumps(value, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

assert_replanned() {
  local route="$1"
  local output="$2"
  local manifest="$FIXTURE_DIR/.runs/replan-candidates/$WORK_ID.json"
  if ! python3 - "$output" "$manifest" "$route" "$CANDIDATE_HEAD" "$WORK_BRANCH" "$WORKTREE" "$MODULE_REL" "$BASELINE_SHA" <<'PY'
import json
import sys
from pathlib import Path

output = json.loads(sys.argv[1])
manifest = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
route, head, branch, worktree, module, baseline = sys.argv[3:]
assert output["status"] == "replanned"
assert output["route"] == route
assert output["candidate_preserved"] is True
assert output["pending_cleanup_enqueued"] is False
assert manifest["route"] == route
assert manifest["candidate_head"] == head
assert manifest["original_baseline_sha"] == baseline
assert manifest["branch"] == branch
assert manifest["worktree"] == worktree
assert manifest["module"] == module
PY
  then
    _fail "unexpected replan result: $output"
    return 1
  fi
  if [ -f "$WORKTREE/$MODULE_REL/.work-meta.json" ] || [ -f "$FIXTURE_DIR/$MODULE_REL/.work-meta.json" ]; then
    _fail "replan should remove .work-meta.json from both worktrees"
    return 1
  fi
  if [ ! -d "$WORKTREE" ] || ! git -C "$FIXTURE_DIR" branch --list "$WORK_BRANCH" | grep -q .; then
    _fail "candidate worktree and branch must be retained"
    return 1
  fi
  if [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "replan must not enqueue pending cleanup"
    return 1
  fi
  if ! git -C "$WORKTREE" merge-base --is-ancestor "$CANDIDATE_HEAD" HEAD; then
    _fail "candidate HEAD must remain reachable from retained branch"
    return 1
  fi
}

test_replan_proposal_preserves_candidate() {
  start_test "replan: proposal route preserves old candidate outside main"
  setup_replan_work iterating
  printf 'candidate implementation\n' > "$WORKTREE/candidate-only.txt"
  git -C "$WORKTREE" add -- candidate-only.txt
  git -C "$WORKTREE" commit -q -m "candidate implementation"
  CANDIDATE_HEAD=$(git -C "$WORKTREE" rev-parse HEAD)
  local output
  if output=$(python3 "$REPLAN" "$WORK_MODULE" --route proposal 2>&1); then
    if assert_replanned proposal "$output" && [ ! -f "$FIXTURE_DIR/candidate-only.txt" ]; then
      pass_test
    elif [ -f "$FIXTURE_DIR/candidate-only.txt" ]; then
      _fail "old candidate must not enter main"
    fi
  else
    _fail "proposal replan failed: $output"
  fi
  fixture_teardown
}

test_replan_design_preserves_candidate() {
  start_test "replan: design route supports final_check and keeps branch"
  setup_replan_work final_check
  local output
  if output=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    if assert_replanned design "$output"; then pass_test; fi
  else
    _fail "design replan failed: $output"
  fi
  fixture_teardown
}

test_replan_blocks_dirty_and_staged_worktrees() {
  start_test "replan: blocks dirty or staged candidate changes"
  setup_replan_work building
  printf 'dirty\n' > "$WORKTREE/未提交变更.txt"
  local output
  if python3 "$REPLAN" "$WORK_MODULE" --route design > /tmp/replan-out.$$ 2>&1; then
    _fail "dirty candidate should block replan"
  elif ! grep -q "未提交改动" /tmp/replan-out.$$; then
    _fail "dirty candidate should explain the block"
  elif [ -e "$FIXTURE_DIR/.runs/replan-candidates/$WORK_ID.json" ]; then
    _fail "failed preflight must not create a manifest"
  else
    rm -f "$WORKTREE/未提交变更.txt"
    printf 'staged\n' > "$WORKTREE/已暂存变更.txt"
    git -C "$WORKTREE" add -- 已暂存变更.txt
    if python3 "$REPLAN" "$WORK_MODULE" --route design > /tmp/replan-out.$$ 2>&1; then
      _fail "staged candidate should block replan"
    elif ! grep -q "未提交改动" /tmp/replan-out.$$; then
      _fail "staged candidate should explain the block"
    else
      pass_test
    fi
  fi
  rm -f /tmp/replan-out.$$
  fixture_teardown
}

test_replan_blocks_dirty_main_and_mismatched_mode() {
  start_test "replan: blocks dirty main and mismatched build mode"
  setup_replan_work iterating
  printf 'main dirty\n' > "$FIXTURE_DIR/main-dirty.txt"
  if python3 "$REPLAN" "$WORK_MODULE" --route proposal > /tmp/replan-out.$$ 2>&1; then
    _fail "dirty main should block replan"
  elif ! grep -q "main存在未提交改动" /tmp/replan-out.$$; then
    _fail "dirty main should explain the block"
  else
    rm -f "$FIXTURE_DIR/main-dirty.txt"
    python3 - "$WORKTREE/$MODULE_REL/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["build"]["mode"] = "main"
path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
    if python3 "$REPLAN" "$WORK_MODULE" --route proposal > /tmp/replan-out.$$ 2>&1; then
      _fail "a worktree cannot claim main mode"
    elif ! grep -q "声明 main mode" /tmp/replan-out.$$; then
      _fail "mode mismatch should explain the safety boundary"
    else
      pass_test
    fi
  fi
  rm -f /tmp/replan-out.$$
  fixture_teardown
}

test_replan_list_is_read_only_when_empty() {
  start_test "replan: empty candidate list is read-only"
  fixture_setup
  local output before_head
  before_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  if output=$(cd "${TMPDIR:-/tmp}" && python3 "$REPLAN" list "$FIXTURE_DIR" 2>&1); then
    if ! python3 - "$output" "$FIXTURE_DIR" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
assert result["status"] == "candidate_list"
assert result["count"] == 0
assert result["candidates"] == []
assert result["read_only"] is True
assert result["main_root"] == str(Path(sys.argv[2]).resolve())
PY
    then
      _fail "empty candidate list output mismatch: $output"
    elif [ -e "$FIXTURE_DIR/.runs/replan-candidates" ]; then
      _fail "read-only list must not create candidate storage"
    elif [ "$(git -C "$FIXTURE_DIR" rev-parse HEAD)" != "$before_head" ] \
      || [ -n "$(git -C "$FIXTURE_DIR" status --porcelain)" ]; then
      _fail "read-only list must not mutate the repository"
    else
      pass_test
    fi
  else
    _fail "empty candidate list failed: $output"
  fi
  fixture_teardown
}

test_replan_list_returns_every_candidate() {
  start_test "replan: cross-cwd list returns every candidate without mtime guessing"
  fixture_setup
  local manifest_dir="$FIXTURE_DIR/.runs/replan-candidates"
  local head output
  head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  mkdir -p "$manifest_dir"
  python3 - "$manifest_dir" "$FIXTURE_DIR" "$head" <<'PY'
import json
import sys
from pathlib import Path

manifest_dir = Path(sys.argv[1])
root = str(Path(sys.argv[2]).resolve())
head = sys.argv[3]
values = (
    ("candidate-z", "proposal", "2026-01-01T00:00:00+00:00"),
    ("candidate-a", "design", "2026-12-31T00:00:00+00:00"),
)
for work_id, route, created_at in values:
    (manifest_dir / f"{work_id}.json").write_text(json.dumps({
        "schema_version": 1,
        "work_id": work_id,
        "mode": "main",
        "route": route,
        "candidate_head": head,
        "original_baseline_sha": head,
        "branch": "main",
        "worktree": root,
        "module": f"docs/modules/{work_id}",
        "main_branch": "main",
        "created_at": created_at,
    }, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  touch -t 203001010101 "$manifest_dir/candidate-z.json"
  touch -t 202001010101 "$manifest_dir/candidate-a.json"
  if output=$(cd "${TMPDIR:-/tmp}" && python3 "$REPLAN" list "$FIXTURE_DIR" 2>&1); then
    if python3 - "$output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["count"] == 2
assert [item["work_id"] for item in result["candidates"]] == ["candidate-a", "candidate-z"]
assert {item["route"] for item in result["candidates"]} == {"proposal", "design"}
assert all(item["mode"] == "main" for item in result["candidates"])
PY
    then
      pass_test
    else
      _fail "candidate list omitted or guessed among manifests: $output"
    fi
  else
    _fail "cross-cwd candidate list failed: $output"
  fi
  fixture_teardown
}

test_replan_main_mode_preserves_implementation_and_fixed_range() {
  start_test "replan: main mode keeps implementation and freezes an inspectable range"
  setup_replan_main_work iterating
  local replanned manifest_rel manifest head_after_replan list_output inspected retired head_after_later
  if ! replanned=$(python3 "$REPLAN" "$WORK_MODULE" --route proposal 2>&1); then
    _fail "main mode replan failed: $replanned"
    fixture_teardown; return
  fi
  manifest_rel=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate_manifest_relative"])' <<<"$replanned")
  manifest="$FIXTURE_DIR/$manifest_rel"
  head_after_replan=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  if ! python3 - "$replanned" "$manifest" "$CANDIDATE_HEAD" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
manifest = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert result["status"] == "replanned"
assert result["mode"] == "main"
assert result["candidate_head"] == sys.argv[3]
assert result["pending_cleanup_enqueued"] is False
assert manifest["mode"] == "main"
assert manifest["candidate_head"] == sys.argv[3]
PY
  then
    _fail "main replan result mismatch: $replanned"
  elif [ -e "$MAIN_MODULE/.work-meta.json" ]; then
    _fail "main replan must commit only the active metadata removal"
  elif [ ! -f "$FIXTURE_DIR/main-candidate.txt" ] \
    || ! grep -q 'main candidate implementation' "$FIXTURE_DIR/main-candidate.txt"; then
    _fail "main replan must never roll back implementation already on main"
  elif [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "main replan must not enqueue cleanup"
  else
    printf 'later main change\n' > "$FIXTURE_DIR/after-replan.txt"
    git -C "$FIXTURE_DIR" add -- after-replan.txt
    git -C "$FIXTURE_DIR" commit -q -m "later unrelated main commit"
    head_after_later=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
    if ! list_output=$(cd "${TMPDIR:-/tmp}" && python3 "$REPLAN" list "$FIXTURE_DIR" 2>&1); then
      _fail "main candidate was not discoverable across cwd: $list_output"
    elif ! inspected=$(cd "${TMPDIR:-/tmp}" && python3 "$REPLAN" inspect "$manifest" 2>&1); then
      _fail "main candidate inspect failed after later main commit: $inspected"
    elif ! python3 - "$list_output" "$inspected" "$manifest" "$BASELINE_SHA" "$CANDIDATE_HEAD" <<'PY'
import json
import sys
from pathlib import Path

listed = json.loads(sys.argv[1])
inspected = json.loads(sys.argv[2])
assert listed["count"] == 1
item = listed["candidates"][0]
assert Path(item["candidate_manifest"]).resolve() == Path(sys.argv[3]).resolve()
assert item["mode"] == "main"
assert item["route"] == "proposal"
assert inspected["diff_range"] == f"{sys.argv[4]}..{sys.argv[5]}"
assert "main-candidate.txt" in inspected["changed_paths"]
assert "after-replan.txt" not in inspected["changed_paths"]
assert "after-replan.txt" not in inspected["diff"]
PY
    then
      _fail "main list/inspect did not preserve the fixed candidate range"
    elif [ "$(git -C "$FIXTURE_DIR" rev-parse HEAD)" != "$head_after_later" ]; then
      _fail "list and inspect must not move main"
    elif ! retired=$(python3 "$REPLAN" retire "$manifest" --reconciled 2>&1); then
      _fail "main candidate retire failed: $retired"
    elif ! python3 - "$retired" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["status"] == "candidate_retired"
assert result["mode"] == "main"
assert result["manifest_removed"] is True
assert result["pending_cleanup_enqueued"] is False
PY
    then
      _fail "main candidate retire result mismatch: $retired"
    elif [ -e "$manifest" ] || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
      _fail "main retire must only remove the manifest"
    elif [ ! -f "$FIXTURE_DIR/main-candidate.txt" ] \
      || [ ! -f "$FIXTURE_DIR/after-replan.txt" ] \
      || [ "$(git -C "$FIXTURE_DIR" rev-parse HEAD)" != "$head_after_later" ] \
      || [ "$head_after_replan" = "$CANDIDATE_HEAD" ]; then
      _fail "main retire must preserve implementation and later commits"
    else
      pass_test
    fi
  fi
  fixture_teardown
}

test_replan_main_mode_recovers_staged_meta_deletion() {
  start_test "replan: main mode recovers a staged metadata deletion idempotently"
  setup_replan_main_work iterating
  write_replan_manifest design main
  git -C "$FIXTURE_DIR" rm -q -- "$MODULE_REL/.work-meta.json"
  local first second first_head
  if ! first=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    _fail "main staged-deletion recovery failed: $first"
  else
    first_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
    if ! second=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
      _fail "completed main replan replay failed: $second"
    elif ! python3 - "$first" "$second" <<'PY'
import json
import sys

first = json.loads(sys.argv[1])
second = json.loads(sys.argv[2])
assert first["mode"] == "main"
assert first["recovered"] is True
assert first["main_meta_removed"] is True
assert second["mode"] == "main"
assert second["recovered"] is True
assert second["main_meta_removed"] is True
PY
    then
      _fail "main replan recovery result mismatch: first=$first second=$second"
    elif [ "$(git -C "$FIXTURE_DIR" rev-parse HEAD)" != "$first_head" ]; then
      _fail "completed main replan replay must not add a commit"
    elif [ -e "$MAIN_MODULE/.work-meta.json" ] \
      || [ ! -f "$FIXTURE_DIR/main-candidate.txt" ] \
      || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
      _fail "main recovery must only finish metadata removal"
    else
      pass_test
    fi
  fi
  fixture_teardown
}

test_replan_main_mode_rejects_candidate_removed_from_main_history() {
  start_test "replan: main inspect and retire require main to retain candidate HEAD"
  setup_replan_main_work iterating
  local replanned manifest_rel manifest inspect_out retire_out
  if ! replanned=$(python3 "$REPLAN" "$WORK_MODULE" --route proposal 2>&1); then
    _fail "main mode replan failed: $replanned"
    fixture_teardown; return
  fi
  manifest_rel=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate_manifest_relative"])' <<<"$replanned")
  manifest="$FIXTURE_DIR/$manifest_rel"

  git -C "$FIXTURE_DIR" update-ref refs/heads/main "$BASELINE_SHA"
  if inspect_out=$(python3 "$REPLAN" inspect "$manifest" 2>&1); then
    _fail "inspect accepted a main branch that no longer retains candidate HEAD"
  elif ! echo "$inspect_out" | grep -q "不再包含 manifest 记录的 candidate HEAD"; then
    _fail "inspect should explain the missing candidate ancestry: $inspect_out"
  elif retire_out=$(python3 "$REPLAN" retire "$manifest" --reconciled 2>&1); then
    _fail "retire accepted a main branch that no longer retains candidate HEAD"
  elif ! echo "$retire_out" | grep -q "不再包含 manifest 记录的 candidate HEAD"; then
    _fail "retire should explain the missing candidate ancestry: $retire_out"
  elif [ ! -f "$manifest" ]; then
    _fail "failed retire must preserve the candidate manifest"
  else
    pass_test
  fi
  fixture_teardown
}

test_replan_recovers_after_old_side_committed() {
  start_test "replan: rerun recovers after only old worktree metadata was removed"
  setup_replan_work iterating
  write_replan_manifest proposal
  git -C "$WORKTREE" rm -q -- "$MODULE_REL/.work-meta.json"
  git -C "$WORKTREE" commit -q -m "replan: preserve candidate $WORK_ID for proposal"
  local output
  if output=$(python3 "$REPLAN" "$WORK_MODULE" --route proposal 2>&1); then
    if assert_replanned proposal "$output"; then pass_test; fi
  else
    _fail "replan recovery failed: $output"
  fi
  fixture_teardown
}

test_replan_is_idempotent_after_completion() {
  start_test "replan: completed handoff is idempotent on repeat"
  setup_replan_work iterating
  local first second old_head main_head
  if ! first=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    _fail "initial replan failed: $first"
    fixture_teardown; return
  fi
  old_head=$(git -C "$WORKTREE" rev-parse HEAD)
  main_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  if second=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    if ! python3 - "$second" <<'PY'
import json
import sys
assert json.loads(sys.argv[1])["recovered"] is True
PY
    then
      _fail "repeat replan should report recovery: $second"
    elif [ "$(git -C "$WORKTREE" rev-parse HEAD)" != "$old_head" ] \
      || [ "$(git -C "$FIXTURE_DIR" rev-parse HEAD)" != "$main_head" ]; then
      _fail "repeat replan must not add another commit"
    elif assert_replanned design "$second"; then
      pass_test
    fi
  else
    _fail "repeat replan failed: $second"
  fi
  fixture_teardown
}

test_replan_recovers_staged_git_rm_on_both_sides() {
  start_test "replan: staged git rm interruption is committed on retry"
  setup_replan_work iterating
  write_replan_manifest design
  git -C "$WORKTREE" rm -q -- "$MODULE_REL/.work-meta.json"
  git -C "$FIXTURE_DIR" rm -q -- "$MODULE_REL/.work-meta.json"
  local output
  if output=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    if ! git -C "$WORKTREE" diff --cached --quiet \
      || ! git -C "$FIXTURE_DIR" diff --cached --quiet; then
      _fail "recovery must commit both staged deletions"
    elif assert_replanned design "$output"; then
      pass_test
    fi
  else
    _fail "staged git rm recovery failed: $output"
  fi
  fixture_teardown
}

test_replan_repeat_preserves_new_main_work_id() {
  start_test "replan: replay never removes a newer main work id"
  setup_replan_work iterating
  local first second old_head main_head
  if ! first=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    _fail "initial replan failed: $first"
    fixture_teardown; return
  fi
  python3 - "$MAIN_MODULE/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.write_text(json.dumps({
    "id": "work-new-round",
    "name": "new round",
    "status": "active",
    "lifecycle_state": "designing",
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$FIXTURE_DIR" add -- "$MODULE_REL/.work-meta.json"
  git -C "$FIXTURE_DIR" commit -q -m "start a newer module round"
  old_head=$(git -C "$WORKTREE" rev-parse HEAD)
  main_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  if second=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    if [ "$(git -C "$WORKTREE" rev-parse HEAD)" != "$old_head" ] \
      || [ "$(git -C "$FIXTURE_DIR" rev-parse HEAD)" != "$main_head" ]; then
      _fail "replay must not create commits after a newer work round exists"
    elif ! python3 - "$second" "$MAIN_MODULE/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
meta = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert result["recovered"] is True
assert result["main_meta_removed"] is False
assert result["main_meta_preserved"] is True
assert meta["id"] == "work-new-round"
PY
    then
      _fail "replay did not preserve the newer main work: $second"
    else
      pass_test
    fi
  else
    _fail "completed replan replay failed: $second"
  fi
  fixture_teardown
}

test_replan_rejects_ambiguous_main_and_master_mounts() {
  start_test "replan: mounted main and master fail closed"
  setup_replan_work iterating
  git -C "$FIXTURE_DIR" branch master
  git -C "$FIXTURE_DIR" worktree add -q "$FIXTURE_DIR/.worktrees/master-copy" master
  if python3 "$REPLAN" "$WORK_MODULE" --route design > /tmp/replan-out.$$ 2>&1; then
    _fail "simultaneously mounted main/master must fail"
  elif ! grep -q "main/master 同时挂载" /tmp/replan-out.$$; then
    _fail "ambiguous main failure should explain the identity conflict"
  elif [ -e "$FIXTURE_DIR/.runs/replan-candidates/$WORK_ID.json" ]; then
    _fail "ambiguous main preflight must not create a manifest"
  else
    pass_test
  fi
  rm -f /tmp/replan-out.$$
  fixture_teardown
}

test_replan_rejects_candidate_storage_symlinks() {
  start_test "replan: candidate storage rejects symlinks and outside targets"
  local outside first_ok=false second_ok=false
  outside=$(mktemp -d "${TMPDIR:-/tmp}/pmai-replan-outside.XXXXXX")

  setup_replan_work iterating
  ln -s "$outside" "$FIXTURE_DIR/.runs/replan-candidates"
  if ! python3 "$REPLAN" "$WORK_MODULE" --route proposal > /tmp/replan-out.$$ 2>&1 \
    && grep -q "符号链接" /tmp/replan-out.$$ \
    && [ -z "$(ls -A "$outside")" ]; then
    first_ok=true
  fi
  fixture_teardown

  setup_replan_work iterating
  mkdir -p "$FIXTURE_DIR/.runs/replan-candidates"
  printf '{}\n' > "$outside/foreign.json"
  ln -s "$outside/foreign.json" "$FIXTURE_DIR/.runs/replan-candidates/foreign.json"
  if ! python3 "$REPLAN" "$WORK_MODULE" --route design > /tmp/replan-out.$$ 2>&1 \
    && grep -q "符号链接" /tmp/replan-out.$$; then
    second_ok=true
  fi
  if [ "$first_ok" = true ] && [ "$second_ok" = true ]; then
    pass_test
  else
    _fail "candidate directory and every entry must reject symlink traversal"
  fi
  rm -f /tmp/replan-out.$$
  fixture_teardown
  rm -rf "$outside"
}

test_replan_list_rejects_candidate_storage_symlinks() {
  start_test "replan: list rejects symlinked candidate storage"
  local outside
  outside=$(mktemp -d "${TMPDIR:-/tmp}/pmai-replan-list-outside.XXXXXX")
  fixture_setup
  ln -s "$outside" "$FIXTURE_DIR/.runs/replan-candidates"
  if python3 "$REPLAN" list "$FIXTURE_DIR" > /tmp/replan-out.$$ 2>&1; then
    _fail "list must reject a symlinked candidate directory"
  elif ! grep -q "符号链接" /tmp/replan-out.$$; then
    _fail "list symlink rejection should explain the safety boundary"
  elif [ -n "$(ls -A "$outside")" ]; then
    _fail "list must not write through candidate storage symlinks"
  else
    pass_test
  fi
  rm -f /tmp/replan-out.$$
  fixture_teardown
  rm -rf "$outside"
}

test_replan_inspect_is_read_only_and_unicode_safe() {
  start_test "replan: inspect shows unicode baseline..candidate diff without mutation"
  setup_replan_work iterating "中文模块"
  printf '候选实现\n' > "$WORKTREE/候选说明.txt"
  git -C "$WORKTREE" add -- 候选说明.txt
  git -C "$WORKTREE" commit -q -m "add unicode candidate"
  CANDIDATE_HEAD=$(git -C "$WORKTREE" rev-parse HEAD)
  local replanned manifest manifest_rel before_manifest before_old before_main inspected
  if ! replanned=$(python3 "$REPLAN" "$WORK_MODULE" --route design 2>&1); then
    _fail "unicode replan failed: $replanned"
    fixture_teardown; return
  fi
  manifest_rel=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate_manifest_relative"])' <<<"$replanned")
  manifest="$FIXTURE_DIR/$manifest_rel"
  before_manifest=$(shasum -a 256 "$manifest" | awk '{print $1}')
  before_old=$(git -C "$WORKTREE" rev-parse HEAD)
  before_main=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  if inspected=$(python3 "$REPLAN" inspect "$manifest" 2>&1); then
    if ! python3 - "$inspected" "$BASELINE_SHA" "$CANDIDATE_HEAD" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["status"] == "candidate_inspected"
assert result["read_only"] is True
assert result["diff_range"] == f"{sys.argv[2]}..{sys.argv[3]}"
assert "候选说明.txt" in result["changed_paths"]
assert "候选说明.txt" in result["diff"]
PY
    then
      _fail "inspect output did not expose the frozen unicode diff: $inspected"
    elif [ "$(shasum -a 256 "$manifest" | awk '{print $1}')" != "$before_manifest" ] \
      || [ "$(git -C "$WORKTREE" rev-parse HEAD)" != "$before_old" ] \
      || [ "$(git -C "$FIXTURE_DIR" rev-parse HEAD)" != "$before_main" ] \
      || [ -n "$(git -C "$WORKTREE" status --porcelain)" ] \
      || [ -n "$(git -C "$FIXTURE_DIR" status --porcelain)" ]; then
      _fail "inspect must be read-only"
    else
      pass_test
    fi
  else
    _fail "candidate inspect failed: $inspected"
  fi
  fixture_teardown
}

test_replan_retire_requires_reconcile_and_queues_cleanup() {
  start_test "replan: retire requires reconcile then uses pending cleanup"
  setup_replan_work iterating
  local replanned manifest manifest_rel retired
  if ! replanned=$(python3 "$REPLAN" "$WORK_MODULE" --route proposal 2>&1); then
    _fail "initial replan failed: $replanned"
    fixture_teardown; return
  fi
  manifest_rel=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["candidate_manifest_relative"])' <<<"$replanned")
  manifest="$FIXTURE_DIR/$manifest_rel"
  if python3 "$REPLAN" retire "$manifest" > /tmp/replan-out.$$ 2>&1; then
    _fail "retire without --reconciled must fail"
  elif [ ! -f "$manifest" ] || [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "unconfirmed retire must not mutate candidate lifecycle"
  elif retired=$(python3 "$REPLAN" retire "$manifest" --reconciled 2>&1); then
    if ! python3 - "$retired" "$FIXTURE_DIR/.runs/pending-cleanup.json" "$WORK_BRANCH" "$WORKTREE" "$WORKTREE/$MODULE_REL" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
queue = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert result["status"] == "candidate_retired"
assert result["reconciled"] is True
assert result["manifest_removed"] is True
assert result["pending_cleanup_enqueued"] is True
assert len(queue) == 1
entry = queue[0]
assert entry["kind"] == "work"
assert entry["branch"] == sys.argv[3]
assert entry["worktree"] == sys.argv[4]
assert entry["work_dir"] == sys.argv[5]
assert entry["phase"] == "active"
assert entry["integration_ref"] == "refs/heads/main"
PY
    then
      _fail "retire did not produce the expected cleanup handoff: $retired"
    elif [ -e "$manifest" ]; then
      _fail "retire must clear the candidate manifest"
    elif [ ! -d "$WORKTREE" ] || ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$WORK_BRANCH"; then
      _fail "retire must enqueue cleanup instead of deleting synchronously"
    else
      pass_test
    fi
  else
    _fail "confirmed retire failed: $retired"
  fi
  rm -f /tmp/replan-out.$$
  fixture_teardown
}

test_replan_contract_blocks_direct_designing_and_routes_upstream() {
  start_test "replan: active build cannot be overwritten by designing; upstream skills share the entry"
  setup_replan_work iterating
  local output
  if python3 "$FRAMEWORK_ROOT/scripts/build-contract.py" designing "$WORK_MODULE" > /tmp/replan-out.$$ 2>&1; then
    _fail "designing should reject an active build"
  elif ! grep -q "replan-work.py" /tmp/replan-out.$$; then
    _fail "designing block should name the shared replan entry"
  elif ! grep -q 'replan-work.py' "$FRAMEWORK_ROOT/skills/proposal/SKILL.md" \
    || ! grep -q -- '--route proposal' "$FRAMEWORK_ROOT/skills/proposal/SKILL.md" \
    || ! grep -q 'replan-work.py' "$FRAMEWORK_ROOT/skills/design/SKILL.md" \
    || ! grep -q -- '--route design' "$FRAMEWORK_ROOT/skills/design/SKILL.md" \
    || ! grep -q 'replan-work.py' "$FRAMEWORK_ROOT/skills/lark-review/SKILL.md" \
    || ! grep -q -- '--route "<proposal|design>"' "$FRAMEWORK_ROOT/skills/lark-review/SKILL.md"; then
    _fail "Proposal, design, and lark-review must share the replan entry"
  elif ! grep -q 'replan-work.py.*inspect' "$FRAMEWORK_ROOT/skills/design/SKILL.md" \
    || ! grep -q 'replan-work.py.*retire' "$FRAMEWORK_ROOT/skills/design/SKILL.md" \
    || ! grep -q 'replan-work.py.*inspect' "$FRAMEWORK_ROOT/skills/build/SKILL.md" \
    || ! grep -q 'replan-work.py.*retire' "$FRAMEWORK_ROOT/skills/build/SKILL.md"; then
    _fail "design and build must expose exact candidate inspect/retire commands"
  elif ! grep -q 'replan-work.py' "$FRAMEWORK_ROOT/skills/status/SKILL.md" \
    || ! grep -q 'list ' "$FRAMEWORK_ROOT/skills/design/SKILL.md" \
    || ! grep -q 'list ' "$FRAMEWORK_ROOT/skills/build/SKILL.md" \
    || ! grep -q 'list ' "$FRAMEWORK_ROOT/skills/status/SKILL.md"; then
    _fail "design, build, and status must discover all candidates across sessions"
  else
    pass_test
  fi
  rm -f /tmp/replan-out.$$
  fixture_teardown
}

test_replan_proposal_preserves_candidate
test_replan_design_preserves_candidate
test_replan_blocks_dirty_and_staged_worktrees
test_replan_blocks_dirty_main_and_mismatched_mode
test_replan_list_is_read_only_when_empty
test_replan_list_returns_every_candidate
test_replan_main_mode_preserves_implementation_and_fixed_range
test_replan_main_mode_recovers_staged_meta_deletion
test_replan_main_mode_rejects_candidate_removed_from_main_history
test_replan_recovers_after_old_side_committed
test_replan_is_idempotent_after_completion
test_replan_recovers_staged_git_rm_on_both_sides
test_replan_repeat_preserves_new_main_work_id
test_replan_rejects_ambiguous_main_and_master_mounts
test_replan_rejects_candidate_storage_symlinks
test_replan_list_rejects_candidate_storage_symlinks
test_replan_inspect_is_read_only_and_unicode_safe
test_replan_retire_requires_reconcile_and_queues_cleanup
test_replan_contract_blocks_direct_designing_and_routes_upstream

report_results "replan-work"
