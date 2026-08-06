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

  printf '# Product\n' > "$T/PRODUCT.md"
  printf '# State\n' > "$T/PRODUCT-STATE.md"
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
    NARRATIVE=$(python3 "$STATUS_VIEW" "$T" --narrative)
    if [[ "$NARRATIVE" != *"设计依据有变化，需要重新确认后才能构建"* ]] \
       || [[ "$NARRATIVE" != *"继续 /pmai-design"* ]]; then
      _fail "status should not present stale ready state as buildable"
      echo "$NARRATIVE" >&2
    else
      pass_test
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

test_ready_currentness_and_legacy_cache_ignore
test_ready_scope_and_dirty_preflight
test_build_start_rejects_paths_outside_project_contract
test_build_start_requires_project_definition

report_results "ready-contract"
