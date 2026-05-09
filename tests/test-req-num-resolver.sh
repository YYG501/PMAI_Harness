#!/usr/bin/env bash
# Tests for scripts/_lib/req-num-resolver.sh
#
# 验证 next / first / list 三个子命令在以下场景的正确性：
# - 空仓（无任何 req）→ next=001, first=true
# - 只有 closed → next=N+1, first=false
# - 只有 active → next=N+1, first=false
# - 只有 git 分支 req-NNN-* → next=N+1, first=false（这是 v3.5 重点）
# - 三来源混合 → next=max+1
# - 三来源相同编号 → 去重
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/_lib/req-num-resolver.sh"

# Helper: 创建一个临时 git 仓库并初始化 requirements/ 目录结构
_make_fake_repo() {
  local tmp="$(mktemp -d)"
  git -C "$tmp" init -q -b main
  git -C "$tmp" config user.email "test@test"
  git -C "$tmp" config user.name "test"
  mkdir -p "$tmp/requirements/active" "$tmp/requirements/closed"
  # 至少要一个 commit 才能 for-each-ref
  echo "init" > "$tmp/README.md"
  git -C "$tmp" add . >/dev/null
  git -C "$tmp" commit -q -m "init"
  echo "$tmp"
}

_add_closed_req() {
  local repo="$1" num="$2" slug="${3:-test}"
  mkdir -p "$repo/requirements/closed/req-${num}-${slug}"
}

_add_active_req() {
  local repo="$1" num="$2" slug="${3:-test}"
  mkdir -p "$repo/requirements/active/req-${num}-${slug}"
}

_add_branch_req() {
  local repo="$1" num="$2" slug="${3:-test}"
  git -C "$repo" branch "req-${num}-${slug}" main 2>/dev/null
}

# -----------------------------------------------------------------
# Scenario 1: 空仓
# -----------------------------------------------------------------
test_empty_repo() {
  start_test "空仓 → next=001, first 退出 0（true）"
  local repo
  repo=$(_make_fake_repo)

  local next
  next=$(bash "$RESOLVER" next "$repo")
  assert_equal "001" "$next" "next on empty repo" || { rm -rf "$repo"; return; }

  bash "$RESOLVER" first "$repo"
  local first_rc=$?
  assert_equal "0" "$first_rc" "first on empty repo (0=true)" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 2: 只有 closed
# -----------------------------------------------------------------
test_only_closed() {
  start_test "只 closed/req-002, req-005 → next=006, first=false"
  local repo
  repo=$(_make_fake_repo)
  _add_closed_req "$repo" "002"
  _add_closed_req "$repo" "005"

  local next
  next=$(bash "$RESOLVER" next "$repo")
  assert_equal "006" "$next" "next with closed only" || { rm -rf "$repo"; return; }

  bash "$RESOLVER" first "$repo"
  local first_rc=$?
  assert_equal "1" "$first_rc" "first=false when closed exists" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 3: 只有 active
# -----------------------------------------------------------------
test_only_active() {
  start_test "只 active/req-003 → next=004, first=false"
  local repo
  repo=$(_make_fake_repo)
  _add_active_req "$repo" "003"

  local next
  next=$(bash "$RESOLVER" next "$repo")
  assert_equal "004" "$next" "next with active only" || { rm -rf "$repo"; return; }

  bash "$RESOLVER" first "$repo"
  local first_rc=$?
  assert_equal "1" "$first_rc" "first=false when active exists" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 4: 只有 git 分支（main 视角下 active/closed 都空，但 active req 占了号）
# 这是 v3.5 重点修复场景：之前光扫目录会漏号导致撞号
# -----------------------------------------------------------------
test_only_branch() {
  start_test "只 git 分支 req-007-foo（目录都空）→ next=008, first=false"
  local repo
  repo=$(_make_fake_repo)
  _add_branch_req "$repo" "007" "foo"

  local next
  next=$(bash "$RESOLVER" next "$repo")
  assert_equal "008" "$next" "next with branch only (key v3.5 case)" || { rm -rf "$repo"; return; }

  bash "$RESOLVER" first "$repo"
  local first_rc=$?
  assert_equal "1" "$first_rc" "first=false when branch exists (no dir)" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 5: 三来源混合，取 max
# -----------------------------------------------------------------
test_mixed() {
  start_test "closed=001/002, active=003, branch=req-005 → next=006"
  local repo
  repo=$(_make_fake_repo)
  _add_closed_req "$repo" "001"
  _add_closed_req "$repo" "002"
  _add_active_req "$repo" "003"
  _add_branch_req "$repo" "005" "live"

  local next
  next=$(bash "$RESOLVER" next "$repo")
  assert_equal "006" "$next" "next with mixed sources" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 6: list 子命令去重 + 排序
# -----------------------------------------------------------------
test_list_dedup_sort() {
  start_test "list 子命令：三来源同号去重，输出升序"
  local repo
  repo=$(_make_fake_repo)
  _add_closed_req "$repo" "002"
  _add_active_req "$repo" "002"  # 同号，应去重
  _add_branch_req "$repo" "001" "early"
  _add_branch_req "$repo" "010" "late"

  local list
  list=$(bash "$RESOLVER" list "$repo")
  local expected="001
002
010"
  assert_equal "$expected" "$list" "list dedup + sort" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 7: source 模式（不直接调 CLI）
# -----------------------------------------------------------------
test_source_mode() {
  start_test "source 模式：next_req_num / is_first_req / list_req_nums 函数"
  local repo
  repo=$(_make_fake_repo)
  _add_closed_req "$repo" "004"

  source "$RESOLVER"

  local n; n=$(next_req_num "$repo")
  assert_equal "005" "$n" "next_req_num function" || { rm -rf "$repo"; return; }

  if is_first_req "$repo"; then
    _fail "is_first_req should return 1 (false) when closed exists"
    rm -rf "$repo"; return
  fi

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 8: SKILL.md 仍然引用 helper（防止下次拆 references 时删丢）
# -----------------------------------------------------------------
test_skill_invokes_helper() {
  start_test "skills/new-req/SKILL.md 引用 req-num-resolver.sh helper"
  local skill="$REPO_ROOT/skills/new-req/SKILL.md"
  assert_file_contains "$skill" "req-num-resolver.sh" || return
  assert_file_contains "$skill" "next" || return  # CLI subcommand
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_empty_repo
test_only_closed
test_only_active
test_only_branch
test_mixed
test_list_dedup_sort
test_source_mode
test_skill_invokes_helper

report_results "req-num-resolver"
