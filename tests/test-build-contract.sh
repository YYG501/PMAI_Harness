#!/usr/bin/env bash
# Build contract helper regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
CONTEXT_PACK="$FRAMEWORK_ROOT/scripts/context-pack.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"
BUILD_SKILL="$FRAMEWORK_ROOT/skills/build/SKILL.md"
LARK_REVIEW="$FRAMEWORK_ROOT/scripts/lark-review.py"
FAKE_LARK_REVIEW_CLI="$SCRIPT_DIR/helpers/fake-lark-review-cli.sh"
ORIGINAL_PATH="$PATH"
LARK_DELTA_SUMMARY="结果页补充轻量筛选提示"
LARK_DELTA_SURFACE="结果页"
PM_DELTA_EVIDENCE=(
  --scope-attestation approved-module-task-no-model-change
  --approval-kind pm-confirmation
  --approval-reference "test:PM explicitly accepted this scoped adjustment"
)
LARK_DELTA_EVIDENCE=(
  --scope-attestation approved-module-task-no-model-change
  --approval-kind lark-review-batch
  --approval-reference "missing-lark-batch-fixture"
)
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
  local raw_fixture
  raw_fixture=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-contract.XXXXXX")
  T=$(cd "$raw_fixture" && pwd -P)
  MODULE_DIR="$T/docs/modules/pet-import"
  mkdir -p "$MODULE_DIR" "$T/.pm-workflow" "$T/.fake-lark-bin"
  cp "$FAKE_LARK_REVIEW_CLI" "$T/.fake-lark-bin/lark-cli"
  chmod +x "$T/.fake-lark-bin/lark-cli"
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
  write_equivalent_product_baseline "$T"
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

prepare_lark_approval_batch() {
  local review_root="$T/.pm-workflow/context/lark-review"
  local published_hash
  mkdir -p "$review_root"
  LARK_BATCH_DIR=$(mktemp -d "$review_root/batch.fixture.XXXXXX")
  published_hash=$(printf '# Spec\n\nOld rule\n' | \
    PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 -c \
      'import sys; from _lib.lark_adapter import markdown_body_hash; print(markdown_body_hash(sys.stdin.read()))')
  printf '%s\n' \
    '---' \
    'lark_doc_id: docR' \
    'lark_doc_url: https://example.feishu.cn/docx/docR' \
    'lark_published_revision_id: 7' \
    "lark_published_source_hash: $published_hash" \
    'lark_reviewed_comment_at: 150' \
    '---' \
    '' \
    '# Spec' \
    '' \
    'Old rule' > "$MODULE_DIR/spec.md"

  PATH="$T/.fake-lark-bin:$ORIGINAL_PATH" \
    python3 "$LARK_REVIEW" collect "$MODULE_DIR/spec.md" \
      --output-dir "$LARK_BATCH_DIR" >/dev/null || return 1
  python3 "$LARK_REVIEW" reconcile \
    --manifest "$LARK_BATCH_DIR/review.json" >/dev/null || return 1
  python3 - \
    "$LARK_BATCH_DIR/resolutions.json" \
    "$MODULE_DIR/.work-meta.json" \
    "$LARK_DELTA_SUMMARY" \
    "$LARK_DELTA_SURFACE" <<'PY'
import json
import sys
from pathlib import Path

resolutions_path = Path(sys.argv[1])
meta = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
summary, surface = sys.argv[3:5]
resolutions = json.loads(resolutions_path.read_text(encoding="utf-8"))

for item in resolutions["body"]:
    item.update(
        decision="remote",
        authority="pm_confirmed",
        reason="PM 本轮确认采用飞书正文增量",
    )
for item in resolutions["comments"]:
    item.update(
        decision="no_spec_change",
        authority="existing_spec",
        reason="评论不改变本次规格口径",
        result_text="已按确认口径更新并验证",
    )
for item in resolutions["decision_routing"]:
    item.update(
        outcome="not_required",
        target_path="",
        decision_id="",
        supersedes=[],
        summary="",
        reason="本批仅为 active build 内小范围调整",
    )

build = meta["build"]
resolutions["active_build_delta"] = {
    "kind": "scoped-adjustment",
    "scope_attestation": "approved-module-task-no-model-change",
    "module": "docs/modules/pet-import",
    "work_id": meta["id"],
    "approved_source_hash_before": build["approved_source_hash"],
    "design_revision_before": build["design_revision"],
    "summary": summary,
    "affected_surfaces": [surface],
    "affects": [],
    "source_items": [f"body:{item['change_id']}" for item in resolutions["body"]],
    "authority": "pm_confirmed",
    "reason": "PM 本轮确认这是已批准模块内的小范围体验调整",
}
resolutions_path.write_text(
    json.dumps(resolutions, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

  LARK_BATCH_ID=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["batch_id"])' \
    "$LARK_BATCH_DIR/review.json") || return 1
  LARK_DELTA_EVIDENCE=(
    --scope-attestation approved-module-task-no-model-change
    --approval-kind lark-review-batch
    --approval-reference "$LARK_BATCH_ID"
  )
}

seal_lark_approval_batch() {
  local target_hash
  python3 "$LARK_REVIEW" reconcile \
    --manifest "$LARK_BATCH_DIR/review.json" \
    --resolutions "$LARK_BATCH_DIR/resolutions.json" \
    --seal >/dev/null || return 1
  PATH="$T/.fake-lark-bin:$ORIGINAL_PATH" \
    python3 "$LARK_REVIEW" apply "$MODULE_DIR/spec.md" \
      --plan "$LARK_BATCH_DIR/apply-plan.json" >/dev/null || return 1
  target_hash=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["target"]["body_sha256"])' \
    "$LARK_BATCH_DIR/apply-plan.json") || return 1
  PATH="$T/.fake-lark-bin:$ORIGINAL_PATH" \
    FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_SYNCED_REVISION=10 \
    python3 "$LARK_REVIEW" baseline "$MODULE_DIR/spec.md" \
      --revision-id 10 --expected-source-hash "$target_hash" >/dev/null || return 1
  PATH="$T/.fake-lark-bin:$ORIGINAL_PATH" \
    FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_SYNCED_REVISION=10 \
    python3 "$LARK_REVIEW" verify-sync \
      --manifest "$LARK_BATCH_DIR/review.json" \
      --plan "$LARK_BATCH_DIR/apply-plan.json" >/dev/null || return 1
  LARK_APPROVAL_ARTIFACT="$LARK_BATCH_DIR/remote-verification.json"
}

