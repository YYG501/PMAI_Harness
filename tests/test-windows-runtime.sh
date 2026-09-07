#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
start_test 'Windows runtime: directory identity, argv, stdin, preloads and cwd'
if python3 "$SCRIPT_DIR/test-windows-runtime.py"; then
  pass_test
else
  _fail 'Windows compatibility boundary failed'
fi
report_results 'windows-runtime'
