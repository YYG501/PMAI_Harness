#!/usr/bin/env bash
# Tests for check-branch.sh — enforces invariants I-CB1 ~ I-CB8
# The hook reads JSON from stdin. Exit 0 + "{}" = allow; exit 2 + decision=deny = deny.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CHECK_BRANCH="$FRAMEWORK_ROOT/scripts/check-branch.sh"

# Build hook JSON and feed to check-branch.sh in the current cwd.
# Usage: run_check <tool> <file_path> [old_string] [new_string] [content]
# Prints stdout, returns exit code from the hook.
run_check() {
  local tool="$1"
  local file_path="$2"
  local old_string="${3:-}"
  local new_string="${4:-}"
  local content="${5:-}"

  python3 - "$tool" "$file_path" "$old_string" "$new_string" "$content" <<'PY' | bash "$CHECK_BRANCH"
import json, sys
tool, fp, old, new, content = sys.argv[1:6]
ti = {"file_path": fp}
if old or new:
    ti["old_string"] = old
    ti["new_string"] = new
if content:
    ti["content"] = content
print(json.dumps({"tool_name": tool, "tool_input": ti}))
PY
}

# Capture stdout + exit code of run_check into globals OUT / RC.
# Usage: capture_check <tool> <path> [old] [new] [content]
capture_check() {
  OUT=$(run_check "$@" 2>&1)
  RC=$?
}

# ---------------------------------------------------------------
# I-CB3: main 白名单
# ---------------------------------------------------------------