make_lark_approval_artifact() {
  prepare_lark_approval_batch || return 1
  seal_lark_approval_batch
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
assert "stage" not in meta
assert "lifecycle_state" not in meta
assert build["mode"] == "worktree"
assert build["contract_version"] == 5
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
assert "required_checks" not in build["acceptance"]
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
  python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind scoped-adjustment \
    --summary "支持批量导入" --affected-surface "导入页" \
    --accepted-at "2026-08-10T12:00:00+08:00" \
    "${PM_DELTA_EVIDENCE[@]}" >/dev/null
  if ! python3 "$BUILD_CONTRACT" validate-final-currentness "$MODULE_DIR" >/dev/null; then
    _fail "single accepted delta should pass final currentness"
    teardown_contract_fixture; return
  fi
  python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind scoped-adjustment \
    --summary "失败项可重试" --affected-surface "结果页" \
    --accepted-at "2026-08-10T12:05:00+08:00" \
    "${PM_DELTA_EVIDENCE[@]}" >/dev/null
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

test_contract_new_delta_requires_scoped_attestation_and_evidence() {
  start_test "build-contract: new deltas require scoped kind, attestation, and approval evidence"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null

  if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --summary "裸调用" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "add-delta must reject a naked invocation"
  elif ! grep -q -- "--scope-attestation" /tmp/build-contract.err.$$; then
    _fail "missing scope attestation guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  elif python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind product-model \
    --summary "试图改变角色模型" "${PM_DELTA_EVIDENCE[@]}" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "new deltas must reject broad legacy kinds"
  elif ! grep -q "kind 只能是 scoped-adjustment" /tmp/build-contract.err.$$; then
    _fail "invalid delta kind guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  elif python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "缺少证据引用" \
    --scope-attestation approved-module-task-no-model-change \
    --approval-kind pm-confirmation \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "approval kind without a reference must fail"
  elif ! grep -q -- "--approval-reference" /tmp/build-contract.err.$$; then
    _fail "missing approval reference guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  elif python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "伪造为飞书批次但没有 applied pack" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "lark review evidence without an applied context pack must fail"
  elif ! grep -q -- "--applied-context-pack" /tmp/build-contract.err.$$; then
    _fail "missing applied pack guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  elif ! python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "沿用已批准名称补充筛选提示" \
    --affects "term:服务窗口" --affects "role:结算观察员" \
    "${PM_DELTA_EVIDENCE[@]}" >/dev/null; then
    _fail "a fully evidenced scoped adjustment should succeed"
  elif python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
delta = json.load(open(sys.argv[1]))["build"]["accepted_deltas"][0]
assert delta["kind"] == "scoped-adjustment"
assert delta["affects"] == [
    {"kind": "term", "name": "服务窗口"},
    {"kind": "role", "name": "结算观察员"},
]
PY
  then
    pass_test
  else
    _fail "structured scoped-delta evidence was not persisted"
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_applied_context_pack_rebinds_authority() {
  start_test "build-contract: Lark apply checkpoint binds only stable spec + work meta"
  setup_contract_fixture product
  local baseline candidate authority_parent authority_checkpoint spec_blob pack
  baseline=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha "$baseline" --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null
  git -C "$T" add -- docs/modules/pet-import/.work-meta.json
  git -C "$T" commit -q -m "start build"
  printf 'export const filters = true\n' >> "$T/src/pets/index.ts"
  git -C "$T" add -- src/pets/index.ts
  git -C "$T" commit -q -m "candidate implementation"
  candidate=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" \
    --implementation-commit "$candidate" >/dev/null
  git -C "$T" add -- docs/modules/pet-import/.work-meta.json
  git -C "$T" commit -q -m "record candidate"
  authority_parent=$(git -C "$T" rev-parse HEAD)

  # Use the same collect -> reconcile -> seal -> apply -> baseline -> verify
  # lifecycle consumed in production.  The publishing frontmatter must be
  # stable before the authority pack is compiled.
  make_lark_approval_artifact || {
    _fail "failed to create a real sealed Lark review batch"
    teardown_contract_fixture
    return
  }
  pack="$T/.pm-workflow/context/applied-delta.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null
  if ! python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --kind scoped-adjustment \
    --summary "$LARK_DELTA_SUMMARY" \
    --affected-surface "$LARK_DELTA_SURFACE" \
    --accepted-at "2026-08-10T12:00:00+08:00" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$pack" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "an applied spec delta should bind the current authority pack"
    cat /tmp/build-contract.err.$$ >&2
  elif ! python3 "$BUILD_CONTRACT" validate-currentness "$MODULE_DIR" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "applied spec delta should remain current"
    cat /tmp/build-contract.err.$$ >&2
  elif ! python3 - "$MODULE_DIR/.work-meta.json" "$pack" "$SOURCE_HASH" \
    "$authority_parent" "$LARK_BATCH_ID" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

meta = json.load(open(sys.argv[1]))
pack = json.load(open(sys.argv[2]))
build = meta["build"]
delta = build["accepted_deltas"][0]
payload = json.dumps(
    {"previous": sys.argv[3], "delta": delta},
    ensure_ascii=False,
    sort_keys=True,
    separators=(",", ":"),
).encode("utf-8")
assert meta["approved_source_hash"] == sys.argv[3]
assert delta["authority_source_hash_before"] == sys.argv[3]
assert delta["authority_source_hash_after"] == pack["source_hash"]
assert delta["authority_source_hash_after"] != delta["authority_source_hash_before"]
assert delta["authority_paths"] == ["docs/modules/pet-import/spec.md"]
assert delta["authority_file_hashes"] == {
    "docs/modules/pet-import/spec.md": pack["input_hashes"]["docs/modules/pet-import/spec.md"]
}
assert delta["authority_parent_commit"] == sys.argv[4]
assert delta["scope_attestation"] == "approved-module-task-no-model-change"
assert delta["approval_evidence"]["kind"] == "lark-review-batch"
assert delta["approval_evidence"]["reference"] == sys.argv[5]
artifact = delta["approval_evidence"]["artifact"]
assert artifact["batch_id"] == sys.argv[5]
assert artifact["path"].endswith("/remote-verification.json")
assert artifact["plan_path"].endswith("/apply-plan.json")
repo_root = Path(sys.argv[1]).parents[3]
verification_path = repo_root / artifact["path"]
plan_path = repo_root / artifact["plan_path"]
target_path = verification_path.parent / "target.md"
assert artifact["sha256"] == hashlib.sha256(verification_path.read_bytes()).hexdigest()
assert artifact["plan_sha256"] == hashlib.sha256(plan_path.read_bytes()).hexdigest()
assert artifact["target_sha256"] == hashlib.sha256(target_path.read_bytes()).hexdigest()
assert build["authority_checkpoint_required"] is True
assert build["approved_source_hash"] == hashlib.sha256(payload).hexdigest()
PY
  then
    _fail "applied delta must preserve the initial anchor and bind before/after hashes"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  git -C "$T" add -- \
    docs/modules/pet-import/spec.md \
    docs/modules/pet-import/.work-meta.json
  git -C "$T" commit -q -m "checkpoint reviewed spec authority"
  authority_checkpoint=$(git -C "$T" rev-parse HEAD)
  spec_blob=$(git -C "$T" rev-parse "$authority_checkpoint:docs/modules/pet-import/spec.md")
  if ! python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" \
    --implementation-commit "$authority_checkpoint" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "the exact spec + work-meta authority checkpoint should pass implementation scope"
    cat /tmp/build-contract.err.$$ >&2
  elif [ "$(git -C "$T" hash-object docs/modules/pet-import/spec.md)" != "$spec_blob" ]; then
    _fail "recording the candidate commit must not change synchronized frontmatter"
  else
    git -C "$T" add -- docs/modules/pet-import/.work-meta.json
    git -C "$T" commit -q -m "record authority checkpoint candidate"
    if [ -n "$(git -C "$T" status --porcelain)" ]; then
      _fail "authority checkpoint flow must leave no dirty spec or work meta"
    elif ! python3 "$BUILD_CONTRACT" validate-currentness "$MODULE_DIR" >/dev/null; then
      _fail "authority checkpoint flow should remain current after the metadata commit"
    elif python3 - "$MODULE_DIR/.work-meta.json" "$authority_checkpoint" "$pack" "$spec_blob" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
pack = json.load(open(sys.argv[3]))
delta = build["accepted_deltas"][0]
assert build["implementation_commit"] == sys.argv[2]
assert build["authority_checkpoint_required"] is False
assert build["authority_checkpoint_commit"] == sys.argv[2]
assert build["authority_checkpoint_source_hash"] == pack["source_hash"]
assert build["authority_checkpoint_source_hash"] != build["approved_source_hash"]
assert delta["authority_git_blobs"] == {
    "docs/modules/pet-import/spec.md": sys.argv[4]
}
PY
    then
      pass_test
    else
      _fail "authority checkpoint metadata was not recorded"
    fi
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_authority_checkpoint_binds_content_and_ancestry() {
  start_test "build-contract: authority checkpoint binds applied spec content and ancestry"
  setup_contract_fixture product
  local baseline pack current_head forged_index bad_blob spec_blob meta_blob
  local wrong_tree wrong_commit parent_tree unrelated_parent correct_tree unrelated_commit
  baseline=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha "$baseline" --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null
  git -C "$T" add -- docs/modules/pet-import/.work-meta.json
  git -C "$T" commit -q -m "start build"
  current_head=$(git -C "$T" rev-parse HEAD)

  make_lark_approval_artifact || {
    _fail "failed to create a real sealed Lark review batch"
    teardown_contract_fixture
    return
  }
  pack="$T/.pm-workflow/context/applied-content.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null
  python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" \
    --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$pack" >/dev/null

  forged_index="$T/.pm-workflow/context/authority-forged.index"
  spec_blob=$(git -C "$T" hash-object -w docs/modules/pet-import/spec.md)
  meta_blob=$(git -C "$T" hash-object -w docs/modules/pet-import/.work-meta.json)
  bad_blob=$(printf '# forged spec\n' | git -C "$T" hash-object -w --stdin)
  GIT_INDEX_FILE="$forged_index" git -C "$T" read-tree "$current_head"
  GIT_INDEX_FILE="$forged_index" git -C "$T" update-index --add \
    --cacheinfo 100644 "$bad_blob" docs/modules/pet-import/spec.md
  GIT_INDEX_FILE="$forged_index" git -C "$T" update-index --add \
    --cacheinfo 100644 "$meta_blob" docs/modules/pet-import/.work-meta.json
  wrong_tree=$(GIT_INDEX_FILE="$forged_index" git -C "$T" write-tree)
  wrong_commit=$(printf 'forged wrong authority\n' | \
    git -C "$T" commit-tree "$wrong_tree" -p "$current_head")
  if python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" \
    --implementation-commit "$wrong_commit" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "allowed checkpoint paths with a forged spec blob must fail"
  elif ! grep -q "不是 applied authority 绑定版本" /tmp/build-contract.err.$$; then
    _fail "forged authority content rejection guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  else
    rm -f "$forged_index"
    GIT_INDEX_FILE="$forged_index" git -C "$T" read-tree "$current_head"
    GIT_INDEX_FILE="$forged_index" git -C "$T" update-index --add \
      --cacheinfo 100644 "$spec_blob" docs/modules/pet-import/spec.md
    GIT_INDEX_FILE="$forged_index" git -C "$T" update-index --add \
      --cacheinfo 100644 "$meta_blob" docs/modules/pet-import/.work-meta.json
    correct_tree=$(GIT_INDEX_FILE="$forged_index" git -C "$T" write-tree)
    parent_tree=$(git -C "$T" rev-parse "$current_head^{tree}")
    unrelated_parent=$(printf 'unrelated authority root\n' | \
      git -C "$T" commit-tree "$parent_tree")
    unrelated_commit=$(printf 'unrelated authority candidate\n' | \
      git -C "$T" commit-tree "$correct_tree" -p "$unrelated_parent")
    if python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" \
      --implementation-commit "$unrelated_commit" \
      >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
      _fail "content-correct checkpoint outside the authority ancestry must fail"
    elif ! grep -q "未直接承接 add-delta 时的当前提交" /tmp/build-contract.err.$$; then
      _fail "authority ancestry rejection guidance mismatch"
      cat /tmp/build-contract.err.$$ >&2
    elif python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["authority_checkpoint_required"] is True
assert build["implementation_commit"] is None
assert build["authority_checkpoint_source_hash"] != build["approved_source_hash"]
PY
    then
      pass_test
    else
      _fail "rejected authority commits must not mutate the build contract"
    fi
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$ "$forged_index"
  teardown_contract_fixture
}

test_contract_authority_checkpoint_rejects_unbound_document() {
  start_test "build-contract: authority checkpoint cannot widen scope to another document"
  setup_contract_fixture product
  local baseline pack bad_checkpoint
  baseline=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha "$baseline" --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null
  git -C "$T" add -- docs/modules/pet-import/.work-meta.json
  git -C "$T" commit -q -m "start build"

  make_lark_approval_artifact || {
    _fail "failed to create a real sealed Lark review batch"
    teardown_contract_fixture
    return
  }
  pack="$T/.pm-workflow/context/applied-delta.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null
  python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" \
    --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$pack" >/dev/null

  printf '# unrelated authority attempt\n' > "$T/docs/other.md"
  git -C "$T" add -- \
    docs/modules/pet-import/spec.md \
    docs/modules/pet-import/.work-meta.json \
    docs/other.md
  git -C "$T" commit -q -m "bad widened authority checkpoint"
  bad_checkpoint=$(git -C "$T" rev-parse HEAD)
  if python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" \
    --implementation-commit "$bad_checkpoint" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "an unbound document must not enter the authority checkpoint"
  elif ! grep -q "批准范围外路径.*docs/other.md" /tmp/build-contract.err.$$; then
    _fail "unbound-document scope rejection guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  elif python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["authority_checkpoint_required"] is True
assert build["implementation_commit"] is None
assert build["accepted_deltas"][0]["authority_paths"] == [
    "docs/modules/pet-import/spec.md"
]
PY
  then
    pass_test
  else
    _fail "failed widened checkpoint must not mutate the contract"
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_legacy_delta_keeps_authority_unchanged() {
  start_test "build-contract: legacy term/role/product deltas remain compatible"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import hashlib
import json
import sys

path = sys.argv[1]
meta = json.load(open(path))
build = meta["build"]
previous = build["approved_source_hash"]
deltas = []
for kind in ("term", "role", "product-behavior"):
    delta = {
        "kind": kind,
        "summary": f"legacy {kind} delta",
        "affected_surfaces": ["结果页"],
        "accepted_at": "2026-08-10T12:00:00+08:00",
    }
    payload = json.dumps(
        {"previous": previous, "delta": delta},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    previous = hashlib.sha256(payload).hexdigest()
    deltas.append(delta)
build["accepted_deltas"] = deltas
build["approved_source_hash"] = previous
build["lifecycle_state"] = "iterating"
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  if python3 "$BUILD_CONTRACT" validate-currentness "$MODULE_DIR" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    pass_test
  else
    _fail "legacy delta should infer authority before=after"
    cat /tmp/build-contract.err.$$ >&2
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_scoped_delta_shape_fails_closed() {
  start_test "build-contract: forged scoped delta shapes fail closed"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import hashlib
import json
import sys

path = sys.argv[1]
meta = json.load(open(path))
build = meta["build"]
delta = {"kind": "scoped-adjustment", "summary": "forged without evidence"}
payload = json.dumps(
    {"previous": build["approved_source_hash"], "delta": delta},
    ensure_ascii=False,
    sort_keys=True,
    separators=(",", ":"),
).encode("utf-8")
build["accepted_deltas"] = [delta]
build["approved_source_hash"] = hashlib.sha256(payload).hexdigest()
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  if python3 "$BUILD_CONTRACT" validate-currentness "$MODULE_DIR" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "scoped delta without evidence must fail"
  elif ! grep -q "scope_attestation" /tmp/build-contract.err.$$; then
    _fail "missing scoped evidence guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  else
    python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import hashlib
import json
import sys

path = sys.argv[1]
meta = json.load(open(path))
build = meta["build"]
previous = meta["approved_source_hash"]
delta = {
    "kind": "product-behavior",
    "summary": "forged legacy delta",
    "scope_attestation": "approved-module-task-no-model-change",
}
payload = json.dumps(
    {"previous": previous, "delta": delta},
    ensure_ascii=False,
    sort_keys=True,
    separators=(",", ":"),
).encode("utf-8")
build["accepted_deltas"] = [delta]
build["approved_source_hash"] = hashlib.sha256(payload).hexdigest()
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
    if python3 "$BUILD_CONTRACT" validate-currentness "$MODULE_DIR" \
      >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
      _fail "legacy kind with new evidence fields must fail"
    elif ! grep -q "kind 必须是 scoped-adjustment" /tmp/build-contract.err.$$; then
      _fail "mixed legacy/new delta guidance mismatch"
      cat /tmp/build-contract.err.$$ >&2
    else
      python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import hashlib
import json
import sys

path = sys.argv[1]
meta = json.load(open(path))
build = meta["build"]
previous = meta["approved_source_hash"]
delta = {
    "kind": "scoped-adjustment",
    "summary": "forged without authority transition",
    "scope_attestation": "approved-module-task-no-model-change",
    "approval_evidence": {"kind": "pm-confirmation", "reference": "test:PM confirmed"},
    "affects": [],
}
payload = json.dumps(
    {"previous": previous, "delta": delta},
    ensure_ascii=False,
    sort_keys=True,
    separators=(",", ":"),
).encode("utf-8")
build["accepted_deltas"] = [delta]
build["approved_source_hash"] = hashlib.sha256(payload).hexdigest()
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
      if python3 "$BUILD_CONTRACT" validate-currentness "$MODULE_DIR" \
        >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
        _fail "new scoped delta without authority transition must fail"
      elif ! grep -q "authority source hash transition" /tmp/build-contract.err.$$; then
        _fail "missing authority transition guidance mismatch"
        cat /tmp/build-contract.err.$$ >&2
      else
        pass_test
      fi
    fi
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_plain_delta_rejects_authority_drift() {
  start_test "build-contract: plain delta cannot absorb unbound authority drift"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null

  printf '\n未绑定的规格变化。\n' >> "$MODULE_DIR/spec.md"
  if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "试图吞掉规格漂移" --affected-surface "规格" \
    "${PM_DELTA_EVIDENCE[@]}" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "plain add-delta must reject authority drift"
  elif ! grep -Eq "设计依据在批准后发生变化|完整 Product Proposal 或等价产品基线" \
    /tmp/build-contract.err.$$; then
    _fail "plain delta drift guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  elif python3 - "$MODULE_DIR/.work-meta.json" "$SOURCE_HASH" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["accepted_deltas"] == []
assert build["approved_source_hash"] == sys.argv[2]
PY
  then
    pass_test
  else
    _fail "rejected plain delta must not mutate the build contract"
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_applied_context_pack_rejects_forged_or_stale_pack() {
  start_test "build-contract: applied context pack must be current and contract-bound"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null

  local stale="$T/.pm-workflow/context/stale-applied.json"
  local current="$T/.pm-workflow/context/current-applied.json"
  local forged="$T/.pm-workflow/context/forged-applied.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$stale" >/dev/null
  make_lark_approval_artifact || {
    _fail "failed to create a real sealed Lark review batch"
    teardown_contract_fixture
    return
  }
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$current" >/dev/null

  if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$stale" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "stale applied context pack must fail"
  elif ! grep -q "现场重新编译结果不一致" /tmp/build-contract.err.$$; then
    _fail "stale applied pack guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  else
    python3 - "$current" "$forged" <<'PY'
import json, sys
pack = json.load(open(sys.argv[1]))
pack["module"] = "docs/modules/other"
json.dump(pack, open(sys.argv[2], "w"), ensure_ascii=False, indent=2)
PY
    if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
      --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
      "${LARK_DELTA_EVIDENCE[@]}" \
      --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
      --applied-context-pack "$forged" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
      _fail "cross-module applied context pack must fail"
    elif ! grep -q "不属于当前模块" /tmp/build-contract.err.$$; then
      _fail "cross-module applied pack guidance mismatch"
      cat /tmp/build-contract.err.$$ >&2
    else
      python3 - "$current" "$forged" <<'PY'
import json, sys
pack = json.load(open(sys.argv[1]))
pack["source_hash_version"] = 1
json.dump(pack, open(sys.argv[2], "w"), ensure_ascii=False, indent=2)
PY
      if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
        --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
        "${LARK_DELTA_EVIDENCE[@]}" \
        --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
        --applied-context-pack "$forged" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
        _fail "wrong-version applied context pack must fail"
      elif ! grep -q "source hash 版本不一致" /tmp/build-contract.err.$$; then
        _fail "wrong-version applied pack guidance mismatch"
        cat /tmp/build-contract.err.$$ >&2
      else
        python3 - "$current" "$forged" <<'PY'
import json, sys
pack = json.load(open(sys.argv[1]))
pack["approved_source_hash"] = "f" * 64
json.dump(pack, open(sys.argv[2], "w"), ensure_ascii=False, indent=2)
PY
        if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
          --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
          "${LARK_DELTA_EVIDENCE[@]}" \
          --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
          --applied-context-pack "$forged" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
          _fail "unbound applied context pack must fail"
        elif ! grep -q "未绑定当前 build contract" /tmp/build-contract.err.$$; then
          _fail "unbound applied pack guidance mismatch"
          cat /tmp/build-contract.err.$$ >&2
        elif python3 - "$MODULE_DIR/.work-meta.json" "$SOURCE_HASH" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["accepted_deltas"] == []
assert build["approved_source_hash"] == sys.argv[2]
PY
        then
          pass_test
        else
          _fail "rejected applied packs must not mutate the build contract"
        fi
      fi
    fi
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_lark_delta_requires_verified_batch_artifact() {
  start_test "build-contract: Lark delta binds sealed batch and verified target"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null

  local pack="$T/.pm-workflow/context/lark-artifact-pack.json"
  make_lark_approval_artifact || {
    _fail "failed to create a real sealed Lark review batch"
    teardown_contract_fixture
    return
  }
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null

  if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" --applied-context-pack "$pack" \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "Lark delta without remote verification artifact must fail"
  elif ! grep -q -- "--approval-artifact" /tmp/build-contract.err.$$; then
    _fail "missing Lark approval artifact guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  else
    python3 - "$LARK_APPROVAL_ARTIFACT" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["batch_id"] = "another-batch"
json.dump(value, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
    if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
      --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
      "${LARK_DELTA_EVIDENCE[@]}" --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
      --applied-context-pack "$pack" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
      _fail "mismatched Lark batch artifact must fail"
    elif ! grep -Eq "不是该 sealed Lark 批次|与当前 ready plan / 发布 revision 不一致" \
      /tmp/build-contract.err.$$; then
      _fail "mismatched Lark batch guidance mismatch"
      cat /tmp/build-contract.err.$$ >&2
    else
      make_lark_approval_artifact || {
        _fail "failed to recreate a real sealed Lark review batch"
        teardown_contract_fixture
        return
      }
      printf '\n批次验证后又发生规格漂移。\n' >> "$MODULE_DIR/spec.md"
      python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null
      if python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
        --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
        "${LARK_DELTA_EVIDENCE[@]}" --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
        --applied-context-pack "$pack" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
        _fail "Lark artifact whose target no longer matches spec must fail"
      elif ! grep -Eq "不是该 sealed Lark 批次已应用的 target|不是已应用的目标版本 T" \
        /tmp/build-contract.err.$$; then
        _fail "stale Lark target guidance mismatch"
        cat /tmp/build-contract.err.$$ >&2
      elif python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1]))["build"]["accepted_deltas"] == []
PY
      then
        pass_test
      else
        _fail "rejected Lark approval artifacts must not mutate the build contract"
      fi
    fi
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_lark_approval_rejects_route_drift_and_tampering() {
  start_test "build-contract: Lark approval replays route, seal, and safe artifact paths"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null
  make_lark_approval_artifact || {
    _fail "failed to create a real sealed Lark review batch"
    teardown_contract_fixture
    return
  }

  local pack="$T/.pm-workflow/context/lark-tamper-pack.json"
  local out rc plan_backup minimal_dir artifact_link_dir parent_link review_root
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null

  out=$(python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "${LARK_DELTA_SUMMARY}（漂移）" \
    --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$pack" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'active_build_delta 不一致'; then
    _fail "CLI summary drift must be rejected by the sealed route: rc=$rc out=$out"
    teardown_contract_fixture
    return
  fi

  out=$(python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "其它页面" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$pack" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'active_build_delta 不一致'; then
    _fail "CLI affected surface drift must be rejected by the sealed route: rc=$rc out=$out"
    teardown_contract_fixture
    return
  fi

  out=$(python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
    --affects "term:额外术语" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$pack" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'active_build_delta 不一致'; then
    _fail "CLI affects drift must be rejected by the sealed route: rc=$rc out=$out"
    teardown_contract_fixture
    return
  fi

  plan_backup="$T/.pm-workflow/context/apply-plan.backup.json"
  cp "$LARK_BATCH_DIR/apply-plan.json" "$plan_backup"
  python3 - "$LARK_BATCH_DIR/apply-plan.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
plan = json.loads(path.read_text(encoding="utf-8"))
plan["unresolved_count"] = 1
plan.pop("ready_token", None)
encoded = json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
plan["ready_token"] = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
path.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  out=$(python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$LARK_APPROVAL_ARTIFACT" \
    --applied-context-pack "$pack" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '仍包含待决项'; then
    _fail "recomputed ready token must not hide a nonzero unresolved count: rc=$rc out=$out"
    teardown_contract_fixture
    return
  fi
  cp "$plan_backup" "$LARK_BATCH_DIR/apply-plan.json"

  review_root="$T/.pm-workflow/context/lark-review"
  minimal_dir=$(mktemp -d "$review_root/batch.minimal.XXXXXX")
  python3 - "$minimal_dir/remote-verification.json" "$LARK_BATCH_ID" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps({"batch_id": sys.argv[2]}, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY
  out=$(python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$minimal_dir/remote-verification.json" \
    --applied-context-pack "$pack" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'review.json'; then
    _fail "a hand-written minimal approval artifact must fail closed: rc=$rc out=$out"
    teardown_contract_fixture
    return
  fi

  artifact_link_dir=$(mktemp -d "$review_root/batch.artifact-link.XXXXXX")
  ln -s "$LARK_APPROVAL_ARTIFACT" "$artifact_link_dir/remote-verification.json"
  out=$(python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$artifact_link_dir/remote-verification.json" \
    --applied-context-pack "$pack" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'symlink'; then
    _fail "a symlinked approval artifact must fail closed: rc=$rc out=$out"
    teardown_contract_fixture
    return
  fi

  parent_link="$review_root/batch.parent-link.$$"
  ln -s "$LARK_BATCH_DIR" "$parent_link"
  out=$(python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" \
    --summary "$LARK_DELTA_SUMMARY" --affected-surface "$LARK_DELTA_SURFACE" \
    "${LARK_DELTA_EVIDENCE[@]}" \
    --approval-artifact "$parent_link/remote-verification.json" \
    --applied-context-pack "$pack" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'symlink'; then
    _fail "an approval artifact behind a symlinked parent must fail closed: rc=$rc out=$out"
    teardown_contract_fixture
    return
  fi

  prepare_lark_approval_batch || {
    _fail "failed to prepare a fresh pre-apply batch for decision-route validation"
    teardown_contract_fixture
    return
  }
  python3 - \
    "$LARK_BATCH_DIR/resolutions.json" \
    "$LARK_BATCH_DIR/target.md" \
    "$LARK_REVIEW" \
    "$T" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

resolutions_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
module_path = Path(sys.argv[3])
repo_root = Path(sys.argv[4])
spec = importlib.util.spec_from_file_location("pmai_lark_review_build_test", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
data = json.loads(resolutions_path.read_text(encoding="utf-8"))
for item in data["decision_routing"]:
    if item["source_type"] == "body":
        item.update(
            outcome="create",
            target_path="docs/modules/pet-import/decisions.md",
            decision_id="D-LARK-STABLE-RULE",
            supersedes=[],
            summary="新增稳定模块规则",
            reason="测试稳定决定与 scoped delta 不能共存",
        )
candidate = "docs/modules/pet-import/decisions.md#D-LARK-STABLE-RULE"
source_hashes, active = module._decision_inventory(repo_root)
data["consistency"] = {
    "status": "checked",
    "target_sha256": module._sha256_text(target_path.read_text(encoding="utf-8")),
    "source_hashes": source_hashes,
    "candidate_decision_ids": [candidate],
    "reviewed_active_decision_ids": sorted(item["id"] for item in active),
    "checks": [
        {
            "candidate_id": candidate,
            "active_id": item["id"],
            "result": "compatible",
            "reason": "测试夹具只验证稳定决定与 active delta 的互斥门",
        }
        for item in active
    ],
}
resolutions_path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  out=$(python3 "$LARK_REVIEW" reconcile \
    --manifest "$LARK_BATCH_DIR/review.json" \
    --resolutions "$LARK_BATCH_DIR/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不能与 create / supersede'; then
    _fail "stable decision writes must not coexist with an active build delta: rc=$rc out=$out"
    teardown_contract_fixture
    return
  elif python3 - "$MODULE_DIR/.work-meta.json" "$SOURCE_HASH" <<'PY'
import json
import sys

build = json.load(open(sys.argv[1], encoding="utf-8"))["build"]
assert build["accepted_deltas"] == []
assert build["approved_source_hash"] == sys.argv[2]
PY
  then
    pass_test
  else
    _fail "rejected Lark approval mutations must not alter the build contract"
  fi
  teardown_contract_fixture
}

test_contract_lark_frontmatter_only_delta_is_rejected() {
  start_test "build-contract: Lark delta requires a real authority body change"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" designing "$MODULE_DIR" >/dev/null
  printf '# Spec\n\nNew rule\n' > "$MODULE_DIR/spec.md"
  git -C "$T" add -- docs/modules/pet-import/spec.md docs/modules/pet-import/.work-meta.json
  git -C "$T" commit -q -m "approve target body before review"

  local pack="$T/.pm-workflow/context/frontmatter-only-ready.json"
  local source_hash checkpoint out rc
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE_DIR" --output "$pack" >/dev/null
  source_hash=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["source_hash"])' \
    "$pack")
  checkpoint=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" ready "$MODULE_DIR" \
    --approved-source-hash "$source_hash" \
    --checkpoint-commit "$checkpoint" \
    --context-pack "$pack" \
    --target-path src/pets \
    --design-revision 1 >/dev/null
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha "$checkpoint" --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null
  prepare_lark_approval_batch || {
    _fail "failed to prepare the frontmatter-only Lark review batch"
    teardown_contract_fixture
    return
  }
  out=$(python3 "$LARK_REVIEW" reconcile \
    --manifest "$LARK_BATCH_DIR/review.json" \
    --resolutions "$LARK_BATCH_DIR/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '没有形成真实规格正文变化'; then
    _fail "frontmatter-only authority changes must not seal a delta: rc=$rc out=$out"
    teardown_contract_fixture
    return
  elif python3 - "$LARK_BATCH_DIR/apply-plan.json" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1], encoding="utf-8"))
assert plan["state"] == "draft"
PY
  then
    pass_test
  else
    _fail "a rejected frontmatter-only batch must remain draft"
  fi
  teardown_contract_fixture
}

test_contract_commit_rejects_stale_authority_sources() {
  start_test "build-contract: implementation commit fails closed on stale authority sources"
  setup_contract_fixture product
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode main --executor native \
    --branch main --baseline-sha abc123 --target-kind product \
    --target-path src/pets --entrypoint src/pets --final-check tests >/dev/null

  printf '\n跨模块规则在 build 开始后发生变化。\n' >> "$T/PRODUCT-RULES.md"
  if python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 \
    >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "stale authority sources must block implementation commit recording"
  elif ! grep -Eq "设计依据在批准后发生变化|完整 Product Proposal 或等价产品基线" \
    /tmp/build-contract.err.$$; then
    _fail "stale commit guidance mismatch"
    cat /tmp/build-contract.err.$$ >&2
  elif python3 - "$MODULE_DIR/.work-meta.json" <<'PY'
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["lifecycle_state"] == "building"
assert build["implementation_commit"] is None
PY
  then
    pass_test
  else
    _fail "failed currentness check must not mutate the build contract"
  fi
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_build_skill_routes_feedback_before_delta() {
  start_test "build skill: feedback routes by product, module, delta, or implementation level"
  assert_file_contains "$BUILD_SKILL" "产品级变化回 Proposal" \
    "product-level feedback should route to Proposal" || return
  assert_file_contains "$BUILD_SKILL" "模块模型变化回 design" \
    "module-model feedback should route to design" || return
  assert_file_contains "$BUILD_SKILL" "不得写 accepted delta" \
    "upstream feedback should not be swallowed as a delta" || return
  assert_file_contains "$BUILD_SKILL" "直接修正实现，不写 delta" \
    "implementation corrections should stay out of product deltas" || return
  assert_file_contains "$BUILD_SKILL" "只有已固化的 accepted-delta 路径才" \
    "lark-review handoff should add a delta only after the same feedback routing" || return
  assert_file_contains "$BUILD_SKILL" "add-delta --applied-context-pack" \
    "lark-review handoff should bind the applied authority pack" || return
  assert_file_contains "$BUILD_SKILL" "不改变对象、关系、业务规则、权限模型或关键任务路径" \
    "scoped adjustments must exclude module-model changes" || return
  assert_file_contains "$BUILD_SKILL" "--scope-attestation approved-module-task-no-model-change" \
    "new deltas must carry the fixed scope attestation" || return
  assert_file_contains "$BUILD_SKILL" "--approval-kind pm-confirmation" \
    "direct build deltas must carry PM evidence" || return
  assert_file_contains "$BUILD_SKILL" "先精细同步飞书、verify 并稳定发布 frontmatter.*重新编译" \
    "Lark authority must be compiled only after publishing frontmatter stabilizes" || return
  if grep -Fq 'apply 成功后先调用一次 `add-delta`' "$BUILD_SKILL"; then
    _fail "lark-review apply must not default every feedback batch to an accepted delta"
    return
  fi
  assert_file_contains "$BUILD_SKILL" "BUILD_BASE_BRANCH" \
    "worktree builds should resolve the actual main/master base branch" || return
  if grep -Fq 'worktree add -b "$BUILD_BRANCH" "$BUILD_DIR" main' "$BUILD_SKILL"; then
    _fail "worktree build example must not hard-code main"
    return
  fi
  pass_test
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
    --check visual \
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
    --check visual \
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
    --reason "PM 接受行为检查缺口" --check behavior >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "behavior fail must not accept an audit exception"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "behavior 不允许 exception" /tmp/build-contract.err.$$; then
    _fail "stderr should explain that behavior is a hard gate"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if python3 "$BUILD_CONTRACT" review-ready "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "review-ready should reject behavior fail"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  elif grep -q "行为审未通过" /tmp/build-contract.err.$$; then
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
    python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind scoped-adjustment \
      --summary "角色详情页补充已批准范围提示" --affected-surface "角色详情页" \
      "${PM_DELTA_EVIDENCE[@]}" >/dev/null
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
  start_test "build-contract v5: final checks require PM request; validation fixes rebind; PM feedback resumes iteration"
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
  start_test "build-contract v5: prototype boundary is required, current, and non-exceptable"
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
  start_test "build-contract v5: one browser batch replaces three separate UI checks"
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
test_contract_new_delta_requires_scoped_attestation_and_evidence
test_contract_applied_context_pack_rebinds_authority
test_contract_authority_checkpoint_binds_content_and_ancestry
test_contract_authority_checkpoint_rejects_unbound_document
test_contract_legacy_delta_keeps_authority_unchanged
test_contract_scoped_delta_shape_fails_closed
test_contract_plain_delta_rejects_authority_drift
test_contract_applied_context_pack_rejects_forged_or_stale_pack
test_contract_lark_delta_requires_verified_batch_artifact
test_contract_lark_approval_rejects_route_drift_and_tampering
test_contract_lark_frontmatter_only_delta_is_rejected
test_contract_commit_rejects_stale_authority_sources
test_build_skill_routes_feedback_before_delta
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
