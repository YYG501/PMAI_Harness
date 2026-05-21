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
  start_test "I-TT1 reject 执行中→待执行 (reverse)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")

  if _run_transition "$task" --to 待执行 >/tmp/out.$$ 2>/tmp/err.$$; then
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
  start_test "I-TT1 reject 待执行→已完成 (skip)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject skip transition"
  else
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-TT2 (放宽后): D0 并行允许同 req 多 task 同时执行
# （2026-05-08: 「待验收」已合并到「执行中」 — sibling 在 commit 后呈交期间仍是「执行中」）
# -----------------------------------------------------------------

test_reject_parallel_active_task_now_allowed() {
  start_test "I-TT2 accept 待执行→执行中 when sibling is 执行中"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  # sibling already active
  fixture_create_task "$req_dir" "001" "running" "执行中" >/dev/null
  task=$(fixture_create_task "$req_dir" "002" "new" "待执行")

  if _run_transition "$task" --to 执行中 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "should accept when another task active after I-TT2 relaxed (v4 D0)"
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-TT3: 执行中 → 已完成 preconditions（PM 通过呈交块）
# -----------------------------------------------------------------

test_reject_empty_doc_diff() {
  start_test "I-TT3 reject 执行中→已完成 when 文档偏差 empty"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  _clear_doc_diff "$task"
  # Review tool already satisfied by event
  fixture_add_review_event "$task" "/qa"

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
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
  start_test "I-TT3 reject 执行中→已完成 when 自审记录 empty"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  _clear_self_review "$task"
  fixture_add_review_event "$task" "/qa"

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
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

test_allow_missing_review_event() {
  start_test "I-RV2 allow 执行中→已完成 even when review_completed event missing"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  fixture_seed_execution_started "$task"
  # Do NOT add the /qa review_completed event — review 是 PM 自跑推荐项，
  # 缺事件不阻止转「已完成」（I-RV2）

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q '^\*\*状态：\*\* 已完成' "$task"; then
      pass_test
    else
      _fail "status not updated to 已完成"
      cat "$task" >&2
    fi
  else
    _fail "should allow even when review event missing (I-RV2 informational only)"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_allow_sentinel_review_tool() {
  start_test "I-TT3 allow 执行中→已完成 when 审查工具 is (无)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  fixture_seed_execution_started "$task"
  _set_review_tools "$task" "(无)"
  # No review event needed

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q "已完成" "$task"; then
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
  start_test "I-TT3 allow 执行中→已完成 when 审查工具 empty"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  fixture_seed_execution_started "$task"
  _set_review_tools "$task" ""

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "should allow when review tool empty"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-TT4 已废弃（2026-05-08）：PM 打回不再走 transition；任务保持「执行中」
# 验证 --to 执行中 from 执行中 被合法转换表拒绝
# -----------------------------------------------------------------

test_reject_self_loop_executing() {
  start_test "I-TT1 reject 执行中→执行中 (self-loop after I-TT4 废弃)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")

  if _run_transition "$task" --to 执行中 --note "PM 打回（旧路径）" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject self-loop transition (PM 打回不切状态)"
  else
    if grep -q "非法状态转换" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing 非法状态转换 message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Happy path
# -----------------------------------------------------------------

test_happy_path_start_to_done() {
  start_test "happy path: 待执行→执行中→已完成 with events"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行" "/qa")
  task_stem=$(basename "$task" .md)
  events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  # 1. 待执行 → 执行中 (no sibling, should pass)
  if ! _run_transition "$task" --to 执行中 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "待执行→执行中 failed"
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

  # 2. Add review event (optional in new flow, but kept here to verify it doesn't block),
  #    then 执行中 → 已完成
  fixture_add_review_event "$task" "/qa"
  fixture_seed_execution_started "$task"
  if ! _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "执行中→已完成 failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q '^\*\*状态：\*\* 已完成' "$task"; then
    _fail "status not set to 已完成"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # Events stream should contain 2 status_changed events (待执行→执行中、执行中→已完成)
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
# accept 闸门：执行中→已完成 须有 execution 事件（task收口加固 vp-1）
# -----------------------------------------------------------------

test_accept_gate_pass_execution_started() {
  start_test "accept 闸门 allow 执行中→已完成 when 事件流有 execution_started"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  fixture_seed_execution_started "$task"

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "应放行：事件流有 execution_started"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_accept_gate_pass_manual_completed() {
  start_test "accept 闸门 allow 执行中→已完成 when 事件流有 execution_manual_completed"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  task_stem=$(basename "$task" .md)
  echo "{\"event\":\"execution_manual_completed\",\"timestamp\":\"2020-01-01T00:01:00+00:00\",\"task\":\"$task_stem\"}" \
    >> "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "应放行：事件流有 execution_manual_completed"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_accept_gate_reject_no_execution_event() {
  start_test "accept 闸门 reject 执行中→已完成 when 事件流无 execution 事件"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  task_stem=$(basename "$task" .md)
  # 事件流有 status_changed 但无 execution 事件 —— task-001 的实况
  echo "{\"event\":\"status_changed\",\"timestamp\":\"2020-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待执行\",\"to\":\"执行中\"}" \
    >> "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应拒绝：事件流无 execution 事件"
  else
    if grep -q "accept 闸门" /tmp/err.$$ && grep -q "task-execute" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺 accept 闸门 / task-execute 提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_accept_gate_fail_closed_malformed_events() {
  start_test "accept 闸门 fail-closed 执行中→已完成 when 事件流含坏行且无 execution 事件"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  task_stem=$(basename "$task" .md)
  echo 'this is not json' >> "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应 fail-closed 拒绝：事件流含坏行且无 execution 事件"
  else
    if grep -q "fail-closed" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺 fail-closed 提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# --repair-evidence：受支持的审计证据修复（证据修复命令 D-task）
# -----------------------------------------------------------------

test_repair_evidence_appends_marked_event() {
  start_test "I-RE1 repair-evidence 补记带 repaired 标记的 execution_manual_completed"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "已完成")
  task_stem=$(basename "$task" .md)
  events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  echo "{\"event\":\"status_changed\",\"timestamp\":\"2020-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待执行\",\"to\":\"执行中\"}" > "$events_file"
  fixture_create_task_worktree "$task" "req-001-test" >/dev/null

  if _run_transition "$task" --repair-evidence --reason "人工窗口真实执行完成" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q '"event": *"execution_manual_completed"' "$events_file" && \
       grep -q '"repaired": *true' "$events_file"; then
      pass_test
    else
      _fail "事件流缺 execution_manual_completed 或 repaired 标记"
      cat "$events_file" >&2
    fi
  else
    _fail "repair-evidence 应成功"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_repair_evidence_rejects_missing_reason() {
  start_test "I-RE2 repair-evidence reject without --reason"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "已完成")

  if _run_transition "$task" --repair-evidence --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应拒绝：缺 --reason"
  else
    if grep -qi "reason" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺 reason 提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_repair_evidence_rejects_non_done_status() {
  start_test "I-RE3 repair-evidence reject 非「已完成」task"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")

  if _run_transition "$task" --repair-evidence --reason "x" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应拒绝：仅「已完成」可 repair"
  else
    if grep -q "仅用于「已完成」" /tmp/err.$$ && grep -q "task-execute" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺状态/引导提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_repair_evidence_rejects_when_already_has_event() {
  start_test "I-RE4 repair-evidence reject 事件流已有 execution 事件"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "已完成")
  fixture_seed_execution_started "$task"

  if _run_transition "$task" --repair-evidence --reason "x" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应拒绝：已有 execution 事件，无需 repair"
  else
    if grep -q "无需 repair" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺「无需 repair」提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_repair_evidence_aborts_on_eof_without_yes() {
  start_test "I-RE5 repair-evidence aborts on EOF when --yes not passed"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "已完成")
  task_stem=$(basename "$task" .md)
  events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  echo "{\"event\":\"status_changed\",\"timestamp\":\"2020-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待执行\",\"to\":\"执行中\"}" > "$events_file"
  fixture_create_task_worktree "$task" "req-001-test" >/dev/null

  if (cd "$FIXTURE_DIR" && python3 "$TASK_TRANSITION" "$task" --repair-evidence --reason "x" </dev/null) >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应在 EOF 时中止"
  else
    if grep -q "已取消" /tmp/err.$$ && ! grep -q "execution_manual_completed" "$events_file"; then
      pass_test
    else
      _fail "abort 后不应补记事件"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_accept_gate_fail_closed_bad_encoding() {
  start_test "accept 闸门 fail-closed 执行中→已完成 when 事件流非法 UTF-8"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中")
  task_stem=$(basename "$task" .md)
  printf '\xff\xfe bad bytes' > "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  if _run_transition "$task" --to 已完成 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应 fail-closed 拒绝：事件流非法 UTF-8"
  else
    if grep -q "fail-closed" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺 fail-closed 提示（疑 UnicodeDecodeError 未捕获）"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_repair_evidence_rejects_when_branch_missing() {
  start_test "I-RE6 repair-evidence reject 当 task 分支不存在（close-task 已跑完）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "已完成")
  task_stem=$(basename "$task" .md)
  echo "{\"event\":\"status_changed\",\"timestamp\":\"2020-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待执行\",\"to\":\"执行中\"}" > "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  # 不建 task worktree/分支 —— 模拟 close-task 已删分支

  if _run_transition "$task" --repair-evidence --reason "x" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "应拒绝：task 分支不存在"
  else
    if grep -q "分支" /tmp/err.$$ && grep -q "不存在" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺分支不存在提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-DISCARD: --discard 路径
# -----------------------------------------------------------------

test_discard_from_pending() {
  start_test "I-DISCARD discard 待执行 task (no worktree)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "002" "demo" "待执行")
  task_basename=$(basename "$task")

  if _run_transition "$task" --discard --reason "拆分有误" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    if [ -f "$req_dir/tasks/discarded/$task_basename" ] && [ ! -f "$task" ]; then
      pass_test
    else
      _fail "task 文件未正确移动"
      ls -la "$req_dir/tasks/" "$req_dir/tasks/discarded/" >&2 2>&1 || true
    fi
  else
    _fail "discard 失败"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_discard_from_executing_with_worktree() {
  start_test "I-DISCARD discard 执行中 task + clean worktree+branch"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "002" "demo" "执行中")
  task_basename=$(basename "$task")
  task_branch="task-002-demo"
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # task_wt 是 fixture 创建后返回的绝对路径
  if _run_transition "$task" --discard --reason "试错重做" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    moved=ok
    [ -f "$req_dir/tasks/discarded/$task_basename" ] || moved="not-moved"
    [ -f "$task" ] && moved="orig-still-exists"

    wt_cleared=ok
    [ -d "$task_wt" ] && wt_cleared="worktree-still-exists"

    branch_cleared=ok
    if (cd "$FIXTURE_DIR" && git show-ref --verify --quiet "refs/heads/$task_branch") 2>/dev/null; then
      branch_cleared="branch-still-exists"
    fi

    if [ "$moved" = ok ] && [ "$wt_cleared" = ok ] && [ "$branch_cleared" = ok ]; then
      pass_test
    else
      _fail "moved=$moved wt=$wt_cleared branch=$branch_cleared"
      cat /tmp/err.$$ >&2
    fi
  else
    _fail "discard 失败"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_discard_from_executing_post_commit() {
  start_test "I-DISCARD discard 执行中 task (commit 后呈交期间)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  # commit 后呈交期间 task 状态仍是「执行中」（2026-05-08「待验收」合并入「执行中」）
  task=$(fixture_create_task "$req_dir" "002" "demo" "执行中")
  task_basename=$(basename "$task")

  if _run_transition "$task" --discard --reason "需求改了" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    if [ -f "$req_dir/tasks/discarded/$task_basename" ]; then
      pass_test
    else
      _fail "task 未归档"
    fi
  else
    _fail "discard 失败"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_discard_done_rejected_with_guidance() {
  start_test "I-DISCARD reject 已完成 with revert/cancel-req guidance"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "002" "demo" "已完成")

  if _run_transition "$task" --discard --reason "x" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject discard from 已完成"
  else
    if grep -q "已完成 task 不能 discard" /tmp/err.$$ && grep -q "cancel-req" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 未出现引导文案"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_discard_missing_reason() {
  start_test "I-DISCARD reject without --reason"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "002" "demo" "待执行")

  if _run_transition "$task" --discard --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject discard without --reason"
  else
    if grep -qi "reason" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing reason message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_discard_aborts_on_eof_without_yes() {
  start_test "I-DISCARD aborts on EOF when --yes not passed"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "002" "demo" "待执行")
  task_basename=$(basename "$task")

  if (cd "$FIXTURE_DIR" && python3 "$TASK_TRANSITION" "$task" --discard --reason "x" </dev/null) >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should abort on EOF"
  else
    if grep -q "已取消" /tmp/err.$$; then
      # 文件不应该被移动
      if [ -f "$task" ] && [ ! -f "$req_dir/tasks/discarded/$task_basename" ]; then
        pass_test
      else
        _fail "abort 后文件被错误移动"
      fi
    else
      _fail "stderr missing 已取消"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_discard_unblocks_stage6_rollback() {
  start_test "I-DISCARD post-discard, req-transition --rollback to stage 5 passes"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  fixture_create_task "$req_dir" "001" "done" "已完成" >/dev/null
  task2=$(fixture_create_task "$req_dir" "002" "todo" "待执行")

  if ! _run_transition "$task2" --discard --reason "重拆" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "discard 失败"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  REQ_TRANSITION="$FRAMEWORK_ROOT/scripts/req-transition.py"
  if (cd "$FIXTURE_DIR" && python3 "$REQ_TRANSITION" "$req_dir" --to 5 --rollback) >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "rollback 应放行"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_discard_appends_reason_section() {
  start_test "I-DISCARD task 文件含 状态=已废弃 + 废弃理由 section"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "002" "demo" "待执行")
  task_basename=$(basename "$task")

  if _run_transition "$task" --discard --reason "拆得不对" --yes >/tmp/out.$$ 2>/tmp/err.$$; then
    new_path="$req_dir/tasks/discarded/$task_basename"
    if grep -q '^\*\*状态：\*\* 已废弃' "$new_path" && \
       grep -q '^## 废弃理由' "$new_path" && \
       grep -q '拆得不对' "$new_path"; then
      pass_test
    else
      _fail "task 文件内容缺字段或 section"
      cat "$new_path" >&2
    fi
  else
    _fail "discard 失败"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# --validate-fields-only （task-spec 步骤 10.6 机器兜底）
# -----------------------------------------------------------------

test_validate_fields_only_passes_paragraph_format() {
  start_test "I-VFO1 段落格式 + 合法状态值 → 退出 0"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")

  if _run_transition "$task" --validate-fields-only >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q "字段校验通过" /tmp/out.$$; then
      pass_test
    else
      _fail "stdout 缺通过提示"
      cat /tmp/out.$$ /tmp/err.$$ >&2
    fi
  else
    _fail "应通过但失败了"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_validate_fields_only_passes_table_format() {
  start_test "I-VFO2 任务卡表格格式 + 合法状态值 → 退出 0"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task_v2 "$req_dir" "001" "demo" "待执行")

  if _run_transition "$task" --validate-fields-only >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "v2 表格格式应通过校验"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_validate_fields_only_rejects_blockquote() {
  start_test "I-VFO3 blockquote frontmatter (> 状态：...) → 退出 1"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")

  # 把段落格式改成 blockquote（模拟 task-spec 假执行的产物）
  python3 - "$task" <<'PY'
import sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
text = text.replace("**状态：** 待执行", "> 状态：「待启动」")
open(p, "w", encoding="utf-8").write(text)
PY

  if _run_transition "$task" --validate-fields-only >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "blockquote frontmatter 不该通过校验"
  else
    if grep -q "无法在 task 文件前 40 行解析出「状态」字段" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺预期诊断"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_validate_fields_only_rejects_derived_label() {
  start_test "I-VFO4 派生显示标签「待启动」作为状态值 → 退出 1"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")

  # 用合法格式但非法值（status-view 派生标签）
  _force_status "$task" "待启动"

  if _run_transition "$task" --validate-fields-only >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "派生显示标签不该作为合法状态值通过"
  else
    if grep -q "状态字段值「待启动」非法" /tmp/err.$$ && \
       grep -q "派生显示标签" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 缺合法 4 态枚举或派生标签提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_reject_reverse_transition
test_reject_from_done
test_reject_skip_transition
test_reject_parallel_active_task_now_allowed
test_reject_empty_doc_diff
test_reject_empty_self_review
test_allow_missing_review_event
test_allow_sentinel_review_tool
test_allow_empty_review_tool
test_reject_self_loop_executing
test_happy_path_start_to_done
test_accept_gate_pass_execution_started
test_accept_gate_pass_manual_completed
test_accept_gate_reject_no_execution_event
test_accept_gate_fail_closed_malformed_events
test_accept_gate_fail_closed_bad_encoding
test_repair_evidence_appends_marked_event
test_repair_evidence_rejects_missing_reason
test_repair_evidence_rejects_non_done_status
test_repair_evidence_rejects_when_already_has_event
test_repair_evidence_aborts_on_eof_without_yes
test_repair_evidence_rejects_when_branch_missing
test_discard_from_pending
test_discard_from_executing_with_worktree
test_discard_from_executing_post_commit
test_discard_done_rejected_with_guidance
test_discard_missing_reason
test_discard_aborts_on_eof_without_yes
test_discard_unblocks_stage6_rollback
test_discard_appends_reason_section
test_validate_fields_only_passes_paragraph_format
test_validate_fields_only_passes_table_format
test_validate_fields_only_rejects_blockquote
test_validate_fields_only_rejects_derived_label

report_results "task-transition"
