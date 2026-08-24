#!/usr/bin/env bash
# design -> ready -> build currentness and scope handoff regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTEXT_PACK="$REPO_ROOT/scripts/context-pack.py"
BUILD_CONTRACT="$REPO_ROOT/scripts/build-contract.py"
PROJECT_DEFINITION="$REPO_ROOT/scripts/project-definition.py"
STATUS_VIEW="$REPO_ROOT/scripts/status-view.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-ready-contract.XXXXXX")
  MODULE="$T/docs/modules/access"
  TARGET="prototype/src/access"
  mkdir -p "$MODULE" "$T/$TARGET" "$T/.pm-workflow"

  write_equivalent_product_baseline "$T"
  printf '# Rules\n' > "$T/PRODUCT-RULES.md"
  printf '# Design\n' > "$T/DESIGN.md"
  printf '# Todo\n' > "$T/TODO.md"
  printf '# Modules\n' > "$T/docs/modules/INDEX.md"
  printf '# Discussion\n' > "$MODULE/discussion.md"
  printf '# Decisions\n' > "$MODULE/decisions.md"
  printf '# Access spec\n' > "$MODULE/spec.md"
  printf 'export const access = true\n' > "$T/$TARGET/index.ts"
  printf '.runs/\n' > "$T/.gitignore"

  git -C "$T" init -q -b main
  git -C "$T" config user.email "test@example.com"
  git -C "$T" config user.name "PMAI Test"
  python3 "$PROJECT_DEFINITION" write "$T" \
    --source docs/modules/access/spec.md \
    --type prototype \
    --root prototype \
    --entrypoint prototype \
    --language typescript \
    --runtime node \
    --framework react \
    --package-manager pnpm >/dev/null
  git -C "$T" add -A
  git -C "$T" commit -q -m "design basis"

  PACK="$T/.pm-workflow/context/access.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$PACK" >/dev/null
  APPROVED=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$PACK")
  CHECKPOINT=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" ready "$MODULE" \
    --approved-source-hash "$APPROVED" \
    --checkpoint-commit "$CHECKPOINT" \
    --context-pack "$PACK" \
    --target-path "$TARGET" \
    --design-revision 1 >/dev/null
  git -C "$T" add -- docs/modules/access/.work-meta.json
  git -C "$T" commit -q -m "mark ready"
}

teardown_fixture() {
  rm -rf "$T"
}

