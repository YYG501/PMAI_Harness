#!/usr/bin/env bash
# Build contract helper regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
PROTOTYPE_CONTRACT_ARGS=(
  --target-kind prototype
  --target-path prototype/
  --entrypoint prototype/
  --required-check browser-smoke
  --required-check coverage
  --required-check visual
  --required-check behavior
)

setup_contract_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-contract.XXXXXX")
  MODULE_DIR="$T/docs/modules/pet-import"
  mkdir -p "$MODULE_DIR"
  cat > "$MODULE_DIR/.work-meta.json" <<'JSON'
{
  "id": "work-001",
  "name": "pet import",
  "branch": "build-pet-import",
  "stage": 1,
  "status": "active"
}
JSON
}

teardown_contract_fixture() {
  rm -rf "$T"
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
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name browser-smoke --status limited --artifact ".pm-workflow/audits/pet-import/browser-smoke.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name coverage --status pass --artifact ".pm-workflow/audits/pet-import/coverage.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name visual --status limited --artifact ".pm-workflow/audits/pet-import/visual.json" >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name behavior --status skipped --artifact ".pm-workflow/audits/pet-import/behavior.json" >/dev/null
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
  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should fail before PM acceptance"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "pm_accepted_at" /tmp/build-contract.err.$$; then
    _fail "missing PM acceptance guidance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 "$BUILD_CONTRACT" accept "$MODULE_DIR" --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$
  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should fail before audit evidence exists"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  if ! grep -q "build 验收证据不完整" /tmp/build-contract.err.$$; then
    _fail "missing audit evidence guidance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  write_clean_audits
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
assert build["contract_version"] == 2
assert build["target"]["kind"] == "prototype"
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

test_contract_start_initializes_missing_meta() {
  start_test "build-contract: start auto-initializes missing .work-meta.json"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-contract.XXXXXX")
  MODULE_DIR="$T/docs/modules/pet-import"
  mkdir -p "$MODULE_DIR"

  if ! python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode main \
    --executor claude-code \
    --branch main \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" \
    "${PROTOTYPE_CONTRACT_ARGS[@]}" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "start should create missing .work-meta.json"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["id"] == "work-pet-import"
assert meta["name"] == "pet-import"
assert meta["status"] == "active"
assert meta["stage"] == 2
assert meta["branch"] == "main"
assert meta["build"]["mode"] == "main"
assert meta["build"]["executor"] == "claude-code"
PY
    _fail "auto-initialized meta fields mismatch"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }

  pass_test
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
assert meta["id"] == "work-new-access-flow"
assert meta["name"] == "new-access-flow"
assert meta["status"] == "active"
assert meta["lifecycle_state"] == "designing"
PY
    _fail "designing meta fields mismatch"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  }
  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_complete_records_commit_and_acceptance_atomically() {
  start_test "build-contract: complete records implementation + acceptance in one write"
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
  if ! python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" \
    --implementation-commit "def456" \
    --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "complete should succeed"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  write_clean_audits
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
  python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" \
    --implementation-commit "def456" \
    --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "complete should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
    }
  write_limited_browser_audits

  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should reject skipped browser evidence without PM exception"
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

  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close must not allow limited browser after exception"
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
  python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" \
    --implementation-commit "def456" \
    --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "complete should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
    }

  write_clean_audits
  rm -f "$T/.pm-workflow/audits/pet-import/browser-smoke.json"
  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should reject missing browser-smoke.json"
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
  python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" \
    --implementation-commit "def456" \
    --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "complete should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
    }

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

  if python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should reject passed browser audits when browser smoke is limited"
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
  python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" \
    --implementation-commit "def456" \
    --accepted-at "2026-06-28T10:00:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "complete should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
    }
  write_clean_audits
  cat > "$T/.pm-workflow/audits/pet-import/behavior.json" <<'JSON'
{"status":"fail","passed":1,"total":2,"note":"确认按钮点击无反应"}
JSON
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name behavior --status fail \
    --artifact ".pm-workflow/audits/pet-import/behavior.json" >/dev/null

  if python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "PM 接受行为检查缺口" --check behavior >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ \
    && python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should reject behavior fail even with audit exception"
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
  setup_contract_fixture

  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree --executor codex --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" --baseline-sha abc123 \
    --target-kind product --target-path "src/pets/" --entrypoint "src/pets/" \
    --approved-source-hash "source-v1" --required-check tests >/dev/null || {
      _fail "v2 start should succeed"; teardown_contract_fixture; return;
    }
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash source-v1 --commit stale-commit >/dev/null

  if python3 "$BUILD_CONTRACT" validate-land "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "stale evidence commit should block landing"
  elif ! grep -q "commit 与当前 implementation_commit 不一致" /tmp/build-contract.err.$$; then
    _fail "stale commit guidance missing"
    cat /tmp/build-contract.err.$$ >&2
  else
    python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
      --source-hash source-v1 --commit commit-v1 >/dev/null
    python3 "$BUILD_CONTRACT" validate-land "$MODULE_DIR" >/dev/null || {
      _fail "fresh product evidence should pass"; teardown_contract_fixture; return;
    }
    python3 "$BUILD_CONTRACT" add-delta "$MODULE_DIR" --kind product-model \
      --summary "角色模型改为能力与数据范围分离" --affected-surface "角色详情页" >/dev/null
    python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["design_revision"] == 2
