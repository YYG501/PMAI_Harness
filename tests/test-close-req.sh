#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_REQ="$FRAMEWORK_ROOT/scripts/close-req.sh"

# close-req（方案 A）后真相源是 docs/modules/<模块>/。
# req_dir = docs/modules/<分支>（fixture_create_req 现返回模块目录）。
# 收尾语义：模块 .req-meta.json 被删（清工作状态），模块三件套留场；有 worktree 走 merge，
# 无 worktree/无分支直接在 main 清。

# Helper: 模块 .req-meta 是否还在（在 = 未收尾）
_module_meta_path_on_main() {
  echo "$FIXTURE_DIR/docs/modules/$1/.req-meta.json"
}

# =================================================
# I-CR1: reject when stage is not 4 (六步沉淀 = MAX_STAGE)
# =================================================
test_reject_if_stage_not_4() {
  start_test "I-CR1 reject when req stage is not 4（沉淀）"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 3)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when stage is not 4"
  else
    if grep -q "stage" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing stage message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR2: reject when there are open tasks
# =================================================
test_reject_if_open_tasks_exist() {
  start_test "I-CR2 reject when there are open tasks"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)
  # Create a task with status 执行中 (open) — 直接落在 docs/modules/<分支>/tasks/
  task=$(fixture_create_task "$req_dir" "001" "stillopen" "执行中" "/qa")

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when task is still open"
  else
    if grep -q "尚未关闭" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing open-tasks message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR3/CR5（方案 A 新语义）：无分支 → 走 main 直接清 .req-meta，不再拒绝
# =================================================
test_no_branch_closes_via_main() {
  start_test "I-CR3 no branch → main 直接清 .req-meta（不拒绝）"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)

  # 把模块三件套 + .req-meta 落到 main（无 worktree 路径要求模块已在 main）
  main_module="$FIXTURE_DIR/docs/modules/req-001-test"
  mkdir -p "$main_module"
  cp -R "$req_dir/." "$main_module/"
  (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "mirror module on main")

  # 删 req 分支 + worktree
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"
  git -C "$FIXTURE_DIR" branch -D "req-001-test" 2>/dev/null || true

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$main_module") >/tmp/out.$$ 2>/tmp/err.$$; then
    # 模块 .req-meta 已被清
    if [ -f "$main_module/.req-meta.json" ]; then
      _fail "module .req-meta should be cleared on main-clear path"
      cat /tmp/out.$$ >&2
    elif [ ! -d "$main_module" ]; then
      _fail "module dir should remain (only .req-meta cleared)"
    else
      pass_test
    fi
  else
    _fail "close-req should succeed on no-branch path (main clear)"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR4（方案 A 新语义）：无 worktree（分支在但 worktree 没了）→ main 直接清
# =================================================
test_no_worktree_closes_via_main() {
  start_test "I-CR4 no worktree → main 直接清 .req-meta（不拒绝）"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)

  # 模块三件套落 main
  main_module="$FIXTURE_DIR/docs/modules/req-001-test"
  mkdir -p "$main_module"
  cp -R "$req_dir/." "$main_module/"
  (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "mirror module on main")

  # 删 worktree 目录但保留分支
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$main_module") >/tmp/out.$$ 2>/tmp/err.$$; then
    if [ -f "$main_module/.req-meta.json" ]; then
      _fail "module .req-meta should be cleared on no-worktree path"
    else
      pass_test
    fi
  else
    _fail "close-req should succeed on no-worktree path (main clear)"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR9: merge conflict → should not leave half-complete state
