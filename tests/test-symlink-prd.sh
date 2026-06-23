#!/usr/bin/env bash
# Tests for docs/prds/ PRD 收口 symlink — close-work / cancel-work / helper unit
#
# 真相源迁移（lifecycle 迁移批 3，方案 A）：PRD 源从旧 requirements/pmai-closed/<work>/prd.md
# 改到模块文件夹 docs/modules/<模块>/prd.md。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_WORK="$FRAMEWORK_ROOT/scripts/close-work.sh"
CANCEL_WORK="$FRAMEWORK_ROOT/scripts/cancel-work.sh"
SYMLINK_LIB="$FRAMEWORK_ROOT/scripts/_lib/symlink-prd.sh"

# 把 work-meta stage 推到 4（六步沉淀 = MAX_STAGE）+ commit（close-work I-CR1 要 stage=4）
_bump_stage_to_finalize() {
  local work_dir="$1"
  local work_branch
  work_branch=$(python3 -c "import json; print(json.load(open('$work_dir/.work-meta.json'))['branch'])")
  python3 -c "
import json
p = '$work_dir/.work-meta.json'
m = json.load(open(p))
m['stage'] = 4
json.dump(m, open(p, 'w'), indent=2, ensure_ascii=False)
"
  (
    cd "$FIXTURE_DIR/.worktrees/$work_branch"
    git add -A
    git commit -q -m "stage 4 沉淀"
  )
}

# 在 worktree 模块目录写 prd.md + commit
_write_prd_in_worktree() {
  local work_dir="$1"
  local body="${2:-# PRD\n\n本 work 的 PRD 内容。}"
  local work_branch
  work_branch=$(python3 -c "import json; print(json.load(open('$work_dir/.work-meta.json'))['branch'])")
  printf '%b\n' "$body" > "$work_dir/prd.md"
  (
    cd "$FIXTURE_DIR/.worktrees/$work_branch"
    git add -A
    git commit -q -m "add prd.md"
  )
}

# cancel-work 要求模块在 main 的 docs/modules/ 下；镜像过去
_mirror_module_to_main() {
  local work_id="$1"
  local name="$2"
  local work_branch="build-$work_id-$name"
  local main_module="$FIXTURE_DIR/docs/modules/$work_branch"
  mkdir -p "$main_module"
  cp -R "$FIXTURE_DIR/.worktrees/$work_branch/docs/modules/$work_branch/." "$main_module/"
  (cd "$FIXTURE_DIR" && git add -A >/dev/null 2>&1 && git commit -q -m "mirror $work_id on main" 2>/dev/null || true)
  echo "$main_module"
}

