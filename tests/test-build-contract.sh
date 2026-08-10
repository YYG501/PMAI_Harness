#!/usr/bin/env bash
# Build contract helper regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
CONTEXT_PACK="$FRAMEWORK_ROOT/scripts/context-pack.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"
PROTOTYPE_CONTRACT_ARGS=(
  --target-kind prototype
  --target-path prototype/
  --entrypoint prototype/
  --required-check prototype-boundary
  --required-check browser-smoke
  --required-check coverage
  --required-check visual
  --required-check behavior
)

setup_contract_fixture() {
  local project_type="${1:-prototype}"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-contract.XXXXXX")
  MODULE_DIR="$T/docs/modules/pet-import"
  mkdir -p "$MODULE_DIR" "$T/.pm-workflow"
  cat > "$MODULE_DIR/.work-meta.json" <<'JSON'
{
  "id": "work-001",
  "name": "pet import",
  "branch": "build-pet-import",
  "stage": 1,
  "status": "active",
  "lifecycle_state": "designing"
}
JSON
  printf '# Product\n' > "$T/PRODUCT.md"
  printf '# State\n' > "$T/PRODUCT-STATE.md"
  printf '# Rules\n' > "$T/PRODUCT-RULES.md"
  printf '# Design\n' > "$T/DESIGN.md"
  printf '# Todo\n' > "$T/TODO.md"
  printf '# Modules\n' > "$T/docs/modules/INDEX.md"
  printf '# Pet import spec\n' > "$MODULE_DIR/spec.md"
  printf '# Discussion\n' > "$MODULE_DIR/discussion.md"
  printf '# Decisions\n' > "$MODULE_DIR/decisions.md"
  printf '.pm-workflow/context/\n' > "$T/.gitignore"

  git -C "$T" init -q -b main
  git -C "$T" config user.email "test@example.com"
  git -C "$T" config user.name "PMAI Test"
  if [ "$project_type" = "product" ]; then
    mkdir -p "$T/src/pets"
    printf 'export const pets = true\n' > "$T/src/pets/index.ts"
    PROJECT_TARGET="src/pets"
  else
    mkdir -p "$T/prototype"
    printf '<!doctype html>\n' > "$T/prototype/index.html"
    PROJECT_TARGET="prototype"
  fi
  python3 "$PROJECT_DEFINITION" write "$T" \
    --source docs/modules/pet-import/spec.md \
    --type "$project_type" \
    --root "$PROJECT_TARGET" \
    --entrypoint "$PROJECT_TARGET" \
    --language typescript \
    --runtime node \
    --framework test \
    --package-manager none >/dev/null
  git -C "$T" add -A
  git -C "$T" commit -q -m "design basis"

  local pack="$T/.pm-workflow/context/pet-import.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null
  SOURCE_HASH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$pack")
  local checkpoint
  checkpoint=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" ready "$MODULE_DIR" \
    --approved-source-hash "$SOURCE_HASH" \
    --checkpoint-commit "$checkpoint" \
    --context-pack "$pack" \
    --target-path "$PROJECT_TARGET" \
    --design-revision 1 >/dev/null
}

teardown_contract_fixture() {
  rm -rf "$T"
}

request_finalization() {
  if python3 - "$MODULE_DIR/.work-meta.json" <<'PY' >/dev/null 2>&1
import json, sys
build = json.load(open(sys.argv[1]))["build"]
finalization = build.get("finalization") or {}
raise SystemExit(0 if finalization.get("requested_at") else 1)
PY
  then
    return 0
  fi
  python3 "$BUILD_CONTRACT" request-finalization "$MODULE_DIR" >/dev/null
}

write_prototype_boundary_audit() {
  request_finalization
  AUDIT_DIR="$T/.pm-workflow/audits/pet-import"
  mkdir -p "$AUDIT_DIR"
  python3 - "$MODULE_DIR/.work-meta.json" "$AUDIT_DIR/prototype-boundary.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
build = meta["build"]
artifact = {
    "schema_version": 1,
    "check": "prototype-boundary",
    "status": "pass",
    "target_kind": "prototype",
    "implementation_mode": "interactive-simulation",
    "policy_hash": build["delivery_policy_hash"],
    "source_hash": build["approved_source_hash"],
    "baseline_sha": build.get("baseline_sha"),
    "implementation_commit": build["implementation_commit"],
    "target_paths": build["target"]["paths"],
    "changed_paths": ["prototype/page.tsx"],
    "outside_target_paths": [],
    "detected_signals": [],
    "unapproved_signals": [],
    "approved_real_edges": [],
    "simulated_capabilities": ["数据持久化"],
    "semantic_review": {"confirmed_no_real_system_changes": True, "reviewed_at": "2026-07-17T10:00:00+08:00"},
}
json.dump(artifact, open(sys.argv[2], "w"), ensure_ascii=False)
PY
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name prototype-boundary --status pass \
    --artifact ".pm-workflow/audits/pet-import/prototype-boundary.json" >/dev/null
}

