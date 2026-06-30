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

test_contract_lifecycle() {
  start_test "build-contract: start → commit → accept → validate-close"
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

test_contract_lifecycle
test_contract_rejects_missing_build
test_contract_start_initializes_missing_meta
test_contract_complete_records_commit_and_acceptance_atomically

report_results "build-contract"