# =================================================
# helper unit: kind=closed 正常路径
# =================================================
test_helper_closed_happy() {
  start_test "helper: kind=closed 建对相对 symlink"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/docs/modules/module-100-helper"
  echo "# fake prd" > "$FIXTURE_DIR/docs/modules/module-100-helper/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "module-100-helper" closed
  ) >/tmp/out.$$ 2>/tmp/err.$$ || {
    _fail "helper returned non-zero"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  }

  link="$FIXTURE_DIR/docs/prds/module-100-helper.md"
  if [ ! -L "$link" ]; then
    _fail "symlink not created: $link"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../docs/modules/module-100-helper/prd.md"
  assert_equal "$expected" "$target" "symlink target wrong" || { rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  if ! grep -q "fake prd" "$link"; then
    _fail "symlink does not resolve to prd.md"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# helper unit: kind=cancelled 子目录 + 多一层 ../
# =================================================
test_helper_cancelled_happy() {
  start_test "helper: kind=cancelled 建在 docs/prds/废弃/ 子目录"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/docs/modules/module-101-helpcancel"
  echo "# cancelled prd" > "$FIXTURE_DIR/docs/modules/module-101-helpcancel/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "module-101-helpcancel" cancelled
  ) >/tmp/out.$$ 2>/tmp/err.$$ || {
    _fail "helper returned non-zero"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  }

  link="$FIXTURE_DIR/docs/prds/废弃/module-101-helpcancel.md"
  if [ ! -L "$link" ]; then
    _fail "symlink not created: $link"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../../docs/modules/module-101-helpcancel/prd.md"
  assert_equal "$expected" "$target" "cancelled symlink target wrong" || { rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  if ! grep -q "cancelled prd" "$link"; then
    _fail "cancelled symlink does not resolve"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# helper unit: PRD 不存在 silent skip
# =================================================
test_helper_no_prd_silent_skip() {
  start_test "helper: 无 prd.md silent skip 返回 0"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/docs/modules/module-102-noprd"
  # 不写 prd.md

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "module-102-noprd" cancelled
  ) >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "expected silent-skip rc=0, got rc=$rc"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -e "$FIXTURE_DIR/docs/prds/废弃/module-102-noprd.md" ]; then
    _fail "should not create symlink when prd.md missing"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# helper unit: 未知 kind 报错
# =================================================
test_helper_unknown_kind_rejects() {
  start_test "helper: 未知 kind 返回非 0"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/docs/modules/module-103-x"
  echo "# x" > "$FIXTURE_DIR/docs/modules/module-103-x/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "module-103-x" bogus
  ) >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "expected non-zero rc for unknown kind, got 0"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q "未知 kind" /tmp/err.$$; then
    _fail "stderr missing 未知 kind message"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# helper unit: 同名普通文件存在时拒绝
# =================================================
test_helper_refuses_overwriting_regular_file() {
  start_test "helper: 同名普通文件存在时拒绝"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/docs/modules/module-104-clash"
  echo "# clash prd" > "$FIXTURE_DIR/docs/modules/module-104-clash/prd.md"
  mkdir -p "$FIXTURE_DIR/docs/prds"
  echo "preexisting" > "$FIXTURE_DIR/docs/prds/module-104-clash.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "module-104-clash" closed
  ) >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "expected non-zero rc when overwriting regular file"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q "preexisting" "$FIXTURE_DIR/docs/prds/module-104-clash.md"; then
    _fail "regular file got overwritten"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# helper unit: 已有 symlink 幂等覆盖
# =================================================
test_helper_idempotent_on_existing_symlink() {
  start_test "helper: 已有 symlink 幂等覆盖"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/docs/modules/module-105-idem"
  echo "# idem prd" > "$FIXTURE_DIR/docs/modules/module-105-idem/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "module-105-idem" closed
    create_prd_symlink "$FIXTURE_DIR" "module-105-idem" closed
  ) >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "rerun should be idempotent, got rc=$rc"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  link="$FIXTURE_DIR/docs/prds/module-105-idem.md"
  if [ ! -L "$link" ]; then
    _fail "symlink missing after rerun"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# E2E: close-work happy path 建 docs/prds/<模块>.md
# =================================================
test_close_work_creates_prd_symlink() {
  start_test "close-work: happy path 建 docs/prds/<模块>.md symlink"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "syml" 1)
  _write_prd_in_worktree "$work_dir" "# Work 001 PRD\n本 work PRD 正文。"
  _bump_stage_to_finalize "$work_dir"

  if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work failed"
    echo "--- stderr ---" >&2
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  link="$FIXTURE_DIR/docs/prds/build-work-001-syml.md"
  if [ ! -L "$link" ]; then
    _fail "expected symlink at $link"
    ls -la "$FIXTURE_DIR/docs/prds/" >&2 2>&1 || true
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../docs/modules/build-work-001-syml/prd.md"
  assert_equal "$expected" "$target" "symlink target wrong" || { rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  if ! grep -q "Work 001 PRD" "$link"; then
    _fail "symlink does not resolve to prd content"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# E2E: close-work 无 prd.md (理论上很少见) 仍能完成不报错
# =================================================
test_close_work_without_prd_silent_skip() {
  start_test "close-work: 无 prd.md silent skip 不报错"
  fixture_setup

  work_dir=$(fixture_create_work "work-002" "noprd" 4)
  # 不写 prd.md

  if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work failed when no prd.md"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -e "$FIXTURE_DIR/docs/prds/build-work-002-noprd.md" ]; then
    _fail "should not create symlink when prd.md absent"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# E2E: cancel-work 有 prd.md 建 docs/prds/废弃/<模块>.md
# =================================================
test_cancel_work_creates_cancelled_symlink() {
  start_test "cancel-work: 有 prd.md 建 docs/prds/废弃/<模块>.md symlink"
  fixture_setup

  # 在 worktree 模块目录写 prd.md
  fixture_create_work "work-003" "cancel-with-prd" 3 >/dev/null
  printf "# Cancelled PRD\n本 work 写过 PRD 但被 cancel。\n" \
    > "$FIXTURE_DIR/.worktrees/build-work-003-cancel-with-prd/docs/modules/build-work-003-cancel-with-prd/prd.md"
  (
    cd "$FIXTURE_DIR/.worktrees/build-work-003-cancel-with-prd"
    git add -A && git commit -q -m "add prd"
  )

  # 镜像模块到 main docs/modules/
  main_module=$(_mirror_module_to_main "work-003" "cancel-with-prd")

  cd "$FIXTURE_DIR"
  if ! bash "$CANCEL_WORK" "$main_module" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel-work failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  link="$FIXTURE_DIR/docs/prds/废弃/build-work-003-cancel-with-prd.md"
  if [ ! -L "$link" ]; then
    _fail "expected cancelled symlink at $link"
    ls -la "$FIXTURE_DIR/docs/prds/废弃/" >&2 2>&1 || true
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../../docs/modules/build-work-003-cancel-with-prd/prd.md"
  assert_equal "$expected" "$target" "cancelled symlink target wrong" || { rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  if ! grep -q "Cancelled PRD" "$link"; then
    _fail "cancelled symlink does not resolve"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# E2E: cancel-work 无 prd.md (stage 1/2 cancel) silent skip
# =================================================
test_cancel_work_without_prd_silent_skip() {
  start_test "cancel-work: 无 prd.md (stage 1/2 cancel) silent skip"
  fixture_setup

  fixture_create_work "work-004" "cancel-noprd" 2 >/dev/null
  main_module=$(_mirror_module_to_main "work-004" "cancel-noprd")

  cd "$FIXTURE_DIR"
  if ! bash "$CANCEL_WORK" "$main_module" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel-work failed on no-prd path"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -e "$FIXTURE_DIR/docs/prds/废弃/build-work-004-cancel-noprd.md" ]; then
    _fail "should not create symlink when prd.md absent"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Run all
# =================================================
test_helper_closed_happy
test_helper_cancelled_happy
test_helper_no_prd_silent_skip
test_helper_unknown_kind_rejects
test_helper_refuses_overwriting_regular_file
test_helper_idempotent_on_existing_symlink
test_close_work_creates_prd_symlink
test_close_work_without_prd_silent_skip
test_cancel_work_creates_cancelled_symlink
test_cancel_work_without_prd_silent_skip

report_results "symlink-prd"
