#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

TASK_TRANSITION="$FRAMEWORK_ROOT/scripts/task-transition.py"

# -----------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------

# Clear "无偏差" marker so 文档偏差 section becomes empty (no content)
_clear_doc_diff() {
  local task="$1"
  sed -i.bak 's|^无偏差$||' "$task" && rm -f "$task.bak"
}

# Wipe the body between "## 自审记录" and next "## " / "---"
# Keeps the section heading; drops all sample content.
_clear_self_review() {
  local task="$1"
  python3 - "$task" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
# Replace everything from "## 自审记录" up to (but not including) the next "## " or end.
def repl(m):
    return "## 自审记录\n\n"
text = re.sub(r"## 自审记录.*?(?=^## |\Z)", repl, text, count=1, flags=re.MULTILINE | re.DOTALL)
open(p, "w", encoding="utf-8").write(text)
PY
}

# Force 状态 field directly (bypass transition script) for test setup
_force_status() {
  local task="$1"
  local status="$2"
  sed -i.bak "s|^\*\*状态：\*\*.*|\*\*状态：\*\* $status|" "$task"
  rm -f "$task.bak"
}

# Set 审查工具 field
_set_review_tools() {
  local task="$1"
  local val="$2"
  sed -i.bak "s|^\*\*审查工具：\*\*.*|\*\*审查工具：\*\* $val|" "$task"
  rm -f "$task.bak"
}

# Run task-transition from inside fixture dir (so find_repo_root works)
_run_transition() {
  (cd "$FIXTURE_DIR" && python3 "$TASK_TRANSITION" "$@")
}

# -----------------------------------------------------------------
# I-TT1: illegal transitions
# -----------------------------------------------------------------

test_reject_reverse_transition() {
  start_test "I-TT1 reject 执行中→待确认 (reverse)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")

  if _run_transition "$task" --to 待确认 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject reverse transition"
  else
    if grep -q "非法状态转换" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing expected message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_from_done() {
  start_test "I-TT1 reject 已完成 → anything"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "已完成")

  if _run_transition "$task" --to 执行中 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject transition out of 已完成"
  else
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_skip_transition() {
  start_test "I-TT1 reject 待确认→已完成 (skip)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待确认")

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject skip transition"
  else
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-TT2: serial constraint
# -----------------------------------------------------------------

test_reject_parallel_active_task() {
  start_test "I-TT2 reject 待确认→执行中 when sibling is 执行中"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  # sibling already active
  fixture_create_task "$req_dir" "001" "running" "执行中" >/dev/null
  task=$(fixture_create_task "$req_dir" "002" "new" "待确认")

  if _run_transition "$task" --to 执行中 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when another task active"
  else
    if grep -q "串行" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing 串行 message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_parallel_pending_review_sibling() {
  start_test "I-TT2 reject when sibling is 待验收"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  fixture_create_task "$req_dir" "001" "review" "待验收" >/dev/null
  task=$(fixture_create_task "$req_dir" "002" "new" "待确认")

  if _run_transition "$task" --to 执行中 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when sibling is 待验收"
  else
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-TT3: 执行中 → 待验收 preconditions
# -----------------------------------------------------------------

test_reject_empty_doc_diff() {
  start_test "I-TT3 reject 执行中→待验收 when 文档偏差 empty"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  _clear_doc_diff "$task"
  # Review tool already satisfied by event
  fixture_add_review_event "$task" "/qa"

  if _run_transition "$task" --to 待验收 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when 文档偏差 is empty"
  else
    if grep -q "文档偏差" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing 文档偏差 message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_empty_self_review() {
  start_test "I-TT3 reject 执行中→待验收 when 自审记录 empty"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  _clear_self_review "$task"
  fixture_add_review_event "$task" "/qa"

  if _run_transition "$task" --to 待验收 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when 自审记录 is empty"
  else
    if grep -q "自审" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing 自审 message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_missing_review_event() {
  start_test "I-TT3 reject 执行中→待验收 when /qa event missing"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  # Do NOT add the /qa review_completed event

  if _run_transition "$task" --to 待验收 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when review event missing"
  else
    if grep -qE "(missing|review|审查)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing review message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_allow_sentinel_review_tool() {
  start_test "I-TT3 allow 执行中→待验收 when 审查工具 is (无)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  _set_review_tools "$task" "(无)"
  # No review event needed

  if _run_transition "$task" --to 待验收 >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q "待验收" "$task"; then
      pass_test
    else
      _fail "status not updated"
      cat "$task" >&2
    fi
  else
    _fail "should allow when review tool is sentinel (无)"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_allow_empty_review_tool() {
  start_test "I-TT3 allow 执行中→待验收 when 审查工具 empty"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  _set_review_tools "$task" ""

  if _run_transition "$task" --to 待验收 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "should allow when review tool empty"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-TT4: 待验收 → 执行中 requires --note
# -----------------------------------------------------------------

test_reject_reject_without_note() {
  start_test "I-TT4 reject 待验收→执行中 without --note"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待验收")

  if _run_transition "$task" --to 执行中 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject reject-without-note"
  else
    if grep -qE "(note|反馈)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing note message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_allow_reject_with_note() {
  start_test "I-TT4 allow 待验收→执行中 with --note"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待验收")

  if _run_transition "$task" --to 执行中 --note "需要修复 X" >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q "执行中" "$task"; then
      pass_test
    else
      _fail "status not updated"
    fi
  else
    _fail "should accept with --note"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Happy path
# -----------------------------------------------------------------

test_happy_path_start_to_review() {
  start_test "happy path: 待确认→执行中→待验收 with events"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待确认" "/qa")
  task_stem=$(basename "$task" .md)
  events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  # 1. 待确认 → 执行中 (no sibling, should pass)
  if ! _run_transition "$task" --to 执行中 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "待确认→执行中 failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # Status updated
  if ! grep -q '^\*\*状态：\*\* 执行中' "$task"; then
    _fail "status not set to 执行中"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # 2. Add review event, then 执行中 → 待验收
  fixture_add_review_event "$task" "/qa"
  if ! _run_transition "$task" --to 待验收 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "执行中→待验收 failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q '^\*\*状态：\*\* 待验收' "$task"; then
    _fail "status not set to 待验收"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # Events stream should contain 2 status_changed events
  if [ ! -f "$events_file" ]; then
    _fail "events file not created: $events_file"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  count=$(grep -c '"event": *"status_changed"' "$events_file" || true)
  if [ "$count" -lt 2 ]; then
    _fail "expected >=2 status_changed events, got $count"
    cat "$events_file" >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_reject_reverse_transition
test_reject_from_done
test_reject_skip_transition
test_reject_parallel_active_task
test_reject_parallel_pending_review_sibling
test_reject_empty_doc_diff
test_reject_empty_self_review
test_reject_missing_review_event
test_allow_sentinel_review_tool
test_allow_empty_review_tool
test_reject_reject_without_note
test_allow_reject_with_note
test_happy_path_start_to_review

report_results "task-transition"
