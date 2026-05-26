#!/usr/bin/env bash
# Tests for docs/prds/ PRD 收口 symlink — close-req / cancel-req / helper unit

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_REQ="$FRAMEWORK_ROOT/scripts/close-req.sh"
CANCEL_REQ="$FRAMEWORK_ROOT/scripts/cancel-req.sh"
SYMLINK_LIB="$FRAMEWORK_ROOT/scripts/_lib/symlink-prd.sh"

# 把 req-meta stage 推到 7 + commit（close-req I-CR1 要 stage=7）
_bump_stage_to_7() {
  local req_dir="$1"
  local req_branch
  req_branch=$(python3 -c "import json; print(json.load(open('$req_dir/.req-meta.json'))['branch'])")
  python3 -c "
import json
p = '$req_dir/.req-meta.json'
m = json.load(open(p))
m['stage'] = 7
json.dump(m, open(p, 'w'), indent=2, ensure_ascii=False)
"
  (
    cd "$FIXTURE_DIR/.worktrees/$req_branch"
    git add -A
    git commit -q -m "stage 7"
  )
}

# 在 req worktree 写 prd.md + commit
_write_prd_in_req_worktree() {
  local req_dir="$1"
  local body="${2:-# PRD\n\n本 req 的 PRD 内容。}"
  local req_branch
  req_branch=$(python3 -c "import json; print(json.load(open('$req_dir/.req-meta.json'))['branch'])")
  printf '%b\n' "$body" > "$req_dir/prd.md"
  (
    cd "$FIXTURE_DIR/.worktrees/$req_branch"
    git add -A
    git commit -q -m "add prd.md"
  )
}

# cancel-req 要求 req 在 main 的 active/ 下；镜像过去
_mirror_to_main() {
  local req_id="$1"
  local name="$2"
  local req_branch="$req_id-$name"
  local main_req_dir="$FIXTURE_DIR/requirements/active/$req_branch"
  mkdir -p "$main_req_dir"
  cp -R "$FIXTURE_DIR/.worktrees/$req_branch/requirements/active/$req_branch/." "$main_req_dir/"
  (cd "$FIXTURE_DIR" && git add -A >/dev/null 2>&1 && git commit -q -m "mirror $req_id on main" 2>/dev/null || true)
  echo "$main_req_dir"
}