test_main_rejects_src_write() {
  start_test "I-CB3 main rejects write to src/foo.ts (not whitelisted)"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p src
  capture_check "Write" "src/foo.ts" "" "" "hello"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should deny main write to src/foo.ts (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_allows_claude_settings() {
  start_test "I-CB3 main allows .claude/settings.json (whitelisted)"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" ".claude/settings.json" "" "" "{}"
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow .claude/settings.json on main (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_allows_requirements_active_brief() {
  start_test "I-CB3 main allows requirements/active/req-001/brief.md"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "requirements/active/req-001/brief.md" "" "" "# Brief"
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow requirements/active write on main (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_rejects_random_toplevel() {
  start_test "I-CB3 main rejects random top-level file (e.g. notes.md)"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "notes.md" "" "" "hello"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should deny notes.md on main (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CB1 / I-CB2: 绝对路径 + 跨 worktree 推导有效分支
# ---------------------------------------------------------------

test_abs_path_from_task_to_req_worktree_gate() {
  start_test "I-CB1/CB2 in task wt, abs path into req worktree → gated by req branch"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)
  # 给 req 里放一个 task 文件
  task_file=$(fixture_create_task "$req_dir" "001" "impl" "执行中")
  # 在主仓里建一个 task worktree 指向这个 task（off req 分支）
  task_wt=$(fixture_create_task_worktree "$task_file" "req-001-test")

  # 从 task worktree 里，用绝对路径指向 req worktree 下的 prototypes/
  cd "$task_wt"
  mkdir -p "$FIXTURE_DIR/.worktrees/req-001-test/prototypes" 2>/dev/null || true
  abs_target="$FIXTURE_DIR/.worktrees/req-001-test/prototypes/bad.ts"

  capture_check "Write" "$abs_target" "" "" "x"
  # 目标所在 worktree 是 req-* 分支 → I-CB5 拒绝 prototypes/
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "abs path into req wt should be gated by req branch (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_abs_path_from_task_to_main_repo_gate() {
  start_test "I-CB1/CB2 in task wt, abs path into main repo root → gated by main"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)
  task_file=$(fixture_create_task "$req_dir" "001" "impl" "执行中")
  task_wt=$(fixture_create_task_worktree "$task_file" "req-001-test")

  cd "$task_wt"
  # 用绝对路径写主仓根的 src/foo.ts（非白名单）
  abs_target="$FIXTURE_DIR/src/foo.ts"
  capture_check "Write" "$abs_target" "" "" "x"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "abs path into main should be gated by main whitelist (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CB4: task 分支不能写 docs/
# ---------------------------------------------------------------

test_task_branch_rejects_docs_write() {
  start_test "I-CB4 task branch rejects write to docs/modules/xxx.md"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)
  task_file=$(fixture_create_task "$req_dir" "001" "impl" "执行中")
  task_wt=$(fixture_create_task_worktree "$task_file" "req-001-test")

  cd "$task_wt"
  mkdir -p docs/modules
  capture_check "Write" "docs/modules/xxx.md" "" "" "content"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "task branch should deny docs/ writes (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CB5: req 分支不能写 prototypes/
# ---------------------------------------------------------------

test_req_branch_rejects_prototypes_write() {
  start_test "I-CB5 req branch rejects write to prototypes/index.ts"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  cd "$FIXTURE_DIR/.worktrees/req-001-test"
  mkdir -p prototypes
  capture_check "Write" "prototypes/index.ts" "" "" "console.log(1)"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "req branch should deny prototypes/ writes (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CB6: 禁止直接改 task 状态字段 / req stage 字段
# ---------------------------------------------------------------

test_reject_direct_task_status_edit() {
  start_test "I-CB6 reject direct edit to task 状态 field"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)
  task_file=$(fixture_create_task "$req_dir" "001" "impl" "待确认")

  cd "$FIXTURE_DIR/.worktrees/req-001-test"
  # Edit: 把状态从 待确认 改成 执行中
  old='**状态：** 待确认'
  new='**状态：** 执行中'
  capture_check "Edit" "$task_file" "$old" "$new" ""
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"' && echo "$OUT" | grep -q "task-transition"; then
    pass_test
  else
    _fail "should deny direct task status edit (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_reject_direct_req_stage_edit() {
  start_test "I-CB6 reject direct edit to .req-meta.json stage"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  cd "$FIXTURE_DIR/.worktrees/req-001-test"
  meta="$req_dir/.req-meta.json"
  old='"stage": 3'
  new='"stage": 4'
  capture_check "Edit" "$meta" "$old" "$new" ""
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"' && echo "$OUT" | grep -q "req-transition"; then
    pass_test
  else
    _fail "should deny direct req stage edit (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CB9: 仓库外路径默认拒绝（fail-closed）
# ---------------------------------------------------------------

test_outside_repo_non_tmp_denied() {
  start_test "I-CB9 path outside repo (non-/tmp) denied by default"
  fixture_setup
  cd "$FIXTURE_DIR"

  # 用 /Users/xxx 或任意非 /tmp 的外部路径
  capture_check "Write" "/Users/nobody/evil.txt" "" "" "x"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "outside-repo non-tmp path should be denied (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_outside_repo_tmp_allowed() {
  start_test "I-CB9 /tmp path allowed as escape hatch"
  fixture_setup
  cd "$FIXTURE_DIR"

  capture_check "Write" "/tmp/scratch.txt" "" "" "x"
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "/tmp should be allowed (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# Run all
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# I-CB10: Task status must be 执行中 to write code in task worktree
# ---------------------------------------------------------------

test_task_status_gate_rejects_when_pending() {
  start_test "I-CB10 reject task worktree write when status=待确认"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "010" "gate" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # Attempt to write a code file from inside the task worktree
  cd "$task_wt"
  capture_check "Write" "prototypes/sneak.ts" "" "" "console.log('leaked')"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q "I-CB10"; then
    pass_test
  else
    _fail "should deny code write when task status=待确认 (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_task_status_gate_allows_when_executing() {
  start_test "I-CB10 allow task worktree write when status=执行中"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "011" "gate-ok" "执行中" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  cd "$task_wt"
  capture_check "Write" "prototypes/legit.ts" "" "" "export {}"
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow code write when task status=执行中 (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_task_status_gate_allows_task_file_edit() {
  start_test "I-CB10 allow editing task.md itself (執行日志/自审) even when not 执行中"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "012" "gate-taskfile" "待验收" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  cd "$task_wt"
  # 编辑 task 文件的非状态字段应放行（状态字段由 Gate 1 保护）
  capture_check "Edit" "requirements/active/req-001-test/tasks/task-012-gate-taskfile.md" \
    "## 执行日志" "## 执行日志\nnew entry" ""
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow task file edit even when status!=执行中 (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_rejects_src_write
test_main_allows_claude_settings
test_main_allows_requirements_active_brief
test_main_rejects_random_toplevel
test_abs_path_from_task_to_req_worktree_gate
test_abs_path_from_task_to_main_repo_gate
test_task_branch_rejects_docs_write
test_req_branch_rejects_prototypes_write
test_reject_direct_task_status_edit
test_reject_direct_req_stage_edit
test_outside_repo_non_tmp_denied
test_outside_repo_tmp_allowed
test_task_status_gate_rejects_when_pending
test_task_status_gate_allows_when_executing
test_task_status_gate_allows_task_file_edit

report_results "check-branch"