test_ready_to_build_starts_building() {
  start_test "ready-contract: ready_to_build → build start → building"
  setup_fixture

  if ! python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor docs/modules/access/spec.md \
    --mode main --executor native \
    --target-kind prototype --target-path "$TARGET" --entrypoint prototype \
    --iteration-check current-page --required-check prototype-boundary \
    >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "current ready contract should start a build"
    cat /tmp/ready-contract.err.$$ >&2
  elif ! python3 - "$MODULE/.work-meta.json" "$APPROVED" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
build = meta["build"]
assert "lifecycle_state" not in meta
assert "stage" not in meta
assert build["lifecycle_state"] == "building"
assert build["contract_version"] == 5
assert build["mode"] == "main"
assert build["executor"] == "native"
assert build["approved_source_hash"] == sys.argv[2]
assert build["target"]["paths"] == ["prototype/src/access"]
assert build["acceptance"]["iteration_checks"] == ["current-page"]
assert build["acceptance"]["final_checks"] == ["prototype-boundary"]
assert "required_checks" not in build["acceptance"]
PY
  then
    _fail "build start should preserve the approved design contract"
  else
    pass_test
  fi

  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_ready_currentness_and_legacy_cache_ignore() {
  start_test "ready-contract: current design passes; authority drift blocks status/build"
  setup_fixture

  if ! git -C "$T" check-ignore -q -- .pm-workflow/context/access.json; then
    _fail "legacy consumer context cache should be locally ignored"
    teardown_fixture
    return
  fi

  CURRENT="$T/.pm-workflow/context/access-current.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$CURRENT" >/dev/null
  if ! python3 "$BUILD_CONTRACT" validate-ready "$MODULE" --context-pack "$CURRENT" >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "fresh ready contract should validate"
    cat /tmp/ready-contract.err.$$ >&2
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi
  python3 - "$MODULE/.work-meta.json" "$CURRENT" <<'PY' || {
import json, sys
meta = json.load(open(sys.argv[1]))
pack = json.load(open(sys.argv[2]))
assert meta["approved_target"]["paths"] == ["prototype/src/access"]
assert pack["target"]["paths"] == ["prototype/src/access"]
assert pack["approved_source_hash"] == meta["approved_source_hash"]
PY
    _fail "approved target should round-trip through ready metadata and context pack"
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  }

  printf '权限模型更新\n' >> "$T/PRODUCT-RULES.md"
  STALE="$T/.pm-workflow/context/access-stale.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$STALE" >/dev/null
  if python3 "$BUILD_CONTRACT" validate-ready "$MODULE" --context-pack "$STALE" >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "authority drift must invalidate ready contract"
  elif ! grep -q "设计依据在批准后发生变化" /tmp/ready-contract.err.$$; then
    _fail "stale ready guidance missing"
    cat /tmp/ready-contract.err.$$ >&2
  else
    local route_out route_rc
    route_out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --route-only 2>&1)
    route_rc=$?
    NARRATIVE=$(python3 "$STATUS_VIEW" "$T" --narrative)
    if [[ "$NARRATIVE" != *"建造依据有变化，需要重新确认后才能继续"* ]] \
       || [[ "$NARRATIVE" != *"当前阶段：设计已定"* ]] \
       || [[ "$NARRATIVE" != *"下一阶段：构建中"* ]] \
       || [[ "$NARRATIVE" != *"当前可执行入口：/pmai-design"* ]] \
       || [[ "$NARRATIVE" != *"需要退回：设计依据在批准后发生变化"* ]] \
       || [[ "$NARRATIVE" == *"当前可执行入口：/pmai-build"* ]] \
       || [[ "$route_rc" != "2" ]] \
       || ! python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["status"] == "blocked"; assert d["route"] == "pmai-design"; assert "设计依据在批准后发生变化" in d["reason"]' <<<"$route_out"; then
      _fail "status and context route should both send stale ready work back to design"
      echo "$NARRATIVE" >&2
      echo "$route_out" >&2
    else
      pass_test
    fi
  fi

  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_legacy_ready_keeps_v1_hash_scope() {
  start_test "ready-contract: legacy ready keeps v1 full-document currentness"
  setup_fixture
  python3 - "$MODULE/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
meta = json.load(open(path))
meta.pop("source_hash_version", None)
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  LEGACY="$T/.pm-workflow/context/access-legacy.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$LEGACY" >/dev/null
  LEGACY_HASH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$LEGACY")
  python3 - "$MODULE/.work-meta.json" "$LEGACY_HASH" <<'PY'
import json, sys
path, approved = sys.argv[1:]
meta = json.load(open(path))
meta["approved_source_hash"] = approved
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$LEGACY" >/dev/null
  if ! python3 "$BUILD_CONTRACT" validate-ready "$MODULE" --context-pack "$LEGACY" \
    >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "legacy ready should validate with its original hash scope"
    cat /tmp/ready-contract.err.$$ >&2
  elif ! python3 - "$LEGACY" <<'PY'
import json, sys
pack = json.load(open(sys.argv[1]))
assert pack["source_hash_version"] == 1
assert "PRODUCT-STATE.md" in pack["source_hash_scope"]
assert "TODO.md" in pack["source_hash_scope"]
PY
  then
    _fail "legacy ready should preserve v1 context scope"
  elif python3 "$BUILD_CONTRACT" designing "$MODULE" >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "ordinary designing must not overwrite legacy ready"
  elif ! grep -q "reopen-ready" /tmp/ready-contract.err.$$; then
    _fail "ready overwrite rejection should name the explicit reopen entry"
  elif ! python3 "$BUILD_CONTRACT" reopen-ready "$MODULE" \
    --reason "PM 明确要求重新确认设计" >/dev/null; then
    _fail "legacy ready should be able to return to design through reopen-ready"
  elif ! python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" \
    --output "$LEGACY" >/dev/null; then
    _fail "redesign should compile a current context pack"
  elif ! python3 - "$LEGACY" <<'PY'
import json, sys
pack = json.load(open(sys.argv[1]))
assert pack["source_hash_version"] == 2
assert "PRODUCT-STATE.md" not in pack["source_hash_scope"]
assert "TODO.md" not in pack["source_hash_scope"]
PY
  then
    _fail "explicit redesign should upgrade the next approval to v2 scope"
  else
    pass_test
  fi
  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_designing_rejects_ready_without_mutation() {
  start_test "ready-contract: ordinary designing rejects ready and preserves the contract"
  setup_fixture
  local before after
  before=$(cat "$MODULE/.work-meta.json")
  if python3 "$BUILD_CONTRACT" designing "$MODULE" >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "ordinary designing must reject ready_to_build"
  else
    after=$(cat "$MODULE/.work-meta.json")
    if [ "$before" != "$after" ]; then
      _fail "rejected designing must not mutate ready metadata"
    elif ! grep -q "reopen-ready" /tmp/ready-contract.err.$$; then
      _fail "rejection must provide the explicit reopen entry"
    else
      pass_test
    fi
  fi
  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_reopen_ready_clears_authorization_and_records_reason() {
  start_test "ready-contract: explicit reopen clears ready bindings and preserves the reason"
  setup_fixture
  local reason="PM 要求重新确认租户接管规则" reopen_baseline
  reopen_baseline=$(git -C "$T" rev-parse HEAD)
  if ! python3 "$BUILD_CONTRACT" reopen-ready "$MODULE" --reason "$reason" \
    >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "explicit reopen-ready should return an unstarted ready module to designing"
    cat /tmp/ready-contract.err.$$ >&2
  elif ! python3 - "$MODULE/.work-meta.json" "$reason" "$reopen_baseline" <<'PY'
import json, sys
path, reason, checkpoint = sys.argv[1:]
meta = json.load(open(path))
assert meta["lifecycle_state"] == "designing"
assert "approved_source_hash" not in meta
assert "design_checkpoint_commit" not in meta
assert "approved_target" not in meta
assert meta["decision_gates"]["ready_authorization"] is None
assert meta["decision_gates"]["design_base_commit"] == checkpoint
reopen = meta["ready_reopen"]
assert reopen["status"] == "accepted"
assert reopen["reason"] == reason
assert reopen["from_lifecycle"] == "ready_to_build"
assert reopen["previous_ready"]["design_checkpoint_commit"]
PY
  then
    _fail "reopen-ready should clear ready bindings, reset the gate baseline, and retain the reason"
  else
    pass_test
  fi
  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_ready_retry_is_idempotent_and_refreshes_pack() {
  start_test "ready-contract: same checkpoint retry is idempotent and refreshes context pack"
  setup_fixture
  local first_meta first_bound first_verified retry_meta retry_bound retry_verified
  first_meta=$(python3 - "$MODULE/.work-meta.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
contract = meta["decision_gates"]
items = {
    item["gate_id"]: item.get("consumed_by")
    for item in contract["items"]
    if item.get("consumed_by") is not None
}
print(json.dumps({"meta": meta, "items": items}, sort_keys=True))
PY
)
  first_bound=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["items"])' <<<"$first_meta")
  first_verified=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["decision_gates"]["ready_authorization"]["verified_at"])' <<<"$first_meta")
  if ! python3 "$BUILD_CONTRACT" ready "$MODULE" \
    --approved-source-hash "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$PACK")" \
    --checkpoint-commit "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["design_checkpoint_commit"])' "$MODULE/.work-meta.json")" \
    --context-pack "$PACK" --target-path "$TARGET" --design-revision 1 >/dev/null; then
    _fail "same ready checkpoint should be retryable"
  else
    retry_meta=$(python3 - "$MODULE/.work-meta.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
contract = meta["decision_gates"]
items = {
    item["gate_id"]: item.get("consumed_by")
    for item in contract["items"]
    if item.get("consumed_by") is not None
}
print(json.dumps({"meta": meta, "items": items}, sort_keys=True))
PY
)
    retry_bound=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["items"])' <<<"$retry_meta")
    retry_verified=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["decision_gates"]["ready_authorization"]["verified_at"])' <<<"$retry_meta")
    if ! python3 - "$PACK" "$MODULE/.work-meta.json" "$first_bound" "$retry_bound" "$first_verified" "$retry_verified" <<'PY'