# =================================================
# helper unit: kind=closed 正常路径
# =================================================
test_helper_closed_happy() {
  start_test "helper: kind=closed 建对相对 symlink"
  fixture_setup

  # 手工准备一个 closed req 目录 + prd.md
  mkdir -p "$FIXTURE_DIR/requirements/closed/req-100-helper"
  echo "# fake prd" > "$FIXTURE_DIR/requirements/closed/req-100-helper/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "req-100-helper" closed
  ) >/tmp/out.$$ 2>/tmp/err.$$ || {
    _fail "helper returned non-zero"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  }

  link="$FIXTURE_DIR/docs/prds/req-100-helper.md"
  if [ ! -L "$link" ]; then
    _fail "symlink not created: $link"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../requirements/closed/req-100-helper/prd.md"
  assert_equal "$expected" "$target" "symlink target wrong" || { rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  # symlink 真能 resolve 到 prd.md 内容
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

  mkdir -p "$FIXTURE_DIR/requirements/closed/req-101-helpcancel"
  echo "# cancelled prd" > "$FIXTURE_DIR/requirements/closed/req-101-helpcancel/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "req-101-helpcancel" cancelled
  ) >/tmp/out.$$ 2>/tmp/err.$$ || {
    _fail "helper returned non-zero"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  }

  link="$FIXTURE_DIR/docs/prds/废弃/req-101-helpcancel.md"
  if [ ! -L "$link" ]; then
    _fail "symlink not created: $link"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../../requirements/closed/req-101-helpcancel/prd.md"
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

  mkdir -p "$FIXTURE_DIR/requirements/closed/req-102-noprd"
  # 不写 prd.md

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "req-102-noprd" cancelled
  ) >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "expected silent-skip rc=0, got rc=$rc"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -e "$FIXTURE_DIR/docs/prds/废弃/req-102-noprd.md" ]; then
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

  mkdir -p "$FIXTURE_DIR/requirements/closed/req-103-x"
  echo "# x" > "$FIXTURE_DIR/requirements/closed/req-103-x/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "req-103-x" bogus
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

  mkdir -p "$FIXTURE_DIR/requirements/closed/req-104-clash"
  echo "# clash prd" > "$FIXTURE_DIR/requirements/closed/req-104-clash/prd.md"
  mkdir -p "$FIXTURE_DIR/docs/prds"
  echo "preexisting" > "$FIXTURE_DIR/docs/prds/req-104-clash.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "req-104-clash" closed
  ) >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "expected non-zero rc when overwriting regular file"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # 原文件未被覆盖
  if ! grep -q "preexisting" "$FIXTURE_DIR/docs/prds/req-104-clash.md"; then
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

  mkdir -p "$FIXTURE_DIR/requirements/closed/req-105-idem"
  echo "# idem prd" > "$FIXTURE_DIR/requirements/closed/req-105-idem/prd.md"

  (
    source "$SYMLINK_LIB"
    create_prd_symlink "$FIXTURE_DIR" "req-105-idem" closed
    create_prd_symlink "$FIXTURE_DIR" "req-105-idem" closed
  ) >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "rerun should be idempotent, got rc=$rc"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  link="$FIXTURE_DIR/docs/prds/req-105-idem.md"
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
# E2E: close-req happy path 建 docs/prds/<req>.md
# =================================================
test_close_req_creates_prd_symlink() {
  start_test "close-req: happy path 建 docs/prds/<req>.md symlink"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "syml" 1)
  _write_prd_in_req_worktree "$req_dir" "# Req 001 PRD\n本 req PRD 正文。"
  _bump_stage_to_7 "$req_dir"

  if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-req failed"
    echo "--- stderr ---" >&2
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  link="$FIXTURE_DIR/docs/prds/req-001-syml.md"
  if [ ! -L "$link" ]; then
    _fail "expected symlink at $link"
    ls -la "$FIXTURE_DIR/docs/prds/" >&2 2>&1 || true
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../requirements/closed/req-001-syml/prd.md"
  assert_equal "$expected" "$target" "symlink target wrong" || { rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  # symlink 真能 resolve（指向已存在的 closed/<req>/prd.md）
  if ! grep -q "Req 001 PRD" "$link"; then
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
# E2E: close-req 无 prd.md (理论上很少见) 仍能完成不报错
# =================================================
test_close_req_without_prd_silent_skip() {
  start_test "close-req: 无 prd.md silent skip 不报错"
  fixture_setup

  req_dir=$(fixture_create_req "req-002" "noprd" 7)
  # 不写 prd.md

  if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_REQ" "$req_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-req failed when no prd.md"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -e "$FIXTURE_DIR/docs/prds/req-002-noprd.md" ]; then
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
# E2E: cancel-req 有 prd.md 建 docs/prds/废弃/<req>.md
# =================================================
test_cancel_req_creates_cancelled_symlink() {
  start_test "cancel-req: 有 prd.md 建 docs/prds/废弃/<req>.md symlink"
  fixture_setup

  # 在 req worktree 写 prd.md
  fixture_create_req "req-003" "cancel-with-prd" 3 >/dev/null
  printf "# Cancelled PRD\n本 req 写过 PRD 但被 cancel。\n" \
    > "$FIXTURE_DIR/.worktrees/req-003-cancel-with-prd/requirements/active/req-003-cancel-with-prd/prd.md"
  (
    cd "$FIXTURE_DIR/.worktrees/req-003-cancel-with-prd"
    git add -A && git commit -q -m "add prd"
  )

  # 镜像到 main active/
  main_req_dir=$(_mirror_to_main "req-003" "cancel-with-prd")

  cd "$FIXTURE_DIR"
  if ! bash "$CANCEL_REQ" "$main_req_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel-req failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  link="$FIXTURE_DIR/docs/prds/废弃/req-003-cancel-with-prd.md"
  if [ ! -L "$link" ]; then
    _fail "expected cancelled symlink at $link"
    ls -la "$FIXTURE_DIR/docs/prds/废弃/" >&2 2>&1 || true
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  target=$(readlink "$link")
  expected="../../../requirements/closed/req-003-cancel-with-prd/prd.md"
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
# E2E: cancel-req 无 prd.md (stage 1/2 cancel) silent skip
# =================================================
test_cancel_req_without_prd_silent_skip() {
  start_test "cancel-req: 无 prd.md (stage 1/2 cancel) silent skip"
  fixture_setup

  fixture_create_req "req-004" "cancel-noprd" 2 >/dev/null
  main_req_dir=$(_mirror_to_main "req-004" "cancel-noprd")

  cd "$FIXTURE_DIR"
  if ! bash "$CANCEL_REQ" "$main_req_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel-req failed on no-prd path"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -e "$FIXTURE_DIR/docs/prds/废弃/req-004-cancel-noprd.md" ]; then
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
test_close_req_creates_prd_symlink
test_close_req_without_prd_silent_skip
test_cancel_req_creates_cancelled_symlink
test_cancel_req_without_prd_silent_skip

report_results "symlink-prd"