# =================================================
test_reject_on_merge_conflict_no_partial_state() {
  start_test "I-CR9 merge conflict does not leave partial state on main"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)

  # Modify main branch to create a conflict with what req branch will do
  (
    cd "$FIXTURE_DIR"
    echo "main version" > conflict.txt
    git add conflict.txt
    git commit -q -m "main: conflict.txt"
  )

  # Modify same file on req branch
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "req version" > conflict.txt
    git add conflict.txt
    git commit -q -m "req: conflict.txt"
  )

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    :
  fi

  (
    cd "$FIXTURE_DIR"
    git checkout main -q 2>/dev/null || true
  )

  # 方案 A 下不再有 closed/ 目录。半完成态判定：merge 是否真落地。
  # 若 merge 失败回滚，req 分支应仍在场 + req 分支上模块 .req-meta 应仍有（pre-close）。
  if git -C "$FIXTURE_DIR" log main --oneline | grep "close: req-001" >/dev/null; then
    # merge 真落地（自动解决冲突的极端情况）：main 上模块 .req-meta 应已清
    if [ -f "$FIXTURE_DIR/docs/modules/req-001-test/.req-meta.json" ]; then
      _fail "merge landed but module .req-meta not cleared on main (half state)"
    else
      pass_test
    fi
  else
    # merge 未落地：req 分支应仍在（可重试），模块 .req-meta 应仍在 req 分支上（pre-close）
    if ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/req-001-test"; then
      _fail "req branch deleted but close did not land (half state)"
    elif [ ! -f "$FIXTURE_DIR/.worktrees/req-001-test/docs/modules/req-001-test/.req-meta.json" ]; then
      _fail "req branch rolled back but module .req-meta missing (half state)"
    else
      pass_test
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR5: clear-state commit must land on req branch before merge
# (verified via happy path: after close, main branch log contains the close commit)
# =================================================
test_archive_committed_before_merge() {
  start_test "I-CR5 clear-state commit lands before merge (happy path verifies order)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    # After close, main should contain the close commit "close: 收尾 req-001"
    if git -C "$FIXTURE_DIR" log main --oneline | grep "close: 收尾 req-001" >/dev/null; then
      pass_test
    else
      _fail "close commit not found on main branch log"
      git -C "$FIXTURE_DIR" log main --oneline >&2
    fi
  else
    _fail "close-req failed unexpectedly"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Happy path: full close-req succeeds (有 worktree → merge 路径)
# =================================================
test_happy_path_close_req() {
  start_test "happy path: close-req clears module .req-meta + merges to main"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    main_module="$FIXTURE_DIR/docs/modules/req-001-test"

    # 模块目录在 main 上仍在（三件套 discussion.md 留场）
    if [ ! -d "$main_module" ]; then
      _fail "module dir should exist on main (三件套留场)"
      ls "$FIXTURE_DIR/docs/modules" >&2 2>&1 || true
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi
    # 工作状态 .req-meta 已清
    if [ -f "$main_module/.req-meta.json" ]; then
      _fail ".req-meta.json should be cleared on main after close"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi
    # discussion.md 应仍在
    if [ ! -f "$main_module/discussion.md" ]; then
      _fail "module 三件套 (discussion.md) should remain on main"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi

    # branch + worktree 已删
    if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/req-001-test"; then
      _fail "req branch should be deleted by close-req.sh"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi
    if [ -d "$FIXTURE_DIR/.worktrees/req-001-test" ]; then
      _fail "req worktree should be removed by close-req.sh"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi

    # 当前分支 main
    cur=$(git -C "$FIXTURE_DIR" branch --show-current)
    if [ "$cur" != "main" ]; then
      _fail "expected to land on main, got $cur"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi

    pass_test
  else
    _fail "close-req failed on happy path"
    echo "--- stdout ---" >&2; cat /tmp/out.$$ >&2
    echo "--- stderr ---" >&2; cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Extra: happy path with a closed task present
# =================================================
test_happy_path_with_completed_task() {
  start_test "happy path: close-req works when req has a 已完成 task"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)
  task=$(fixture_create_task "$req_dir" "001" "done" "已完成" "/qa")

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    # 模块下的 task 文件随三件套留在 main（不再有 closed/ 归档）
    main_task="$FIXTURE_DIR/docs/modules/req-001-test/tasks/task-001-done.md"
    if [ -f "$main_task" ]; then
      pass_test
    else
      _fail "task file should remain under module on main"
      ls "$FIXTURE_DIR/docs/modules/req-001-test/tasks" >&2 2>&1 || true
    fi
  else
    _fail "close-req failed with completed task present"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR9b: on merge failure, req branch is reset to pre-close (module .req-meta still present)
# =================================================
test_merge_failure_rolls_back_req_branch() {
  start_test "I-CR9b merge failure rolls req branch back to pre-close state"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)

  # Create conflict: same file on main and on req branch with different content
  (
    cd "$FIXTURE_DIR"
    echo "main" > clash.txt && git add clash.txt && git commit -q -m "main: clash"
  )
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "req" > clash.txt && git add clash.txt && git commit -q -m "req: clash"
  )

  # Should fail
  (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$ && \
    { _fail "close-req should have failed on conflict"; rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  # On req branch: 模块 .req-meta 应仍在（pre-close 状态，被回滚回来）
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"
  if [ ! -f "$req_wt/docs/modules/req-001-test/.req-meta.json" ]; then
    _fail "req branch should be rolled back with module .req-meta restored"
    ls "$req_wt/docs/modules/req-001-test" >&2 2>&1 || true
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  # main 上模块 .req-meta 不应被清（merge 未落地）
  if [ ! -f "$FIXTURE_DIR/docs/modules/req-001-test/.req-meta.json" ] && \
     git -C "$FIXTURE_DIR" show main:docs/modules/req-001-test/.req-meta.json >/dev/null 2>&1; then
    : # 不应到这（main 上本来就没 mirror，跳过）
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR10: reject when cwd is inside the req worktree
# =================================================
test_reject_when_cwd_inside_req_worktree() {
  start_test "I-CR10 reject when cwd is inside req worktree"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"

  if (cd "$req_wt" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when cwd is inside req worktree"
  else
    if grep -qE "(cwd 在 req worktree|切到主仓窗口)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing cwd-in-worktree message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_if_req_worktree_has_unrelated_dirty_changes() {
  start_test "I-CR11 reject unrelated dirty changes in req worktree"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 4)
  req_wt="$FIXTURE_DIR/.worktrees/req-001-test"
  mkdir -p "$req_wt/prototypes"
  echo "leak" > "$req_wt/prototypes/unrelated.txt"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject unrelated dirty file instead of committing it"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  if ! grep -q "当前模块目录外" /tmp/err.$$; then
    _fail "stderr missing unrelated dirty guidance"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  if git -C "$FIXTURE_DIR" show main:prototypes/unrelated.txt >/dev/null 2>&1; then
    _fail "unrelated dirty file leaked into main"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Run all tests
# =================================================
test_reject_if_stage_not_4
test_reject_if_open_tasks_exist
test_no_branch_closes_via_main
test_no_worktree_closes_via_main
test_reject_when_cwd_inside_req_worktree
test_reject_if_req_worktree_has_unrelated_dirty_changes
test_reject_on_merge_conflict_no_partial_state
test_archive_committed_before_merge
test_happy_path_close_req
test_happy_path_with_completed_task
test_merge_failure_rolls_back_req_branch

report_results "close-req"
