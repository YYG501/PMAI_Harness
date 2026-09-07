#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
start_test "consumer hooks: transport, identity, timeout and checker failure boundaries"
if python3 "$SCRIPT_DIR/test-hook-runtime.py"; then
  pass_test
else
  _fail "hook runtime process regression failed"
fi
report_results "hook-runtime"
