#!/usr/bin/env bash
# 测试 pre-commit hook：docs 顶层约定 + engineering index + attachments warning。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

INSTALL_HOOKS="$FRAMEWORK_ROOT/scripts/install-hooks.sh"

# pre-commit hook 模板按 $PMAI_HOME 解析 checker 路径（默认 ~/.pmai）。把它指向本仓，
# 不依赖、不改动用户的 ~/.pmai 安装；git 调 hook 时继承本进程环境。
export PMAI_HOME="$FRAMEWORK_ROOT"

# Helper: 把当前 fixture 装上 hook（在 fixture main worktree 里跑 install-hooks.sh）
_install_hook() {
  (cd "$FIXTURE_DIR" && bash "$INSTALL_HOOKS") >/dev/null
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
# T2: 普通 commit 通过
# -----------------------------------------------------------------

test_unrelated_commit_passes() {
  start_test "I-PCH2 普通 commit 通过 hook"
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
# T3: 重装幂等（已是相同模板时不备份不覆盖）
# -----------------------------------------------------------------

test_install_idempotent() {
  start_test "I-PCH3 重复安装幂等（同模板不备份）"
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
# T4: 已存在不同 hook 时备份
# -----------------------------------------------------------------

test_install_backs_up_existing() {
  start_test "I-PCH4 已存在不同 hook 内容时备份再覆盖"
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
# T5: attachments/ 小文件 commit 不触发末尾段 silent fail
# 回归测试：末尾 STAGED_LARGE=$(... | while read; done) 在命中
# attachments 且文件 ≤10MB 时，while body 末 `[ ] && echo` 返回 1 →
# while exit 1 → $() 失败 → 顶部 set -e 触发 silent abort（无 stderr）。
# 修复：done 后 `|| true`。
# -----------------------------------------------------------------

test_attachments_small_file_no_silent_fail() {
  start_test "I-PCH5 attachments/ ≤10MB 文件 commit 不被 silent fail"
  fixture_setup
  _install_hook

  mkdir -p "$FIXTURE_DIR/sample/attachments"
  echo "small payload" > "$FIXTURE_DIR/sample/attachments/note.txt"

  if (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "add small attachment") >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "attachments/ 小文件 commit 不该被 hook 拦（silent fail 回归）"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T6: attachments/ 大文件 (>10MB) 触发 warn 但不 block
# -----------------------------------------------------------------

test_attachments_big_file_warn_but_pass() {
  start_test "I-PCH6 attachments/ >10MB 文件触发 warn 但 commit 通过"
  fixture_setup
  _install_hook

  mkdir -p "$FIXTURE_DIR/big/attachments"
  dd if=/dev/zero of="$FIXTURE_DIR/big/attachments/huge.bin" bs=1M count=12 >/dev/null 2>&1

  if (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "add big attachment") >/tmp/out.$$ 2>/tmp/err.$$; then
    if grep -q "attachments/ 内有 >10MB 文件" /tmp/err.$$; then
      pass_test
    else
      _fail "大文件应触发 warn stderr 但没看到"
      cat /tmp/err.$$ >&2
    fi
  else
    _fail "大文件 commit 不该被 block（仅 warn）"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# T7: engineering 文档接回后未登记 INDEX 会被 hook 拦
# -----------------------------------------------------------------

test_engineering_doc_requires_index_entry() {
  start_test "I-PCH7 engineering 文档未登记 INDEX 时 commit 被拦"
  fixture_setup
  _install_hook

  mkdir -p "$FIXTURE_DIR/docs/engineering"
  printf '# 工程文档索引\n' > "$FIXTURE_DIR/docs/engineering/INDEX.md"
  printf '# API Auth\n' > "$FIXTURE_DIR/docs/engineering/api-auth.md"

  if (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "add engineering doc") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "未登记 engineering 文档应被 pre-commit 拦下"
  elif grep -q "docs/engineering/INDEX.md" /tmp/err.$$; then
    pass_test
  else
    _fail "拦截提示应指向 docs/engineering/INDEX.md"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_install_creates_executable_hook
test_unrelated_commit_passes
test_install_idempotent
test_install_backs_up_existing
test_attachments_small_file_no_silent_fail
test_attachments_big_file_warn_but_pass
test_engineering_doc_requires_index_entry

report_results "pre-commit-hook"