write_clean_audits() {
  AUDIT_DIR="$T/.pm-workflow/audits/pet-import"
  mkdir -p "$AUDIT_DIR"
  cat > "$AUDIT_DIR/coverage.json" <<'JSON'
{"items":[{"name":"导入入口","status":"built","note":""}]}
JSON
  cat > "$AUDIT_DIR/browser-smoke.json" <<'JSON'
{"status":"pass","active_browser_smoke":true,"active_design_smoke":false}
JSON
  cat > "$AUDIT_DIR/visual.json" <<'JSON'
{"status":"pass","findings":[]}
JSON
  cat > "$AUDIT_DIR/behavior.json" <<'JSON'
{"status":"pass","passed":2,"total":2,"note":""}
JSON
  echo "# Legacy v1 acceptance report" > "$AUDIT_DIR/synthesis.md"
  write_prototype_boundary_audit
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name browser-smoke --status pass --artifact ".pm-workflow/audits/pet-import/browser-smoke.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name coverage --status pass --artifact ".pm-workflow/audits/pet-import/coverage.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name visual --status pass --artifact ".pm-workflow/audits/pet-import/visual.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name behavior --status pass --artifact ".pm-workflow/audits/pet-import/behavior.json" >/dev/null
}

write_limited_browser_audits() {
  AUDIT_DIR="$T/.pm-workflow/audits/pet-import"
  mkdir -p "$AUDIT_DIR"
  cat > "$AUDIT_DIR/coverage.json" <<'JSON'
{"items":[{"name":"导入入口","status":"built","note":""}]}
JSON
  cat > "$AUDIT_DIR/browser-smoke.json" <<'JSON'
{"status":"limited","active_browser_smoke":true,"active_design_smoke":false,"note":"browser 工具不可用"}
JSON
  cat > "$AUDIT_DIR/visual.json" <<'JSON'
{"status":"limited","findings":[],"note":"sandbox 无法启动浏览器截图"}
JSON
  cat > "$AUDIT_DIR/behavior.json" <<'JSON'
{"status":"skipped","passed":0,"total":2,"note":"browser 工具不可用"}
JSON
  echo "# Legacy v1 acceptance report" > "$AUDIT_DIR/synthesis.md"
  write_prototype_boundary_audit
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name browser-smoke --status limited --artifact ".pm-workflow/audits/pet-import/browser-smoke.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name coverage --status pass --artifact ".pm-workflow/audits/pet-import/coverage.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name visual --status limited --artifact ".pm-workflow/audits/pet-import/visual.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name behavior --status skipped --artifact ".pm-workflow/audits/pet-import/behavior.json" >/dev/null
}

mark_review_ready() {
  python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/dev/null
}

