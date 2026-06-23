#!/usr/bin/env bash
# test-state-lib.sh
#
# 包装 scripts/_lib/state_test.py 进 bash test suite，
# 让 _lib/state.py 的单元覆盖也进 run-all 绿网（此前只在 python -m unittest 手动跑、CI 扫不到）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

start_test "_lib/state.py 单元测试（state_test.py）"

if PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 -m unittest _lib.state_test > /tmp/state_lib_test.out 2>&1; then
  pass_test "_lib/state.py 单元测试（state_test.py）"
else
  _fail "_lib/state.py 单元测试失败"
  cat /tmp/state_lib_test.out >&2
fi

report_results "state-lib"
exit $((FAIL_COUNT > 0 ? 1 : 0))
