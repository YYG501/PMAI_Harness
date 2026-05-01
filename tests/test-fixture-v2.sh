#!/usr/bin/env bash
# Smoke test: fixture_create_task_v2 与 parser / task-transition 端到端协作。
# 不引入新 review gate；仅验证新 fixture 被现有解析层接受。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

TASK_TRANSITION="$FRAMEWORK_ROOT/scripts/task-transition.py"

_parser() {
  PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 -m _lib.task_parser "$@"
}

# -----------------------------------------------------------------
# 双文件存在
# -----------------------------------------------------------------

test_v2_creates_dual_files() {
  start_test "v2 fixture creates PM view + engineering contract"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "待确认")

  if [ ! -f "$task" ]; then
    _fail "PM view file missing: $task"
    fixture_teardown
    return
  fi
  local eng="${task%.md}.engineering.md"
  if [ ! -f "$eng" ]; then
    _fail "engineering contract missing: $eng"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

# -----------------------------------------------------------------
# parser detect_format = v2
# -----------------------------------------------------------------

test_v2_detect_format() {
  start_test "parser detect_format → v2"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "待确认")

  local fmt
  fmt=$(_parser detect_format "$task")
  if [ "$fmt" != "v2" ]; then
    _fail "expected v2, got: $fmt"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

# -----------------------------------------------------------------
# parser 能从表格读字段
# -----------------------------------------------------------------

test_v2_parser_reads_status() {
  start_test "parser get_status reads v2 table"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "执行中")

  local status
  status=$(_parser get_status "$task")
  if [ "$status" != "执行中" ]; then
    _fail "expected 执行中, got: $status"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_v2_parser_reads_branch() {
  start_test "parser get_branch reads v2 table"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "待确认")

  local branch
  branch=$(_parser get_branch "$task")
  if [ "$branch" != "task-001-demo" ]; then
    _fail "expected task-001-demo, got: $branch"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

# -----------------------------------------------------------------
# parser read_section 跨文件查 §10 文档偏差（在 .engineering.md）
# -----------------------------------------------------------------

test_v2_read_section_finds_engineering_doc_diff() {
  start_test "parser read_section finds §10 文档偏差 in engineering"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "待确认")

  local content
  content=$(_parser read_section "$task" "文档偏差")
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "exit code expected 0, got: $rc"
    fixture_teardown
    return
  fi
  if ! echo "$content" | grep -q "无偏差"; then
    _fail "missing '无偏差' in section content"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

test_v2_read_section_finds_engineering_self_review() {
  start_test "parser read_section finds §11 自审记录 in engineering"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "待确认")

  local content
  content=$(_parser read_section "$task" "自审记录")
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "exit code expected 0, got: $rc"
    fixture_teardown
    return
  fi
  if ! echo "$content" | grep -q "自审 1"; then
    _fail "missing '自审 1' in section content"
    fixture_teardown
    return
  fi
  pass_test
  fixture_teardown
}

# -----------------------------------------------------------------
# 端到端：task-transition.py 能识别 v2 状态并做合法转换
# -----------------------------------------------------------------

test_v2_task_transition_accepts_legal() {
  start_test "task-transition accepts v2 待确认→执行中"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "待确认")

  if (cd "$FIXTURE_DIR" && python3 "$TASK_TRANSITION" "$task" --to 执行中) >/tmp/out.$$ 2>/tmp/err.$$; then
    local status
    status=$(_parser get_status "$task")
    if [ "$status" = "执行中" ]; then
      pass_test
    else
      _fail "transition succeeded but status not updated; got: $status"
    fi
  else
    _fail "task-transition rejected legal v2 transition"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_v2_creates_dual_files
test_v2_detect_format
test_v2_parser_reads_status
test_v2_parser_reads_branch
test_v2_read_section_finds_engineering_doc_diff
test_v2_read_section_finds_engineering_self_review
test_v2_task_transition_accepts_legal

report_results "fixture-v2"