import json, sys
pack = json.load(open(sys.argv[1]))
meta = json.load(open(sys.argv[2]))
assert pack["approved_source_hash"] == meta["approved_source_hash"]
assert pack["source_hash"] == meta["approved_source_hash"]
assert sys.argv[3] == sys.argv[4]
assert sys.argv[5] == sys.argv[6]
PY
    then
      _fail "same-checkpoint retry must preserve receipt bindings and timestamp"
    else
      pass_test
    fi
  fi
  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_ready_retry_rejects_different_checkpoint() {
  start_test "ready-contract: different checkpoint retry fails without mutation"
  setup_fixture
  local before after current_head approved
  before=$(cat "$MODULE/.work-meta.json")
  current_head=$(git -C "$T" rev-parse HEAD)
  approved=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["approved_source_hash"])' "$MODULE/.work-meta.json")
  if python3 "$BUILD_CONTRACT" ready "$MODULE" \
    --approved-source-hash "$approved" --checkpoint-commit "$current_head" \
    --context-pack "$PACK" --target-path "$TARGET" --design-revision 1 \
    >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "different ready checkpoint must be rejected"
  else
    after=$(cat "$MODULE/.work-meta.json")
    if [ "$before" != "$after" ]; then
      _fail "different-checkpoint rejection must not mutate ready metadata"
    elif ! grep -q "reopen-ready" /tmp/ready-contract.err.$$; then
      _fail "different-checkpoint rejection should name reopen-ready"
    else
      pass_test
    fi
  fi
  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_ready_rejects_active_build_without_mutation() {
  start_test "ready-contract: ready cannot overwrite an active build"
  setup_fixture
  if ! python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor docs/modules/access/spec.md \
    --mode main --executor native \
    --target-kind prototype --target-path "$TARGET" --entrypoint prototype \
    --required-check prototype-boundary >/dev/null; then
    _fail "fixture should enter building before the ready overwrite check"
  else
    local before after
    before=$(cat "$MODULE/.work-meta.json")
    if python3 "$BUILD_CONTRACT" ready "$MODULE" \
      --approved-source-hash "$APPROVED" --checkpoint-commit "$CHECKPOINT" \
      --context-pack "$PACK" --target-path "$TARGET" --design-revision 1 \
      >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
      _fail "ready must reject an active build"
    else
      after=$(cat "$MODULE/.work-meta.json")
      if [ "$before" != "$after" ]; then
        _fail "active-build ready rejection must not mutate the build contract"
      elif ! grep -q "active build" /tmp/ready-contract.err.$$; then
        _fail "active-build ready rejection should explain that the existing build must continue"
      else
        pass_test
      fi
    fi
  fi
  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_ready_scope_and_dirty_preflight() {
  start_test "ready-contract: build reuses approved paths and blocks overlapping dirty work"
  setup_fixture

  if python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor docs/modules/access/spec.md \
    --mode worktree --executor codex --branch build-access --worktree .worktrees/build-access \
    --target-kind prototype --target-path prototype/src/other --entrypoint prototype \
    --required-check tests >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "build must reject a target path that design did not approve"
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi
  if ! grep -q "design 批准范围不一致" /tmp/ready-contract.err.$$; then
    _fail "divergent target guidance missing"
    cat /tmp/ready-contract.err.$$ >&2
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi

  printf 'export const changed = true\n' >> "$T/$TARGET/index.ts"
  if python3 "$BUILD_CONTRACT" check-dirty "$MODULE" >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "target-overlapping dirty work must block build preflight"
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi
  if ! grep -q "$TARGET/index.ts" /tmp/ready-contract.err.$$; then
    _fail "dirty preflight should identify the overlapping target path"
    cat /tmp/ready-contract.err.$$ >&2
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi
  if python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor docs/modules/access/spec.md \
    --mode worktree --executor codex --branch build-access --worktree .worktrees/build-access \
    --target-kind prototype --target-path "$TARGET" --entrypoint prototype \
    --required-check tests >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "build start must enforce the dirty-target gate itself"
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi
  if ! grep -q "本轮目标路径已有未提交改动" /tmp/ready-contract.err.$$; then
    _fail "build start dirty-target guidance missing"
    cat /tmp/ready-contract.err.$$ >&2
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi

  git -C "$T" add -- "$TARGET/index.ts"
  git -C "$T" commit -q -m "checkpoint existing target work"
  printf 'unrelated notes\n' > "$T/notes.txt"
  if ! python3 "$BUILD_CONTRACT" check-dirty "$MODULE" >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "unrelated dirty work should be preserved without blocking build"
    cat /tmp/ready-contract.err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_build_start_rejects_paths_outside_project_contract() {
  start_test "ready-contract: build rejects traversal anchors and absolute entrypoints"
  setup_fixture

  if python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor ../../outside \
    --mode worktree --executor codex --branch build-access --worktree .worktrees/build-access \
    --target-kind prototype --target-path "$TARGET" --entrypoint prototype \
    --required-check prototype-boundary >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "build must reject an anchor outside the repository"
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi
  if ! grep -q "仓内相对路径" /tmp/ready-contract.err.$$; then
    _fail "traversal anchor guidance missing"
    cat /tmp/ready-contract.err.$$ >&2
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi

  if python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor docs/modules/access/spec.md \
    --mode worktree --executor codex --branch build-access --worktree .worktrees/build-access \
    --target-kind prototype --target-path "$TARGET" --entrypoint /tmp/outside \
    --required-check prototype-boundary >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "build must reject an absolute entrypoint"
    rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
    teardown_fixture
    return
  fi
  if ! grep -q "仓内相对路径" /tmp/ready-contract.err.$$; then
    _fail "absolute entrypoint guidance missing"
    cat /tmp/ready-contract.err.$$ >&2
  elif ! python3 - "$MODULE/.work-meta.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["lifecycle_state"] == "ready_to_build"
assert "build" not in meta
PY
  then
    _fail "rejected starts must leave the ready contract unchanged"
  else
    pass_test
  fi

  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_build_start_requires_project_definition() {
  start_test "ready-contract: build refuses a ready record without project.yml"
  setup_fixture
  rm -f "$T/.pm-workflow/project.yml"

  if python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor docs/modules/access/spec.md \
    --mode worktree --executor codex --branch build-access --worktree .worktrees/build-access \
    --target-kind prototype --target-path "$TARGET" --entrypoint prototype \
    --required-check prototype-boundary >/tmp/ready-contract.$$ 2>/tmp/ready-contract.err.$$; then
    _fail "build must reject a missing project.yml"
  elif ! grep -q "project.yml" /tmp/ready-contract.err.$$; then
    _fail "missing project definition guidance absent"
    cat /tmp/ready-contract.err.$$ >&2
  elif ! python3 - "$MODULE/.work-meta.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["lifecycle_state"] == "ready_to_build"
assert "build" not in meta
PY
  then
    _fail "missing project.yml failure must leave ready state unchanged"
  else
    pass_test
  fi

  rm -f /tmp/ready-contract.$$ /tmp/ready-contract.err.$$
  teardown_fixture
}

test_status_uses_attached_worktree_root_for_ready_currentness() {
  start_test "ready-contract: status 在 attached worktree 使用该工作环境的 currentness"
  setup_fixture
  local worktree="$T/.worktrees/build-access-ready"
  git -C "$T" worktree add -q -b build-access-ready "$worktree" main
  mkdir -p "$worktree/docs/modules/access"
  cp "$MODULE/discussion.md" "$worktree/docs/modules/access/discussion.md"
  cp "$MODULE/decisions.md" "$worktree/docs/modules/access/decisions.md"
  cp "$MODULE/spec.md" "$worktree/docs/modules/access/spec.md"
  cp "$MODULE/.work-meta.json" "$worktree/docs/modules/access/.work-meta.json"
  python3 - "$worktree/docs/modules/access/.work-meta.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["branch"] = "build-access-ready"
meta["worktree"] = ".worktrees/build-access-ready"
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$worktree" add -- docs/modules/access
  git -C "$worktree" commit -qm "attach ready work"

  local out
  out=$(python3 "$STATUS_VIEW" "$T" --narrative 2>&1)
  if echo "$out" | grep -q "当前阶段：设计已定" \
     && echo "$out" | grep -q "下一阶段：构建中" \
     && echo "$out" | grep -q "当前可执行入口：/pmai-build" \
     && ! echo "$out" | grep -q "需要退回："; then
    pass_test
  else
    _fail "attached ready work should use its own repository root: $out"
  fi
  git -C "$T" worktree remove "$worktree" --force >/dev/null 2>&1 || true
  teardown_fixture
}

test_ready_to_build_starts_building
test_ready_currentness_and_legacy_cache_ignore
test_legacy_ready_keeps_v1_hash_scope
test_designing_rejects_ready_without_mutation
test_reopen_ready_clears_authorization_and_records_reason
test_ready_retry_is_idempotent_and_refreshes_pack
test_ready_retry_rejects_different_checkpoint
test_ready_rejects_active_build_without_mutation
test_ready_scope_and_dirty_preflight
test_build_start_rejects_paths_outside_project_contract
test_build_start_requires_project_definition
test_status_uses_attached_worktree_root_for_ready_currentness

report_results "ready-contract"
