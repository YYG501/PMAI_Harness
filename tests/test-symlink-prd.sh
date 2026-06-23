#!/usr/bin/env bash
# Tests for docs/prds/ PRD 收口 symlink — close-work / cancel-work / helper unit
#
# 真相源迁移（lifecycle 迁移批 3，方案 A）：PRD 源从 requirements/pmai-closed/<req>/prd.md
# 改到模块文件夹 docs/modules/<模块>/prd.md。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_WORK="$FRAMEWORK_ROOT/scripts/close-work.sh"
CANCEL_WORK="$FRAMEWORK_ROOT/scripts/cancel-work.sh"
SYMLINK_LIB="$FRAMEWORK_ROOT/scripts/_lib/symlink-prd.sh"
SYNC_PRDS="$FRAMEWORK_ROOT/bin/pmai-sync-prds"

# 在 FIXTURE_DIR 直接造一个模块目录 + prd.md（不走 close-work 流程，模拟历史老仓）
# status: closed | cancelled | active | (none) → none 时不写 .work-meta（= 已收尾）
_seed_module() {
  local module="$1"
  local status="$2"   # closed | cancelled | active | none
  local with_prd="${3:-yes}"   # yes | no
  local dir="$FIXTURE_DIR/docs/modules/$module"
  mkdir -p "$dir"
  if [ "$status" != "none" ]; then
    cat >"$dir/.work-meta.json" <<EOF
{"id": "${module%%-*}", "branch": "$module", "status": "$status"}
EOF
  fi
  if [ "$with_prd" = "yes" ]; then
    echo "# Seeded PRD for $module" > "$dir/prd.md"
  fi
}

# 把 work-meta stage 推到 4（六步沉淀 = MAX_STAGE）+ commit（close-work I-CR1 要 stage=4）
_bump_stage_to_finalize() {
  local work_dir="$1"
  local req_branch
  req_branch=$(python3 -c "import json; print(json.load(open('$work_dir/.work-meta.json'))['branch'])")
  python3 -c "
import json
p = '$work_dir/.work-meta.json'
m = json.load(open(p))
m['stage'] = 4
json.dump(m, open(p, 'w'), indent=2, ensure_ascii=False)
"
  (
    cd "$FIXTURE_DIR/.worktrees/$req_branch"
    git add -A
    git commit -q -m "stage 4 沉淀"
  )
}

# 在 worktree 模块目录写 prd.md + commit
_write_prd_in_req_worktree() {
  local work_dir="$1"
  local body="${2:-# PRD\n\n本 work 的 PRD 内容。}"
  local req_branch
  req_branch=$(python3 -c "import json; print(json.load(open('$work_dir/.work-meta.json'))['branch'])")
  printf '%b\n' "$body" > "$work_dir/prd.md"
  (
    cd "$FIXTURE_DIR/.worktrees/$req_branch"
    git add -A
    git commit -q -m "add prd.md"
  )
}

# cancel-work 要求模块在 main 的 docs/modules/ 下；镜像过去
_mirror_module_to_main() {
  local req_id="$1"
  local name="$2"
  local req_branch="$req_id-$name"
  local main_module="$FIXTURE_DIR/docs/modules/$req_branch"
  mkdir -p "$main_module"
  cp -R "$FIXTURE_DIR/.worktrees/$req_branch/docs/modules/$req_branch/." "$main_module/"
  (cd "$FIXTURE_DIR" && git add -A >/dev/null 2>&1 && git commit -q -m "mirror $req_id on main" 2>/dev/null || true)
  echo "$main_module"
}

