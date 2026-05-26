#!/usr/bin/env bash
# test-publish-to-lark-rowspan-merge.sh
#
# 包装 tests/test-publish-to-lark-rowspan-merge.py 进 bash test suite。
# 单测 find_desc_group_ranges：续行 rowspan markdown → 单个合并 range（飞书侧合并为一个单元格语义）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

start_test "publish-to-lark find_desc_group_ranges 单测（6 case）"

if python3 "$SCRIPT_DIR/test-publish-to-lark-rowspan-merge.py" > /tmp/rowspan_test.out 2>&1; then
  pass_test "publish-to-lark find_desc_group_ranges 单测（6 case）"
else
  _fail "publish-to-lark find_desc_group_ranges 单测失败"
  cat /tmp/rowspan_test.out >&2
fi

report_results "publish-to-lark-rowspan-merge"
exit $((FAIL_COUNT > 0 ? 1 : 0))