test_contract_lifecycle() {
  start_test "build-contract: start → commit → accept → validate-close"
  setup_contract_fixture

  if ! python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree \
    --executor codex \
    --builder-profile codex \
    --builder-json '{"model":"gpt-5.4","thinking":"high","sandbox":"workspace-write"}' \
    --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "start should succeed"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should fail before implementation_commit"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "implementation_commit" /tmp/build-contract.err.$$; then
    _fail "missing implementation guidance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit "def456" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$
  request_finalization
  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should fail before PM acceptance"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "pm_accepted_at" /tmp/build-contract.err.$$; then
    _fail "missing PM acceptance guidance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  if python3 "$BUILD_CONTRACT" accept "$MODULE_DIR" --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "accept should fail before review-ready"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "验收就绪快照" /tmp/build-contract.err.$$; then
    _fail "missing review-ready guidance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  write_clean_audits
  mark_review_ready || {
    _fail "review-ready should succeed after fresh evidence"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }
  python3 "$BUILD_CONTRACT" accept "$MODULE_DIR" --accepted-at "2026-06-28T10:00:00+08:00" >/dev/null
  if ! python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should succeed after commit and acceptance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
meta = json.load(open(sys.argv[1]))
build = meta["build"]
assert meta["stage"] == 2
assert build["mode"] == "worktree"
assert build["contract_version"] == 4
assert build["target"]["kind"] == "prototype"
assert build["delivery_policy"]["implementation_mode"] == "interactive-simulation"
assert build["delivery_policy"]["required_check"] == "prototype-boundary"
assert len(build["delivery_policy_hash"]) == 64
assert build["lifecycle_state"] == "final_check"
assert build["design_revision"] == 1
assert build["approved_source_hash"]
assert build["docs_status"] == "pending"
assert build["executor"] == "codex"
assert build["builder_profile"] == "codex"
assert build["builder"]["model"] == "gpt-5.4"
assert build["builder"]["thinking"] == "high"
assert build["builder"]["sandbox"] == "workspace-write"
assert build["implementation_commit"] == "def456"
assert build["pm_accepted_at"] == "2026-06-28T10:00:00+08:00"
assert build["acceptance"]["ready_commit"] == "def456"
assert build["acceptance"]["ready_source_hash"] == build["approved_source_hash"]
assert build["finalization"]["requested_commit"] == "def456"
PY
    _fail "written build contract fields mismatch"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }

  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_rejects_missing_build() {
  start_test "build-contract: validate-close rejects missing build object"
  setup_contract_fixture

  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should reject missing build object"
  elif grep -q "缺少 build 合同" /tmp/build-contract.err.$$; then
    pass_test
  else
    _fail "stderr missing missing contract guidance"
    cat /tmp/build-contract.err.$$ >&2
  fi

  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_start_requires_adaptive_inputs() {
  start_test "build-contract v2: start has no prototype or fixed-check defaults"
  setup_contract_fixture

  if python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree --executor codex --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" --baseline-sha abc123 \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "v2 start without adaptive target/check inputs should fail"
  elif grep -q -- '--target-kind' /tmp/build-contract.err.$$; then
    pass_test
  else
    _fail "missing adaptive inputs should fail with explicit argument guidance"
    cat /tmp/build-contract.err.$$ >&2
  fi

  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_start_rejects_missing_ready_meta() {
  start_test "build-contract: start rejects missing ready contract"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-contract.XXXXXX")
  MODULE_DIR="$T/docs/modules/pet-import"
  mkdir -p "$MODULE_DIR"

  if python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode main \
    --executor claude-code \
    --branch main \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "start should not create a build contract without ready_to_build"
  elif [ -e "$MODULE_DIR/.work-meta.json" ]; then
    _fail "failed start should not create .work-meta.json"
  elif grep -q "ready_to_build" /tmp/build-contract.err.$$; then
    pass_test
  else
    _fail "missing ready gate guidance"
    cat /tmp/build-contract.err.$$ >&2
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_designing_creates_new_module_directory() {
  start_test "build-contract: designing creates a missing module directory"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-contract.XXXXXX")
  MODULE_DIR="$T/docs/modules/new-access-flow"

  if ! python3 "$BUILD_CONTRACT" designing "$MODULE_DIR" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "designing should create a new module directory"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["id"].startswith("work-new-access-flow-")
assert meta["name"] == "new-access-flow"
assert meta["status"] == "active"
assert meta["lifecycle_state"] == "designing"
PY
    _fail "designing meta fields mismatch"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }
  FIRST_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' \
    "$MODULE_DIR/.work-meta.json")
  rm -f "$MODULE_DIR/.work-meta.json"
  python3 "$BUILD_CONTRACT" designing "$MODULE_DIR" >/dev/null
  if ! python3 - "$MODULE_DIR/.work-meta.json" "$FIRST_ID" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["id"] != sys.argv[2]
assert meta["id"].startswith("work-new-access-flow-")
PY
  then
    _fail "reopening a closed module should create a distinct work round"
  else
    pass_test
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_new_round_gets_isolated_audit_dir() {
  start_test "build-contract: new work round gets an isolated audit directory"
  setup_contract_fixture product
  python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
meta = json.load(open(path))
meta["id"] = "work-pet-import-20260810120000-a1b2c3d4"
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null || {
      _fail "new work round should start"; teardown_contract_fixture; return;
    }
  if python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["audit_dir"] == ".pm-workflow/audits/pet-import/work-pet-import-20260810120000-a1b2c3d4"
PY
  then
    pass_test
  else
    _fail "new work round audit directory should be bound to its work id"
  fi
  teardown_contract_fixture
}

test_contract_final_currentness_accepts_ordered_deltas() {
  start_test "build-contract: final currentness validates one and multiple accepted deltas"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null
  python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind product-behavior \
    --summary "支持批量导入" --affected-surface "导入页" \
    --accepted-at "2026-08-10T12:00:00+08:00" >/dev/null
  if ! python3 "$BUILD_CONTRACT" validate-final-currentness "$MODULE_DIR" >/dev/null; then
    _fail "single accepted delta should pass final currentness"
    teardown_contract_fixture; return
  fi
  python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind product-behavior \
    --summary "失败项可重试" --affected-surface "结果页" \
    --accepted-at "2026-08-10T12:05:00+08:00" >/dev/null
  if ! python3 "$BUILD_CONTRACT" validate-final-currentness "$MODULE_DIR" >/dev/null; then
    _fail "multiple ordered accepted deltas should pass final currentness"
    teardown_contract_fixture; return
  fi
  python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
meta = json.load(open(path))
meta["build"]["accepted_deltas"].reverse()
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  if python3 "$BUILD_CONTRACT" validate-final-currentness "$MODULE_DIR" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "reordered accepted deltas must fail final currentness"
  elif ! grep -q "design 依据 + accepted deltas 不一致" /tmp/build-contract.err.$$; then
    _fail "reordered delta guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  else
    pass_test
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_complete_accepts_only_ready_candidate() {
  start_test "build-contract: complete accepts only the already checked candidate"
  setup_contract_fixture

  if ! python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree \
    --executor codex \
    --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "start should succeed"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit "draft123" >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit "def456" >/dev/null
  write_clean_audits
  mark_review_ready || {
    _fail "review-ready should succeed"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }
  if ! python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" \
    --implementation-commit "def456" \
    --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "complete should succeed"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  if ! python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should succeed after complete"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
meta = json.load(open(sys.argv[1]))
build = meta["build"]
assert build["implementation_commit"] == "def456"
assert build["pm_accepted_at"] == "2026-06-28T10:00:00+08:00"
assert build["implementation_committed_at"]
PY
    _fail "complete fields mismatch"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }

  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_limited_browser_cannot_be_excepted() {
  start_test "build-contract: v2 UI requires active browser even after other exceptions"
  setup_contract_fixture

  if ! python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree \
    --executor codex \
    --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "start should succeed"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit "def456" >/dev/null
  write_limited_browser_audits

  if python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "review-ready should reject skipped browser evidence without PM exception"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "主动浏览器能力" /tmp/build-contract.err.$$; then
    _fail "stderr should explain active browser requirement"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  if ! python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "PM 确认本轮浏览器工具受限，先接受页面返回检查风险" \
    --check visual --check behavior \
    --accepted-at "2026-06-28T10:05:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "audit-exception should record PM acceptance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  if python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "review-ready must not allow limited browser after exception"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "主动浏览器能力" /tmp/build-contract.err.$$; then
    _fail "browser hard gate should remain after exception"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_missing_browser_smoke_blocks_clean_audits() {
  start_test "build-contract: clean visual/behavior still require active browser smoke"
  setup_contract_fixture

  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree \
    --executor codex \
    --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "start should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit "def456" >/dev/null

  write_clean_audits
  rm -f "$T/.pm-workflow/audits/pet-import/browser-smoke.json"
  if python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "review-ready should reject missing browser-smoke.json"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if grep -q "浏览器主动 smoke" /tmp/build-contract.err.$$; then
    pass_test
  else
    _fail "stderr should explain missing active browser smoke"
    cat /tmp/build-contract.err.$$ >&2
  fi

  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_browser_smoke_limited_blocks_passed_browser_audits() {
  start_test "build-contract: limited browser smoke triggers v2 active-browser hard gate"
  setup_contract_fixture

  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree \
    --executor codex \
    --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "start should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit "def456" >/dev/null

  write_clean_audits
  cat > "$T/.pm-workflow/audits/pet-import/browser-smoke.json" <<'JSON'
{"status":"limited","active_browser_smoke":true,"active_design_smoke":false,"note":"browser 工具不可用"}
JSON
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name browser-smoke --status limited \
    --artifact ".pm-workflow/audits/pet-import/browser-smoke.json" >/dev/null
  python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "PM 确认本轮浏览器工具受限，先接受风险" \
    --check visual --check behavior \
    --accepted-at "2026-06-28T10:05:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "audit-exception should record PM acceptance"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
    }

  if python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "review-ready should reject passed browser audits when browser smoke is limited"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if grep -q "主动浏览器能力" /tmp/build-contract.err.$$; then
    pass_test
  else
    _fail "stderr should explain active browser hard gate"
    cat /tmp/build-contract.err.$$ >&2
  fi

  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_behavior_fail_blocks_close() {
  start_test "build-contract: behavior audit fail blocks close"
  setup_contract_fixture

  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree \
    --executor codex \
    --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "start should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit "def456" >/dev/null
  write_clean_audits
  cat > "$T/.pm-workflow/audits/pet-import/behavior.json" <<'JSON'
{"status":"fail","passed":1,"total":2,"note":"确认按钮点击无反应"}
JSON
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name behavior --status fail \
    --artifact ".pm-workflow/audits/pet-import/behavior.json" >/dev/null

  if python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "PM 接受行为检查缺口" --check behavior >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ \
    && python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "review-ready should reject behavior fail even with audit exception"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if grep -q "行为审未通过" /tmp/build-contract.err.$$; then
    pass_test
  else
    _fail "stderr should explain behavior fail block"
    cat /tmp/build-contract.err.$$ >&2
  fi

  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_v2_rejects_stale_evidence_and_invalidates_on_delta() {
  start_test "build-contract v2: evidence binds source hash + commit; accepted delta invalidates it"
  setup_contract_fixture product

  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree --executor codex --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" --baseline-sha abc123 \
    --target-kind product --target-path "src/pets/" --entrypoint "src/pets/" \
    --approved-source-hash "$SOURCE_HASH" --required-check tests >/dev/null || {
      _fail "v2 start should succeed"; teardown_contract_fixture; return;
  }
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  request_finalization
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit stale-commit >/dev/null

  if python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "stale evidence commit should block review readiness"
  elif ! grep -q "commit 与当前 implementation_commit 不一致" /tmp/build-contract.err.$$; then
    _fail "stale commit guidance missing"
    cat /tmp/build-contract.err.$$ >&2
  else
    python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
      --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null
    mark_review_ready || {
      _fail "fresh product evidence should become review-ready"; teardown_contract_fixture; return;
    }
    python3 "$BUILD_CONTRACT" accept "$MODULE_DIR" >/dev/null
    python3 "$BUILD_CONTRACT" validate-land "$MODULE_DIR" >/dev/null || {
      _fail "fresh product evidence should pass"; teardown_contract_fixture; return;
    }
    python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind product-model \
      --summary "角色模型改为能力与数据范围分离" --affected-surface "角色详情页" >/dev/null
    python3 - "$MODULE_DIR/.work-meta.json" "$SOURCE_HASH" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["design_revision"] == 2
assert build["approved_source_hash"] != sys.argv[2]
assert build["acceptance"]["evidence"] == []
assert build["implementation_commit"] is None
assert build["lifecycle_state"] == "iterating"
PY
      _fail "accepted delta should increment revision and invalidate evidence"
      teardown_contract_fixture; return
    }
    pass_test
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_v2_post_land_docs_resume() {
  start_test "build-contract v2: landed → documenting/failed → documenting/complete"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ --approved-source-hash "$SOURCE_HASH" \
    --required-check tests >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  request_finalization
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null
  mark_review_ready
  python3 "$BUILD_CONTRACT" accept "$MODULE_DIR" >/dev/null
  python3 "$BUILD_CONTRACT" landed "$MODULE_DIR" --landed-commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" docs-start "$MODULE_DIR" >/dev/null
  python3 "$BUILD_CONTRACT" docs-fail "$MODULE_DIR" --reason "规格覆盖表缺一页" >/dev/null
  python3 "$BUILD_CONTRACT" docs-start "$MODULE_DIR" >/dev/null
  python3 "$BUILD_CONTRACT" docs-complete "$MODULE_DIR" >/dev/null
  if python3 "$BUILD_CONTRACT" validate-docs "$MODULE_DIR" >/dev/null; then
    pass_test
  else
    _fail "post-land docs should resume without re-landing"
  fi
  teardown_contract_fixture
}

test_contract_v2_new_implementation_invalidates_evidence() {
  start_test "build-contract v2: new implementation commit clears old evidence"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ --approved-source-hash "$SOURCE_HASH" \
    --required-check tests >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  request_finalization
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v2 >/dev/null

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["implementation_commit"] == "commit-v2"
assert build["acceptance"]["evidence"] == []
assert build["acceptance"]["ready_at"] is None
assert build["acceptance"]["ready_commit"] is None
assert build["pm_accepted_at"] is None
assert build["lifecycle_state"] == "iterating"
PY
    _fail "new implementation commit should invalidate evidence"
    teardown_contract_fixture; return
  }
  pass_test
  teardown_contract_fixture
}

test_contract_v2_new_evidence_invalidates_review_ready() {
  start_test "build-contract v2: changed evidence invalidates review-ready snapshot"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ \
    --approved-source-hash "$SOURCE_HASH" --required-check tests >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  request_finalization
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null
  mark_review_ready
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null

  if python3 "$BUILD_CONTRACT" accept "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "accept must reject a snapshot invalidated by changed evidence"
  elif ! grep -q "验收就绪快照" /tmp/build-contract.err.$$; then
    _fail "changed evidence should report missing review-ready snapshot"
    cat /tmp/build-contract.err.$$ >&2
  else
    pass_test
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_v2_iterating_clears_acceptance_and_readiness() {
  start_test "build-contract v2: returning to iterating clears acceptance and readiness"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ \
    --approved-source-hash "$SOURCE_HASH" --required-check tests >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  request_finalization
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null
  mark_review_ready
  python3 "$BUILD_CONTRACT" accept "$MODULE_DIR" >/dev/null
  python3 "$BUILD_CONTRACT" iterating "$MODULE_DIR" >/dev/null

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["lifecycle_state"] == "iterating"
assert build["pm_accepted_at"] is None
assert build["acceptance"]["ready_at"] is None
assert build["acceptance"]["ready_commit"] is None
assert len(build["acceptance"]["evidence"]) == 1
PY
    _fail "iterating should clear acceptance/readiness while preserving reusable evidence"
    teardown_contract_fixture; return
  }
  pass_test
  teardown_contract_fixture
}

test_contract_v2_rejects_illegal_lifecycle_jumps() {
  start_test "build-contract v2: cannot document or land before final_check"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ --approved-source-hash "$SOURCE_HASH" \
    --required-check tests >/dev/null

  if python3 "$BUILD_CONTRACT" docs-complete "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "docs-complete must not jump from building"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if python3 "$BUILD_CONTRACT" landed "$MODULE_DIR" --landed-commit commit-v1 >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "landed must not jump from building"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pretending \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "invalid evidence status must be rejected"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_v4_finalization_gate_and_iteration_lane() {
  start_test "build-contract v4: final checks require PM request; validation fixes rebind; PM feedback resumes iteration"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ \
    --approved-source-hash "$SOURCE_HASH" --iteration-check typecheck --final-check tests >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --lane iteration \
    --name typecheck --status pass --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null || {
      _fail "iteration evidence should be recordable before finalization"; teardown_contract_fixture; return;
    }
  if python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "final evidence must be blocked before PM requests finalization"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  elif ! grep -q "PM 尚未请求定稿" /tmp/build-contract.err.$$; then
    _fail "missing finalization-gate guidance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 "$BUILD_CONTRACT" request-finalization "$MODULE_DIR" \
    --requested-at "2026-07-17T10:00:00+08:00" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash "$SOURCE_HASH" --commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" request-finalization "$MODULE_DIR" >/dev/null
  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert len(build["acceptance"]["evidence"]) == 1
assert build["finalization"]["requested_at"] == "2026-07-17T10:00:00+08:00"
PY
    _fail "repeated finalization request should be idempotent"
    teardown_contract_fixture; return
  }
  mark_review_ready || {
    _fail "requested finalization should allow a complete final snapshot"; teardown_contract_fixture; return;
  }

  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v2 >/dev/null
  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["finalization"]["requested_at"] == "2026-07-17T10:00:00+08:00"
assert build["finalization"]["requested_commit"] == "commit-v2"
assert build["finalization"]["rebound_at"]
assert build["acceptance"]["evidence"] == []
assert build["acceptance"]["iteration_evidence"] == []
PY
    _fail "validation-fix commit should rebind finalization and invalidate old checks"
    teardown_contract_fixture; return
  }
  python3 "$BUILD_CONTRACT" resume-iteration "$MODULE_DIR" >/dev/null
  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["lifecycle_state"] == "iterating"
assert build["finalization"]["requested_at"] is None
assert build["finalization"]["requested_commit"] is None
assert build["acceptance"]["evidence"] == []
PY
    _fail "PM feedback should cancel the finalization request"
    teardown_contract_fixture; return
  }
  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_v4_requires_and_validates_prototype_boundary() {
  start_test "build-contract v4: prototype boundary is required, current, and non-exceptable"
  setup_contract_fixture
  if python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind prototype --target-path prototype/ --entrypoint prototype/ \
    --required-check browser-smoke --required-check coverage --required-check visual --required-check behavior \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "prototype start without boundary check should fail"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  elif ! grep -q "prototype-boundary" /tmp/build-contract.err.$$; then
    _fail "missing prototype-boundary guidance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 "${PROTOTYPE_CONTRACT_ARGS[@]}" >/dev/null || {
      _fail "prototype start with boundary check should succeed"
      teardown_contract_fixture; return
    }
  if python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "尝试跳过原型边界" --check prototype-boundary \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "prototype-boundary must not accept an exception"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  elif ! grep -q "不允许 exception" /tmp/build-contract.err.$$; then
    _fail "prototype-boundary exception rejection guidance missing"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_v4_accepts_one_hard_browser_batch() {
  start_test "build-contract v4: one browser batch replaces three separate UI checks"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets --entrypoint src/pets \
    --final-check browser-acceptance >/dev/null || {
      _fail "browser batch contract should start"; teardown_contract_fixture; return;
    }
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  request_finalization
  mkdir -p "$T/.pm-workflow/audits/pet-import"
  python3 - "$MODULE_DIR/.work-meta.json" "$T/.pm-workflow/audits/pet-import/browser-acceptance.json" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
artifact = {
    "schema_version": 1,
    "check": "browser-acceptance",
    "status": "pass",
    "implementation_commit": build["implementation_commit"],
    "source_hash": build["approved_source_hash"],
    "active_browser_smoke": True,
    "single_chain_invocation": True,
    "covers": ["smoke", "visual", "behavior"],
    "flows": [{"id": "pet-list", "status": "pass"}],
}
json.dump(artifact, open(sys.argv[2], "w"))
PY
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" \
    --name browser-acceptance --status pass \
    --artifact ".pm-workflow/audits/pet-import/browser-acceptance.json" >/dev/null
  if ! python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "one valid browser batch should satisfy the UI hard gate"
    cat /tmp/build-contract.err.$$ >&2
  elif python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "try skip" --check browser-acceptance \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "browser-acceptance must remain non-exceptable"
  else
    pass_test
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_lifecycle
test_contract_rejects_missing_build
test_contract_start_requires_adaptive_inputs
test_contract_start_rejects_missing_ready_meta
test_contract_designing_creates_new_module_directory
test_contract_new_round_gets_isolated_audit_dir
test_contract_final_currentness_accepts_ordered_deltas
test_contract_complete_accepts_only_ready_candidate
test_contract_limited_browser_cannot_be_excepted
test_contract_missing_browser_smoke_blocks_clean_audits
test_contract_browser_smoke_limited_blocks_passed_browser_audits
test_contract_behavior_fail_blocks_close
test_contract_v2_rejects_stale_evidence_and_invalidates_on_delta
test_contract_v2_post_land_docs_resume
test_contract_v2_new_implementation_invalidates_evidence
test_contract_v2_new_evidence_invalidates_review_ready
test_contract_v2_iterating_clears_acceptance_and_readiness
test_contract_v2_rejects_illegal_lifecycle_jumps
test_contract_v4_finalization_gate_and_iteration_lane
test_contract_v4_requires_and_validates_prototype_boundary
test_contract_v4_accepts_one_hard_browser_batch

report_results "build-contract"