# =================================================
# helper unit: kind=closed 正常路径
# =================================================
test_helper_closed_happy() {
  start_test "helper: kind=closed 建对相对 symlink"
  fixture_setup

  mkdir -p "$FIXTURE_DIR/docs/modules/req-100-helper"
  echo "# fake prd" > "$FIXTURE_DIR/docs/modules/req-100-helper/prd.md"

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
  expected="../../docs/modules/req-100-helper/prd.md"
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

  mkdir -p "$FIXTURE_DIR/docs/modules/req-101-helpcancel"
  echo "# cancelled prd" > "$FIXTURE_DIR/docs/modules/req-101-helpcancel/prd.md"

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
  expected="../../../docs/modules/req-101-helpcancel/prd.md"
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

  mkdir -p "$FIXTURE_DIR/docs/modules/req-102-noprd"
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

  mkdir -p "$FIXTURE_DIR/docs/modules/req-103-x"
  echo "# x" > "$FIXTURE_DIR/docs/modules/req-103-x/prd.md"

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

  mkdir -p "$FIXTURE_DIR/docs/modules/req-104-clash"
  echo "# clash prd" > "$FIXTURE_DIR/docs/modules/req-104-clash/prd.md"
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

  mkdir -p "$FIXTURE_DIR/docs/modules/req-105-idem"
  echo "# idem prd" > "$FIXTURE_DIR/docs/modules/req-105-idem/prd.md"

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
# E2E: close-work happy path 建 docs/prds/<模块>.md
# =================================================
test_close_req_creates_prd_symlink() {
  start_test "close-work: happy path 建 docs/prds/<模块>.md symlink"
  fixture_setup

  work_dir=$(fixture_create_req "req-001" "syml" 1)
  _write_prd_in_req_worktree "$work_dir" "# Req 001 PRD\n本 work PRD 正文。"
  _bump_stage_to_finalize "$work_dir"

  if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work failed"
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
  expected="../../docs/modules/req-001-syml/prd.md"
  assert_equal "$expected" "$target" "symlink target wrong" || { rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

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
# E2E: close-work 无 prd.md (理论上很少见) 仍能完成不报错
# =================================================
test_close_req_without_prd_silent_skip() {
  start_test "close-work: 无 prd.md silent skip 不报错"
  fixture_setup

  work_dir=$(fixture_create_req "req-002" "noprd" 4)
  # 不写 prd.md

  if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work failed when no prd.md"
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
# E2E: cancel-work 有 prd.md 建 docs/prds/废弃/<模块>.md
# =================================================
test_cancel_req_creates_cancelled_symlink() {
  start_test "cancel-work: 有 prd.md 建 docs/prds/废弃/<模块>.md symlink"
  fixture_setup

  # 在 worktree 模块目录写 prd.md
  fixture_create_req "req-003" "cancel-with-prd" 3 >/dev/null
  printf "# Cancelled PRD\n本 work 写过 PRD 但被 cancel。\n" \
    > "$FIXTURE_DIR/.worktrees/req-003-cancel-with-prd/docs/modules/req-003-cancel-with-prd/prd.md"
  (
    cd "$FIXTURE_DIR/.worktrees/req-003-cancel-with-prd"
    git add -A && git commit -q -m "add prd"
  )

  # 镜像模块到 main docs/modules/
  main_module=$(_mirror_module_to_main "req-003" "cancel-with-prd")

  cd "$FIXTURE_DIR"
  if ! bash "$CANCEL_WORK" "$main_module" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel-work failed"
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
  expected="../../../docs/modules/req-003-cancel-with-prd/prd.md"
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
test_cancel_req_without_prd_silent_skip() {
  start_test "cancel-work: 无 prd.md (stage 1/2 cancel) silent skip"
  fixture_setup

  fixture_create_req "req-004" "cancel-noprd" 2 >/dev/null
  main_module=$(_mirror_module_to_main "req-004" "cancel-noprd")

  cd "$FIXTURE_DIR"
  if ! bash "$CANCEL_WORK" "$main_module" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel-work failed on no-prd path"
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
# sync-prds: 无 docs/modules/ → silent exit 0
# =================================================
test_sync_prds_no_modules_dir() {
  start_test "sync-prds: 无 docs/modules/ silent exit 0"
  fixture_setup
  rm -rf "$FIXTURE_DIR/docs/modules"

  if ! (cd "$FIXTURE_DIR" && bash "$SYNC_PRDS") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "sync-prds rc!=0 on empty modules/"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q "不存在" /tmp/out.$$; then
    _fail "expected '不存在' notice"
    cat /tmp/out.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# sync-prds: closed(无meta) + cancelled + active 混合，建对该建的
# =================================================
test_sync_prds_mixed_modules() {
  start_test "sync-prds: 已收尾/cancelled/active 混合都判对"
  fixture_setup

  _seed_module "req-200-alpha" none yes        # 无 meta = 已收尾 → closed
  _seed_module "req-201-beta" closed yes        # status closed → closed
  _seed_module "req-202-trash" cancelled yes    # cancelled
  _seed_module "req-203-noprd" none no          # 无 prd → 跳过
  _seed_module "req-204-active" active yes       # 在做的工作 → 跳过

  if ! (cd "$FIXTURE_DIR" && bash "$SYNC_PRDS") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "sync-prds failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # closed 类
  for r in req-200-alpha req-201-beta; do
    if [ ! -L "$FIXTURE_DIR/docs/prds/$r.md" ]; then
      _fail "missing symlink: docs/prds/$r.md"
      cat /tmp/out.$$ >&2
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi
  done

  # cancelled 类
  if [ ! -L "$FIXTURE_DIR/docs/prds/废弃/req-202-trash.md" ]; then
    _fail "missing cancelled symlink"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # 跳过类不应存在
  if [ -e "$FIXTURE_DIR/docs/prds/req-203-noprd.md" ]; then
    _fail "no-prd module should be skipped"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi
  if [ -e "$FIXTURE_DIR/docs/prds/req-204-active.md" ]; then
    _fail "active-status module should be skipped"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # 汇总数字：3 个建/更新（alpha + beta + trash）
  if ! grep -qE "建/更新: 3" /tmp/out.$$; then
    _fail "summary count wrong (expected 建/更新: 3)"
    cat /tmp/out.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# sync-prds: --dry-run 不动文件
# =================================================
test_sync_prds_dry_run() {
  start_test "sync-prds: --dry-run 不动文件"
  fixture_setup

  _seed_module "req-205-dry" none yes

  if ! (cd "$FIXTURE_DIR" && bash "$SYNC_PRDS" --dry-run) >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "dry-run failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ -e "$FIXTURE_DIR/docs/prds/req-205-dry.md" ]; then
    _fail "dry-run should not create symlink"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if ! grep -q "\[dry\]" /tmp/out.$$; then
    _fail "dry-run output missing [dry] tag"
    cat /tmp/out.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# sync-prds: 重跑幂等（已建过的不报错）
# =================================================
test_sync_prds_idempotent() {
  start_test "sync-prds: 重跑幂等"
  fixture_setup

  _seed_module "req-206-idem" none yes

  (cd "$FIXTURE_DIR" && bash "$SYNC_PRDS") >/dev/null 2>&1
  if ! (cd "$FIXTURE_DIR" && bash "$SYNC_PRDS") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "second run failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  if [ ! -L "$FIXTURE_DIR/docs/prds/req-206-idem.md" ]; then
    _fail "symlink lost after rerun"
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
test_sync_prds_no_modules_dir
test_sync_prds_mixed_modules
test_sync_prds_dry_run
test_sync_prds_idempotent

report_results "symlink-prd"