assert build["approved_source_hash"] != "source-v1"
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
  setup_contract_fixture
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ --approved-source-hash source-v1 \
    --required-check tests >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" complete "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash source-v1 --commit commit-v1 >/dev/null
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
  setup_contract_fixture
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ --approved-source-hash source-v1 \
    --required-check tests >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" record-evidence "$MODULE_DIR" --name tests --status pass \
    --source-hash source-v1 --commit commit-v1 >/dev/null
  python3 "$BUILD_CONTRACT" commit "$MODULE_DIR" --implementation-commit commit-v2 >/dev/null

  python3 - "$MODULE_DIR/.work-meta.json" <<'PY' || {
import json, sys
build = json.load(open(sys.argv[1]))["build"]
assert build["implementation_commit"] == "commit-v2"
assert build["acceptance"]["evidence"] == []
assert build["pm_accepted_at"] is None
assert build["lifecycle_state"] == "iterating"
PY
    _fail "new implementation commit should invalidate evidence"
    teardown_contract_fixture; return
  }
  pass_test
  teardown_contract_fixture
}

test_contract_v2_rejects_illegal_lifecycle_jumps() {
  start_test "build-contract v2: cannot document or land before final_check"
  setup_contract_fixture
  python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" --mode worktree --executor codex \
    --branch build-pet-import --worktree ".worktrees/build-pet-import" \
    --baseline-sha abc123 --target-kind product --target-path src/pets/ --entrypoint src/pets/ --approved-source-hash source-v1 \
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
    --source-hash source-v1 --commit commit-v1 >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "invalid evidence status must be rejected"
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi
  pass_test
  rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$
  teardown_contract_fixture
}

test_contract_lifecycle
test_contract_rejects_missing_build
test_contract_start_requires_adaptive_inputs
test_contract_start_initializes_missing_meta
test_contract_designing_creates_new_module_directory
test_contract_complete_records_commit_and_acceptance_atomically
test_contract_limited_browser_cannot_be_excepted
test_contract_missing_browser_smoke_blocks_clean_audits
test_contract_browser_smoke_limited_blocks_passed_browser_audits
test_contract_behavior_fail_blocks_close
test_contract_v2_rejects_stale_evidence_and_invalidates_on_delta
test_contract_v2_post_land_docs_resume
test_contract_v2_new_implementation_invalidates_evidence
test_contract_v2_rejects_illegal_lifecycle_jumps

report_results "build-contract"
