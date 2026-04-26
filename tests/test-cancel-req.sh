#!/usr/bin/env bash
# Tests for cancel-req.sh — enforces invariants I-CA1 ~ I-CA6

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CANCEL_REQ="$FRAMEWORK_ROOT/scripts/cancel-req.sh"
CLEANUP_PENDING="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"

# cancel-req.sh expects the req-dir to live under the MAIN repo's requirements/active/.
# Fixture creates it inside the req worktree. We mirror it to main so the script
# can find it (and test the move-to-closed behavior on main).
#
# Returns the path to the req dir on main.
_setup_req_on_main() {
  local req_id="$1"
  local name="$2"
  local stage="${3:-3}"
  local req_branch="$req_id-$name"

  # Standard fixture creates worktree + req dir inside worktree
  fixture_create_req "$req_id" "$name" "$stage" >/dev/null

  # Also copy req dir to main repo's requirements/active/ so cancel-req can mv it
  local main_req_dir="$FIXTURE_DIR/requirements/active/$req_branch"
  mkdir -p "$main_req_dir"
  cp -R "$FIXTURE_DIR/.worktrees/$req_branch/requirements/active/$req_branch/." "$main_req_dir/"

  # Commit the main-side req dir so git status is clean (not strictly required)
  (cd "$FIXTURE_DIR" && git add -A >/dev/null 2>&1 && git commit -q -m "mirror req $req_id on main" 2>/dev/null || true)

  echo "$main_req_dir"
}

# ---------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------

