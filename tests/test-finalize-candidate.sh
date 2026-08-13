#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE="$FRAMEWORK_ROOT/scripts/finalize-candidate.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-finalize-candidate.XXXXXX")
  REPO="$T/repo"
  MODULE="$REPO/docs/modules/demo"
  RUNNER_DIR="$T/framework"
  LOG="$T/calls.log"
  mkdir -p "$MODULE" "$RUNNER_DIR"
  cp "$SOURCE" "$RUNNER_DIR/finalize-candidate.py"
  printf '# Demo\n' > "$MODULE/spec.md"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name Test
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm candidate
  HEAD_SHA=$(git -C "$REPO" rev-parse HEAD)
  MODULE=$(cd "$MODULE" && pwd -P)
  cat > "$RUNNER_DIR/build-contract.py" <<'PY'
import os, sys
with open(os.environ["PMAI_TEST_LOG"], "a", encoding="utf-8") as stream:
    stream.write("contract " + " ".join(sys.argv[1:]) + "\n")
raise SystemExit(int(os.environ.get("PMAI_TEST_CONTRACT_RC", "0")))
PY
  cat > "$RUNNER_DIR/finalize-work.py" <<'PY'
import os, sys
with open(os.environ["PMAI_TEST_LOG"], "a", encoding="utf-8") as stream:
    stream.write("runner " + " ".join(sys.argv[1:]) + "\n")
raise SystemExit(int(os.environ.get("PMAI_TEST_RUNNER_RC", "0")))
PY
}

teardown_fixture() { rm -rf "$T"; }

test_binds_candidate_before_runner() {
  start_test "finalize-candidate: resolves contract candidate before forwarding runner options"
  setup_fixture
  if ! PMAI_TEST_LOG="$LOG" python3 "$RUNNER_DIR/finalize-candidate.py" \
    --module-dir "$MODULE" --browser-manifest manifest.json --browse-bin browse \
    --coverage-plan checks.json --coverage-artifacts captures \
    --coverage-confirm-state detail \
    --retry-failed --no-land; then
    _fail "candidate entry should succeed"
  elif ! python3 - "$LOG" "$MODULE" "$HEAD_SHA" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
module, _head = sys.argv[2:]
assert lines == [
    f"contract bind-candidate {module}",
    f"runner --module-dir {module} --browser-manifest manifest.json --browse-bin browse --coverage-plan checks.json --coverage-artifacts captures --coverage-confirm-state detail --retry-failed --no-land",
], lines
PY
  then
    _fail "candidate entry command order or forwarding mismatch"
  else
    pass_test
  fi
  teardown_fixture
}

test_contract_failure_stops_runner() {
  start_test "finalize-candidate: contract failure stops before runner"
  setup_fixture
  PMAI_TEST_LOG="$LOG" PMAI_TEST_CONTRACT_RC=7 \
    python3 "$RUNNER_DIR/finalize-candidate.py" --module-dir "$MODULE" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -ne 7 ]; then
    _fail "contract exit code should pass through"
  elif [ "$(wc -l < "$LOG" | tr -d ' ')" -ne 1 ] || grep -q '^runner ' "$LOG"; then
    _fail "runner must not start after contract failure"
  else
    pass_test
  fi
  teardown_fixture
}

test_runner_status_passes_through() {
  start_test "finalize-candidate: semantic handoff exit code passes through"
  setup_fixture
  PMAI_TEST_LOG="$LOG" PMAI_TEST_RUNNER_RC=3 \
    python3 "$RUNNER_DIR/finalize-candidate.py" --module-dir "$MODULE" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 3 ]; then
    pass_test
  else
    _fail "runner exit code 3 should pass through"
  fi
  teardown_fixture
}

test_binds_candidate_before_runner
test_contract_failure_stops_runner
test_runner_status_passes_through
report_results "finalize-candidate"
