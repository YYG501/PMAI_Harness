#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$REPO_ROOT/scripts/build-contract.py"
REVIEW_ADAPTER="$REPO_ROOT/scripts/_lib/review_evidence.py"
ATOMIC_FILE="$REPO_ROOT/scripts/_lib/atomic_file.py"
RUN_ALL="$REPO_ROOT/tests/run-all.sh"
RELEASE_GATE="$REPO_ROOT/tests/run-release-gate.sh"

test_build_modules_are_separated() {
  start_test "build maintenance: schema, transition, evidence, adapter, and CLI stay separated"
  local file
  for file in build_schema.py build_transition.py build_evidence.py review_evidence.py; do
    if [ ! -f "$REPO_ROOT/scripts/_lib/$file" ]; then
      _fail "missing build boundary module: $file"; return
    fi
  done
  if rg -q '_lib\.lark_adapter|lark-cli|lark-review\.py' "$CONTRACT"; then
    _fail "core Build CLI must not directly depend on Lark implementation"
  elif ! rg -q 'lark-review\.py' "$REVIEW_ADAPTER"; then
    _fail "review adapter should own the optional Lark validator bridge"
  elif ! PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/pmai-boundary-pyc" \
    python3 "$CONTRACT" --help >/dev/null; then
    _fail "core Build CLI help should load without a Lark runtime"
  else
    pass_test
  fi
}

test_release_gate_excludes_optional_lark_runtime() {
  start_test "release gate: core release evidence does not require optional Lark runtime"
  if ! rg -q '^OPTIONAL_LARK_SUITES=\(' "$RUN_ALL"; then
    _fail "optional Lark suites should be named explicitly"
  elif ! rg -q 'PMAI_SKIP_OPTIONAL_LARK_TESTS=1' "$RELEASE_GATE"; then
    _fail "stable core release gate should exclude optional Lark suites"
  elif ! rg -q 'test-lark-adapter\.sh' "$RUN_ALL"; then
    _fail "default full regression should retain Lark adapter coverage"
  else
    pass_test
  fi
}

test_atomic_threat_model_is_explicit() {
  start_test "atomic writes: ADR-004 supported and unsupported risks are explicit"
  if ! rg -q 'Supported threat model \(ADR-004\)' "$ATOMIC_FILE" \
    || ! rg -q 'cooperative writers' "$ATOMIC_FILE" \
    || ! rg -q 'malicious same-user process' "$ATOMIC_FILE" \
    || ! rg -q 'non-cooperative writer' "$ATOMIC_FILE"; then
    _fail "atomic write boundary should state the supported threat model"
  else
    pass_test
  fi
}

test_build_modules_are_separated
test_release_gate_excludes_optional_lark_runtime
test_atomic_threat_model_is_explicit
report_results "build-maintenance-boundaries"