test_cancel_happy_path() {
  start_test "happy path: cancel removes worktree, branch, moves dir to closed/"
  fixture_setup
  req_dir=$(_setup_req_on_main "req-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1

  # Cancel 后 worktree/branch 推迟到 cleanup（防止 dangling cwd）。
  # 跑 cleanup 完成清理，再断言已删。
  bash "$CLEANUP_PENDING" >/dev/null 2>&1

  # Worktree removed
  if [ -d "$FIXTURE_DIR/.worktrees/req-001-test" ]; then
    _fail "req worktree should be gone after cleanup"
    fixture_teardown; return
  fi
  # Branch removed
  if git -C "$FIXTURE_DIR" branch --list req-001-test | grep -q .; then
    _fail "req branch should be deleted after cleanup"
    fixture_teardown; return
  fi
  # Dir moved to closed/
  if [ ! -d "$FIXTURE_DIR/requirements/closed/req-001-test" ]; then
    _fail "req dir should be in requirements/closed/"
    fixture_teardown; return
  fi
  # active/ is gone
  if [ -d "$FIXTURE_DIR/requirements/active/req-001-test" ]; then
    _fail "req dir should NOT remain in active/"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA1: main 零污染
# ---------------------------------------------------------------

test_cancel_does_not_merge_to_main() {
  start_test "I-CA1 cancel does not merge req code to main"
  fixture_setup
  req_dir=$(_setup_req_on_main "req-001" "test" 3)

  # 在 req 分支上加一个显著的文件，证明 req 分支有内容
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "req-only content" > req-only-marker.md
    git add -A
    git commit -q -m "req work"
  )

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1

  # main 上不应该存在 req-only-marker.md
  if [ -f "$FIXTURE_DIR/req-only-marker.md" ]; then
    _fail "main should NOT have req branch's content"
    fixture_teardown; return
  fi

  # git log on main should not contain req's commit message
  if git -C "$FIXTURE_DIR" log main --oneline | grep -q "req work"; then
    _fail "main log should not contain 'req work' commit"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA2: 活跃 task 被清理
# ---------------------------------------------------------------

test_cancel_cleans_active_task() {
  start_test "I-CA2 cancel with active task removes task worktree + branch"
  fixture_setup
  req_dir=$(_setup_req_on_main "req-001" "test" 3)

  # 在 main 侧的 req 目录里建 task
  task_file=$(fixture_create_task "$req_dir" "001" "impl" "执行中")
  # 建 task worktree（off req 分支）
  task_wt=$(fixture_create_task_worktree "$task_file" "req-001-test")

  # sanity
  if [ ! -d "$task_wt" ]; then
    _fail "task worktree setup failed"
    fixture_teardown; return
  fi

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1

  # Cancel 后清理推迟到 cleanup
  bash "$CLEANUP_PENDING" >/dev/null 2>&1

  # task worktree gone
  if [ -d "$task_wt" ]; then
    _fail "task worktree should be removed after cleanup"
    fixture_teardown; return
  fi
  # task branch gone
  if git -C "$FIXTURE_DIR" branch --list "task-001-impl" | grep -q .; then
    _fail "task branch should be deleted after cleanup"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA4: 目录到 closed/，meta.status=cancelled
# ---------------------------------------------------------------

test_cancel_sets_meta_status_cancelled() {
  start_test "I-CA4 after cancel, meta.status == 'cancelled' in closed/"
  fixture_setup
  req_dir=$(_setup_req_on_main "req-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1

  closed_meta="$FIXTURE_DIR/requirements/closed/req-001-test/.req-meta.json"
  if [ ! -f "$closed_meta" ]; then
    _fail "closed meta should exist at $closed_meta"
    fixture_teardown; return
  fi
  status=$(python3 -c "import json; print(json.load(open('$closed_meta'))['status'])" 2>/dev/null)
  if [ "$status" = "cancelled" ]; then
    pass_test
  else
    _fail "meta.status should be 'cancelled', got '$status'"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA5: 幂等
# ---------------------------------------------------------------

test_cancel_is_idempotent_after_partial_cleanup() {
  start_test "I-CA5 idempotent: re-run after partial cleanup does not error"
  fixture_setup
  req_dir=$(_setup_req_on_main "req-001" "test" 3)

  # 手动模拟部分清理状态：删掉 worktree 和分支（但留下 active/ 目录和 meta）
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"
  git -C "$FIXTURE_DIR" branch -D req-001-test 2>/dev/null || true

  cd "$FIXTURE_DIR"
  # 再跑 cancel-req 应该能清理完剩下的（active → closed + meta 更新）且不报错
  if bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1; then
    :
  else
    _fail "second-run cancel-req failed (rc=$?)"
    fixture_teardown; return
  fi

  # closed/ 应该存在
  if [ ! -d "$FIXTURE_DIR/requirements/closed/req-001-test" ]; then
    _fail "closed/ dir should exist after idempotent re-run"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

test_cancel_rerun_on_fully_closed_does_not_error() {
  start_test "I-CA5 idempotent: running cancel twice on same req does not crash"
  fixture_setup
  req_dir=$(_setup_req_on_main "req-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1
  # 第二次：req_dir 已被 mv 到 closed/，所以先尝试用 closed 路径再跑
  closed_dir="$FIXTURE_DIR/requirements/closed/req-001-test"
  # 第二次传 closed 路径，脚本应优雅处理（meta 在但 worktree/active 目录都没了）
  if bash "$CANCEL_REQ" "$closed_dir" >/dev/null 2>&1; then
    pass_test
  else
    _fail "second cancel-req run should not crash (rc=$?)"
  fi
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA6: cancel-req must clean task worktrees/branches even when req
# only exists in the req worktree (not mirrored on main).
# ---------------------------------------------------------------

test_cancel_cleans_tasks_when_req_not_on_main() {
  start_test "I-CA6 cancel cleans task branches when req only in req worktree"
  fixture_setup

  # 不走 _setup_req_on_main：req 目录只存在于 req worktree，不在 main 上
  fixture_create_req "req-001" "test" 3 >/dev/null
  req_dir_in_wt="$FIXTURE_DIR/.worktrees/req-001-test/requirements/active/req-001-test"

  # 在 req worktree 的 req dir 里建 task
  task_file=$(fixture_create_task "$req_dir_in_wt" "001" "impl" "执行中")
  task_wt=$(fixture_create_task_worktree "$task_file" "req-001-test")

  # 跑 cancel-req，传入 req worktree 里的 req 目录
  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir_in_wt" >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "cancel-req should succeed (rc=$rc)"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  # Cancel 后清理推迟到 cleanup
  bash "$CLEANUP_PENDING" >/dev/null 2>&1

  # task worktree/分支 必须清掉
  if [ -d "$task_wt" ]; then
    _fail "task worktree left behind after cleanup: $task_wt"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi
  if git -C "$FIXTURE_DIR" branch --list "task-001-impl" | grep -q .; then
    _fail "task branch left behind after cleanup"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA7: cancel-req must refuse when main has unrelated dirty changes
# ---------------------------------------------------------------

test_cancel_rejects_dirty_main() {
  start_test "I-CA7 cancel rejects when main has unrelated dirty changes"
  fixture_setup
  req_dir=$(_setup_req_on_main "req-001" "test" 3)

  # 在 main 留一个无关脏文件
  echo "stray" > "$FIXTURE_DIR/unrelated.txt"

  cd "$FIXTURE_DIR"
  if bash "$CANCEL_REQ" "$req_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel should have refused with dirty main"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  if ! grep -qE "(污染|unrelated|无关|拒绝)" /tmp/err.$$; then
    _fail "stderr missing pollution-refusal message"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  # 无关文件仍然在，说明没污染 cancel commit
  if [ ! -f "$FIXTURE_DIR/unrelated.txt" ]; then
    _fail "unrelated file got consumed"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  # 没有 cancel commit 进入 main
  if git -C "$FIXTURE_DIR" log main --oneline | grep -q "cancel:"; then
    _fail "main log should not contain a cancel commit"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# ---------------------------------------------------------------
# Run all
# ---------------------------------------------------------------

test_cancel_happy_path
test_cancel_does_not_merge_to_main
test_cancel_cleans_active_task
test_cancel_sets_meta_status_cancelled
test_cancel_is_idempotent_after_partial_cleanup
test_cancel_rerun_on_fully_closed_does_not_error
test_cancel_cleans_tasks_when_req_not_on_main
test_cancel_rejects_dirty_main

report_results "cancel-req"
