#!/usr/bin/env bash
# Tests for cancel-req.sh — enforces invariants I-CA1 ~ I-CA7（方案 A·清模块 .req-meta）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CANCEL_REQ="$FRAMEWORK_ROOT/scripts/cancel-req.sh"
CLEANUP_PENDING="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"

# cancel-req（方案 A）：真相源 = docs/modules/<模块>/。废弃 = 在 main 上清模块 .req-meta，
# 不 merge req 分支到 main；task/req worktree 推迟到 cleanup-pending 兜底清。
#
# fixture_create_req 在 req worktree 里建模块目录。把它镜像到 main 的 docs/modules/，
# 让 cancel-req 能在 main 上清掉模块 .req-meta。返回 main 上的模块目录路径。
_setup_module_on_main() {
  local req_id="$1"
  local name="$2"
  local stage="${3:-3}"
  local req_branch="$req_id-$name"

  fixture_create_req "$req_id" "$name" "$stage" >/dev/null

  local main_module="$FIXTURE_DIR/docs/modules/$req_branch"
  mkdir -p "$main_module"
  cp -R "$FIXTURE_DIR/.worktrees/$req_branch/docs/modules/$req_branch/." "$main_module/"

  (cd "$FIXTURE_DIR" && git add -A >/dev/null 2>&1 && git commit -q -m "mirror module $req_id on main" 2>/dev/null || true)

  echo "$main_module"
}

# ---------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------

test_cancel_happy_path() {
  start_test "happy path: cancel clears module .req-meta on main + removes worktree/branch"
  fixture_setup
  req_dir=$(_setup_module_on_main "req-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1

  # Cancel 后 worktree/branch 推迟到 cleanup（防 dangling cwd）。
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
  # 模块 .req-meta 已清（main 上）
  if [ -f "$FIXTURE_DIR/docs/modules/req-001-test/.req-meta.json" ]; then
    _fail "module .req-meta should be cleared on main"
    fixture_teardown; return
  fi
  # 模块三件套留场（discussion.md 仍在）
  if [ ! -f "$FIXTURE_DIR/docs/modules/req-001-test/discussion.md" ]; then
    _fail "module 三件套 (discussion.md) should remain on main"
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
  req_dir=$(_setup_module_on_main "req-001" "test" 3)

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
  req_dir=$(_setup_module_on_main "req-001" "test" 3)

  # 在 main 侧的模块目录里建 task
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
# I-CA4（方案 A）：cancel 后模块 .req-meta 已清（不再移 closed/、不再留 status=cancelled 文件）
# ---------------------------------------------------------------

test_cancel_clears_module_meta() {
  start_test "I-CA4 after cancel, module .req-meta is cleared (no closed/ archive)"
  fixture_setup
  req_dir=$(_setup_module_on_main "req-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1

  # 模块 .req-meta 应被删（main 上）
  if [ -f "$FIXTURE_DIR/docs/modules/req-001-test/.req-meta.json" ]; then
    _fail "module .req-meta should be cleared after cancel"
    fixture_teardown; return
  fi
  # 方案 A 下不再有 requirements/closed/ 归档目录
  if [ -d "$FIXTURE_DIR/requirements/closed/req-001-test" ]; then
    _fail "no requirements/closed/ archive should be created under 方案 A"
    fixture_teardown; return
  fi
  # cancel commit 应进入 main
  # 用 grep ... >/dev/null（不加 -q）：grep -q 命中即早退会让上游 git SIGPIPE，
  # 在 set -o pipefail 下整条管道返回非 0，假阴性。
  if ! git -C "$FIXTURE_DIR" log main --oneline | grep "cancel: req-001" >/dev/null; then
    _fail "main log should contain a cancel commit"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA5: 幂等
# ---------------------------------------------------------------

test_cancel_is_idempotent_after_partial_cleanup() {
  start_test "I-CA5 idempotent: re-run after partial cleanup does not error"
  fixture_setup
  req_dir=$(_setup_module_on_main "req-001" "test" 3)

  # 手动模拟部分清理状态：删掉 worktree 和分支（但留下 main 上的模块 .req-meta）
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"
  git -C "$FIXTURE_DIR" branch -D req-001-test 2>/dev/null || true

  cd "$FIXTURE_DIR"
  # 再跑 cancel-req 应该能清理完剩下的（清 main 上模块 .req-meta）且不报错
  if bash "$CANCEL_REQ" "$req_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    :
  else
    _fail "second-run cancel-req failed (rc=$?)"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  # 模块 .req-meta 应已清
  if [ -f "$FIXTURE_DIR/docs/modules/req-001-test/.req-meta.json" ]; then
    _fail "module .req-meta should be cleared after idempotent re-run"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi
  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_cancel_rerun_on_already_cleared_does_not_error() {
  start_test "I-CA5 idempotent: running cancel twice on same req does not crash"
  fixture_setup
  req_dir=$(_setup_module_on_main "req-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$req_dir" >/dev/null 2>&1
  # 第二次：模块 .req-meta 已被删，脚本应优雅退出（缺 meta 直接报错退出，rc!=0 但不崩溃）。
  # 用 cleanup 把 worktree/branch 清完后第二次跑：模块 .req-meta 已无 → 脚本 fail-fast（缺 meta）。
  bash "$CLEANUP_PENDING" >/dev/null 2>&1
  if bash "$CANCEL_REQ" "$req_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    # 已无 .req-meta，理应报「不存在」退出非 0；若返回 0 也不算崩溃
    pass_test
  else
    # 缺 meta 时 fail-fast 退出是预期的优雅处理（非崩溃）
    if grep -q "不存在" /tmp/err.$$; then
      pass_test
    else
      _fail "second cancel-req run should fail gracefully (got unexpected error)"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA6: cancel-req must clean task worktrees/branches even when module
# only exists in the req worktree (not mirrored on main).
# ---------------------------------------------------------------

test_cancel_cleans_tasks_when_module_not_on_main() {
  start_test "I-CA6 cancel cleans task branches when module only in req worktree"
  fixture_setup

  # 不走 _setup_module_on_main：模块目录只存在于 req worktree，不在 main 上
  module_dir_in_wt=$(fixture_create_req "req-001" "test" 3)

  # 在 req worktree 的模块目录里建 task
  task_file=$(fixture_create_task "$module_dir_in_wt" "001" "impl" "执行中")
  task_wt=$(fixture_create_task_worktree "$task_file" "req-001-test")

  # 跑 cancel-req，传入 req worktree 里的模块目录
  cd "$FIXTURE_DIR"
  bash "$CANCEL_REQ" "$module_dir_in_wt" >/tmp/out.$$ 2>/tmp/err.$$
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
  req_dir=$(_setup_module_on_main "req-001" "test" 3)

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
test_cancel_clears_module_meta
test_cancel_is_idempotent_after_partial_cleanup
test_cancel_rerun_on_already_cleared_does_not_error
test_cancel_cleans_tasks_when_module_not_on_main
test_cancel_rejects_dirty_main

report_results "cancel-req"
