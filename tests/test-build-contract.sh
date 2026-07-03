#!/usr/bin/env bash
# Build contract helper regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"

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
  cat > "$AUDIT_DIR/visual.json" <<'JSON'
{"status":"pass","findings":[]}
JSON
  cat > "$AUDIT_DIR/behavior.json" <<'JSON'
{"status":"pass","passed":2,"total":2,"note":""}
JSON
  echo "# 三道审合成报告" > "$AUDIT_DIR/synthesis.md"
}

write_limited_browser_audits() {
  AUDIT_DIR="$T/.pm-workflow/audits/pet-import"
  mkdir -p "$AUDIT_DIR"
  cat > "$AUDIT_DIR/coverage.json" <<'JSON'
{"items":[{"name":"导入入口","status":"built","note":""}]}
JSON
  cat > "$AUDIT_DIR/visual.json" <<'JSON'
{"status":"limited","findings":[],"note":"sandbox 无法启动浏览器截图"}
JSON
  cat > "$AUDIT_DIR/behavior.json" <<'JSON'
{"status":"skipped","passed":0,"total":2,"note":"browser 工具不可用"}
JSON
  echo "# 三道审合成报告" > "$AUDIT_DIR/synthesis.md"
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
    --audit-dir ".pm-workflow/audits/pet-import" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
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
  if ! grep -q "三道审证据不完整" /tmp/build-contract.err.$$; then
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
    --audit-dir ".pm-workflow/audits/pet-import" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
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
    --audit-dir ".pm-workflow/audits/pet-import" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "start should succeed"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

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

test_contract_limited_browser_requires_pm_exception() {
  start_test "build-contract: browser/visual skipped needs explicit PM audit exception"
  setup_contract_fixture

  if ! python3 "$BUILD_CONTRACT" start "$MODULE_DIR" \
    --anchor "docs/modules/pet-import/spec.md" \
    --mode worktree \
    --executor codex \
    --branch build-pet-import \
    --worktree ".worktrees/build-pet-import" \
    --baseline-sha "abc123" \
    --audit-dir ".pm-workflow/audits/pet-import" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "start should succeed"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

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
  if ! grep -q "受限/跳过" /tmp/build-contract.err.$$; then
    _fail "stderr should explain audit exception requirement"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  if ! python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "PM 确认本轮浏览器工具受限，先接受页面返回检查风险" \
    --accepted-at "2026-06-28T10:05:00+08:00" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "audit-exception should record PM acceptance"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  if ! python3 "$BUILD_CONTRACT" validate-close "$MODULE_DIR" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$; then
    _fail "validate-close should allow limited/skipped audit after PM exception"
    cat /tmp/build-contract.err.$$ >&2
    rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
  fi

  pass_test
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
    --audit-dir ".pm-workflow/audits/pet-import" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ || {
      _fail "start should succeed"
      cat /tmp/build-contract.err.$$ >&2
      rm -f /tmp/build-contract.$$ /tmp/build-contract.err.$$; teardown_contract_fixture; return
    }
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

  if python3 "$BUILD_CONTRACT" audit-exception "$MODULE_DIR" \
    --reason "PM 接受浏览器工具受限" >/tmp/build-contract.$$ 2>/tmp/build-contract.err.$$ \
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

test_contract_lifecycle
test_contract_rejects_missing_build
test_contract_start_initializes_missing_meta
test_contract_complete_records_commit_and_acceptance_atomically
test_contract_limited_browser_requires_pm_exception
test_contract_behavior_fail_blocks_close

report_results "build-contract"
