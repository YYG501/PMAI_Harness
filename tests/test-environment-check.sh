#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
start_test "runtime: versions, capabilities, malformed declarations and snapshots"
if python3 "$SCRIPT_DIR/test-environment-check.py"; then
  pass_test
else
  _fail "runtime diagnostics regression failed"
fi
report_results "environment-check"
