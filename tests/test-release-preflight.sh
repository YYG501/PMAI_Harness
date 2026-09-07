#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
start_test "release gate: explicit suite and capability readiness"
if python3 "$SCRIPT_DIR/test-release-preflight.py"; then
  pass_test
else
  _fail "release preflight regression failed"
fi
report_results "release-preflight"
