#!/usr/bin/env bash
# 测试 pre-commit hook：拦截非法 task 状态字段直改。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

INSTALL_HOOKS="$FRAMEWORK_ROOT/scripts/install-hooks.sh"
TASK_TRANSITION="$FRAMEWORK_ROOT/scripts/task-transition.py"

# Helper: 把当前 fixture 装上 hook（在 fixture main worktree 里跑 install-hooks.sh）
_install_hook() {
  (cd "$FIXTURE_DIR" && bash "$INSTALL_HOOKS") >/dev/null
}

# Helper: 强制改状态字段（bypass task-transition）
_sed_force_status() {
  local task="$1"
  local status="$2"
  sed -i.bak "s|^\*\*状态：\*\*.*|\*\*状态：\*\* $status|" "$task"
  rm -f "$task.bak"
}

# -----------------------------------------------------------------
# T1: install-hooks.sh 在主仓装好可执行 hook
# -----------------------------------------------------------------

test_install_creates_executable_hook() {
  start_test "I-PCH1 install-hooks 创建可执行 pre-commit hook"
  fixture_setup
  _install_hook

  hook="$FIXTURE_DIR/.git/hooks/pre-commit"
  if [ -f "$hook" ] && [ -x "$hook" ]; then
    pass_test
  else
    _fail "hook 文件缺失或不可执行: $hook"
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# T2: 不含 task 文件的 commit 通过
# -----------------------------------------------------------------

test_unrelated_commit_passes() {
  start_test "I-PCH2 不含 task 文件的 commit 通过 hook"
  fixture_setup
  _install_hook

  echo "hello" > "$FIXTURE_DIR/README.md"
  if (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "add readme") >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "无关 commit 不该被拦"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T3: 新建 task 文件（HEAD 没有）的 commit 通过
# -----------------------------------------------------------------

test_newly_added_task_passes() {
  start_test "I-PCH3 新建 task（HEAD 不存在该文件）通过 hook"
  fixture_setup
  _install_hook

  # fixture_create_task 自己会在 req worktree 里 commit。
  # 该 commit 包含 newly-added task — 应该被 hook 放行。
  req_dir=$(fixture_create_req "req-001" "test" 6)
  if task=$(fixture_create_task "$req_dir" "001" "demo" "待执行" 2>/tmp/err.$$); then
    if [ -f "$task" ]; then
      pass_test
    else
      _fail "task 文件未创建"
      cat /tmp/err.$$ >&2
    fi
  else
    _fail "fixture_create_task 失败（hook 误拦新建？）"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T4: 合法 transition（task-transition.py 推进）的 commit 通过
# -----------------------------------------------------------------

test_legal_transition_passes() {
  start_test "I-PCH4 task-transition.py 合法推进后 commit 通过"
  fixture_setup
  _install_hook

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")
  req_wt=$(dirname "$(dirname "$(dirname "$task")")")

  # 在 req worktree 里跑 task-transition.py 推进状态
  (cd "$req_wt" && python3 "$TASK_TRANSITION" "$task" --to 执行中) >/tmp/out.$$ 2>/tmp/err.$$ || {
    _fail "task-transition.py 失败"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  }

  # 现在 commit 该状态变更
  if (cd "$req_wt" && git add -A && git commit -q -m "transition to 执行中") >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "合法推进后 commit 被误拦"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T5: 非法直改（sed 改状态字段）的 commit 被拒
# -----------------------------------------------------------------

test_direct_edit_rejected() {
  start_test "I-PCH5 sed 直改状态字段后 commit 被拒"
  fixture_setup
  _install_hook

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")
  req_wt=$(dirname "$(dirname "$(dirname "$task")")")

  # 直改文件（不留事件痕迹）
  _sed_force_status "$task" "执行中"

  if (cd "$req_wt" && git add -A && git commit -q -m "sneaky edit") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "非法直改不该通过 hook"
    cat /tmp/err.$$ >&2
  else
    if grep -q "拦截非法 task 状态字段直改" /tmp/err.$$ && \
       grep -q "task-transition.py" /tmp/err.$$; then
      pass_test
    else
      _fail "拦截信息缺关键提示"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T6: 状态字段未变（只改其他章节）的 commit 通过
# -----------------------------------------------------------------

test_other_section_edit_passes() {
  start_test "I-PCH6 状态字段未变、只改其他章节 → 通过"
  fixture_setup
  _install_hook

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")
  req_wt=$(dirname "$(dirname "$(dirname "$task")")")

  # 改 PM 反馈段，状态不动
  cat >> "$task" <<'EOF'

#### 反馈 1 - 2026-05-07
**问题描述：** 测试反馈
**要求修改：** 改文案
**处理结果：** 待处理
EOF

  if (cd "$req_wt" && git add -A && git commit -q -m "add PM feedback") >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "状态没变的 commit 不该被拦"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T7: --no-verify 绕过
# -----------------------------------------------------------------

test_no_verify_bypasses() {
  start_test "I-PCH7 --no-verify 救火绕过"
  fixture_setup
  _install_hook

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "待执行")
  req_wt=$(dirname "$(dirname "$(dirname "$task")")")

  _sed_force_status "$task" "执行中"

  if (cd "$req_wt" && git add -A && git commit --no-verify -q -m "force") >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "--no-verify 不该被 hook 阻塞"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T8: 重装幂等（已是相同模板时不备份不覆盖）
# -----------------------------------------------------------------

test_install_idempotent() {
  start_test "I-PCH8 重复安装幂等（同模板不备份）"
  fixture_setup
  _install_hook

  # 第二次安装：不该产生 .bak
  (cd "$FIXTURE_DIR" && bash "$INSTALL_HOOKS") >/tmp/out.$$ 2>&1
  if grep -q "已是最新版" /tmp/out.$$ && \
     ! ls "$FIXTURE_DIR/.git/hooks/pre-commit.bak."* 2>/dev/null | grep -q .; then
    pass_test
  else
    _fail "重装应幂等，不该有 .bak"
    cat /tmp/out.$$ >&2
    ls "$FIXTURE_DIR/.git/hooks/" >&2
  fi
  rm -f /tmp/out.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T9: 已存在不同 hook 时备份
# -----------------------------------------------------------------

test_install_backs_up_existing() {
  start_test "I-PCH9 已存在不同 hook 内容时备份再覆盖"
  fixture_setup

  # 装一个假 hook
  mkdir -p "$FIXTURE_DIR/.git/hooks"
  echo "#!/bin/sh" > "$FIXTURE_DIR/.git/hooks/pre-commit"
  echo "echo old hook" >> "$FIXTURE_DIR/.git/hooks/pre-commit"
  chmod +x "$FIXTURE_DIR/.git/hooks/pre-commit"

  (cd "$FIXTURE_DIR" && bash "$INSTALL_HOOKS") >/tmp/out.$$ 2>&1

  bak_count=$(ls "$FIXTURE_DIR/.git/hooks/pre-commit.bak."* 2>/dev/null | wc -l | tr -d ' ')
  if [ "$bak_count" -ge 1 ]; then
    pass_test
  else
    _fail "应备份原 hook 但没看到 .bak"
    cat /tmp/out.$$ >&2
    ls "$FIXTURE_DIR/.git/hooks/" >&2
  fi
  rm -f /tmp/out.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_install_creates_executable_hook
test_unrelated_commit_passes
test_newly_added_task_passes
test_legal_transition_passes
test_direct_edit_rejected
test_other_section_edit_passes
test_no_verify_bypasses
test_install_idempotent
test_install_backs_up_existing

report_results "pre-commit-hook"
