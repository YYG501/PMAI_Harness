#!/usr/bin/env bash
# Tests for scripts/req-events.py（delta-7 vp-1 —— req 级内容性事件流）
#
# 验证：
# - append decision → 一行合法 jsonl，event=decision，公共信封字段 timestamp（对齐 task-events.py，非 ts）
# - append adjustment → 一行合法 jsonl，event=adjustment
# - list → 折叠成可读时间线（decision / adjustment 分组 + 计数）
# - 文件落 <req-dir>/req-events.jsonl（tracked 路径，非 .runs/）
# - tracked：req-events.jsonl 在 req 目录下、git add 不被 gitignore 拦
# - list 容错文件缺失（IRON in-flight 旧 req 前置）
# - decision 缺 --decision / adjustment 缺 --from-task → 报错 exit 1
# - --alternatives 可重复 → jsonl 数组
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQ_EVENTS="$REPO_ROOT/scripts/req-events.py"

# 建临时 req 目录（不需 git，除 tracked 测试外）
_make_req_dir() {
  local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/reqevt.XXXXXX")
  mkdir -p "$tmp/requirements/active/req-001-test"
  echo "$tmp/requirements/active/req-001-test"
}

# -----------------------------------------------------------------
# Scenario 1: append decision
# -----------------------------------------------------------------
test_append_decision() {
  start_test "append decision → 合法 jsonl 一行，event=decision，含 decided_by"
  local rd; rd=$(_make_req_dir)
  python3 "$REQ_EVENTS" append "$rd" --type decision \
    --source prd-writing@3 \
    --decision "状态用枚举不用布尔" \
    --decided-by pm-explicit \
    --prd-anchor "§四 第2条" \
    --chosen "枚举 status" \
    --alternatives "布尔 is_active" \
    --alternatives "三个独立 flag" \
    --rationale "未来要加更多状态" >/dev/null 2>&1
  local f="$rd/req-events.jsonl"
  assert_file_exists "$f" "req-events.jsonl 已创建" || { rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"; return; }
  local nlines; nlines=$(wc -l < "$f" | tr -d ' ')
  assert_equal "1" "$nlines" "只写一行" || { rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"; return; }
  # 合法 JSON + 字段
  python3 -c "
import json,sys
e=json.loads(open('$f').readline())
assert e['event']=='decision', e
assert e['req']=='req-001-test', e
assert 'timestamp' in e and 'ts' not in e, e
assert e['decision']=='状态用枚举不用布尔', e
assert e['source']=='prd-writing@3', e
assert e['decided_by']=='pm-explicit', e
assert e['alternatives']==['布尔 is_active','三个独立 flag'], e
assert e['chosen']=='枚举 status', e
" >/dev/null 2>&1
  if [ $? -eq 0 ]; then pass_test; else _fail "decision jsonl 字段不符"; fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 2: append adjustment
# -----------------------------------------------------------------
test_append_adjustment() {
  start_test "append adjustment → 合法 jsonl 一行，event=adjustment"
  local rd; rd=$(_make_req_dir)
  python3 "$REQ_EVENTS" append "$rd" --type adjustment \
    --source close-task@6 \
    --from-task task-003 \
    --prd-anchor "§六 功能3" \
    --before "PRD 原定弹窗确认" \
    --after "实际做成 inline 提示" \
    --reason "弹窗打断流程" >/dev/null 2>&1
  local f="$rd/req-events.jsonl"
  python3 -c "
import json
e=json.loads(open('$f').readline())
assert e['event']=='adjustment', e
assert e['from_task']=='task-003', e
assert e['before']=='PRD 原定弹窗确认', e
assert e['after']=='实际做成 inline 提示', e
assert 'timestamp' in e, e
" >/dev/null 2>&1
  if [ $? -eq 0 ]; then pass_test; else _fail "adjustment jsonl 字段不符"; fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 3: list 折叠时间线
# -----------------------------------------------------------------
test_list_timeline() {
  start_test "list → 折叠成时间线，decision/adjustment 分组 + 计数"
  local rd; rd=$(_make_req_dir)
  python3 "$REQ_EVENTS" append "$rd" --type decision --decision "决策A" --decided-by pm-explicit >/dev/null 2>&1
  python3 "$REQ_EVENTS" append "$rd" --type adjustment --from-task task-001 >/dev/null 2>&1
  local out; out=$(python3 "$REQ_EVENTS" list "$rd" 2>&1)
  if echo "$out" | grep -q "decision: 1 条" \
     && echo "$out" | grep -q "adjustment: 1 条" \
     && echo "$out" | grep -q "决策A" \
     && echo "$out" | grep -q "task-001"; then
    pass_test
  else
    _fail "list 输出不含分组/计数: $out"
  fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 4: list 容错文件缺失（IRON in-flight 旧 req 前置）
# -----------------------------------------------------------------
test_list_missing_file() {
  start_test "list 文件缺失 → 不报错（in-flight 旧 req 容错）"
  local rd; rd=$(_make_req_dir)
  local out; out=$(python3 "$REQ_EVENTS" list "$rd" 2>&1)
  local rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "No req events"; then
    pass_test
  else
    _fail "缺文件时未优雅退出: rc=$rc out=$out"
  fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 5: 文件落 tracked 路径（req 目录下、非 gitignore）
# -----------------------------------------------------------------
test_tracked_path() {
  start_test "req-events.jsonl 落 req 目录、git add 不被拦（tracked）"
  local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/reqevt.XXXXXX")
  local rd="$tmp/requirements/active/req-001-test"
  mkdir -p "$rd"
  (
    cd "$tmp"
    git init -b main -q
    git config user.email t@t.local
    git config user.name T
    echo ".runs/" > .gitignore
  )
  python3 "$REQ_EVENTS" append "$rd" --type decision --decision "x" --decided-by pm-explicit >/dev/null 2>&1
  # git add 后 git status 该文件 staged
  (cd "$tmp" && git add requirements/active/req-001-test/req-events.jsonl) 2>/dev/null
  local staged; staged=$(cd "$tmp" && git diff --cached --name-only)
  if echo "$staged" | grep -q "req-events.jsonl"; then
    pass_test
  else
    _fail "req-events.jsonl 未能 git add（被 gitignore 或路径错）: $staged"
  fi
  rm -rf "$tmp"
}

# -----------------------------------------------------------------
# Scenario 6: 缺必填字段报错
# -----------------------------------------------------------------
test_missing_required_field() {
  start_test "decision 缺 --decision / adjustment 缺 --from-task → exit 1"
  local rd; rd=$(_make_req_dir)
  local ok=1
  python3 "$REQ_EVENTS" append "$rd" --type decision >/dev/null 2>&1 && ok=0
  python3 "$REQ_EVENTS" append "$rd" --type adjustment >/dev/null 2>&1 && ok=0
  if [ "$ok" -eq 1 ]; then
    pass_test
  else
    _fail "缺必填字段未报错"
  fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 7: decision 缺 --decided-by 报错
# -----------------------------------------------------------------
test_decision_missing_decided_by() {
  start_test "decision 缺 --decided-by → exit 1"
  local rd; rd=$(_make_req_dir)
  local out; out=$(python3 "$REQ_EVENTS" append "$rd" --type decision --decision "x" 2>&1)
  local rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -q "decided-by"; then
    pass_test
  else
    _fail "缺 --decided-by 应报错并提示，实际 rc=$rc out=$out"
  fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 8: --decided-by 非法值报错（argparse choices 把关）
# -----------------------------------------------------------------
test_decided_by_invalid_value() {
  start_test "--decided-by maybe → argparse 拒绝 exit 2"
  local rd; rd=$(_make_req_dir)
  python3 "$REQ_EVENTS" append "$rd" --type decision \
    --decision "x" --decided-by maybe >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    pass_test
  else
    _fail "非法 --decided-by 未拒绝"
  fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 9: list 按 decided_by 分两组渲染（PM 拍 / AI 推断）
# -----------------------------------------------------------------
test_list_decided_by_groups() {
  start_test "list → decision 按 decided_by 分两组（PM 拍 / AI 推断）"
  local rd; rd=$(_make_req_dir)
  python3 "$REQ_EVENTS" append "$rd" --type decision \
    --decision "PM 拍的决策" --decided-by pm-explicit >/dev/null 2>&1
  python3 "$REQ_EVENTS" append "$rd" --type decision \
    --decision "AI 推断的决策 1" --decided-by ai-inferred >/dev/null 2>&1
  python3 "$REQ_EVENTS" append "$rd" --type decision \
    --decision "AI 推断的决策 2" --decided-by ai-inferred >/dev/null 2>&1
  local out; out=$(python3 "$REQ_EVENTS" list "$rd" 2>&1)
  if echo "$out" | grep -q "\[PM 拍\]（1 条" \
     && echo "$out" | grep -q "\[AI 推断\]（2 条" \
     && echo "$out" | grep -q "PM 拍的决策" \
     && echo "$out" | grep -q "AI 推断的决策 1" \
     && echo "$out" | grep -q "AI 推断的决策 2"; then
    pass_test
  else
    _fail "list 未按 decided_by 分两组: $out"
  fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 10: list 容错 legacy decision（无 decided_by 字段的旧事件）
# -----------------------------------------------------------------
test_list_legacy_decision() {
  start_test "list → 旧 decision 事件（无 decided_by）归 legacy 段"
  local rd; rd=$(_make_req_dir)
  # 手动写一条旧格式 decision（无 decided_by），模拟 decided_by 引入前留下的事件
  printf '%s\n' '{"event":"decision","timestamp":"2026-05-01T00:00:00+00:00","req":"req-001-test","decision":"legacy 决策"}' \
    > "$rd/req-events.jsonl"
  local out; out=$(python3 "$REQ_EVENTS" list "$rd" 2>&1)
  if echo "$out" | grep -q "未分类 legacy" \
     && echo "$out" | grep -q "legacy 决策"; then
    pass_test
  else
    _fail "legacy decision 未归 legacy 段: $out"
  fi
  rm -rf "$(dirname "$(dirname "$(dirname "$rd")")")"
}

# -----------------------------------------------------------------
# Scenario 7: SKILL 引用守护 —— 防重构丢失（暂无 skill 引用，跳过登记）
# -----------------------------------------------------------------

main() {
  test_append_decision
  test_append_adjustment
  test_list_timeline
  test_list_missing_file
  test_tracked_path
  test_missing_required_field
  test_decision_missing_decided_by
  test_decided_by_invalid_value
  test_list_decided_by_groups
  test_list_legacy_decision
  report_results "req-events.py (delta-7 vp-1)"
}

main
