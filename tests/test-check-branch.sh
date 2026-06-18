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

test_main_allows_module_meta_create() {
  # 批 2：真相源迁 docs/modules/*；旧 requirements/active 白名单已删。模块 .req-meta.json
  # 在 main 上首建（/design 开工）放行——走 docs/* 全放行；stage 字段直改仍由 GATE2 拦。
  start_test "I-CB3 (批2) main allows docs/modules/<模块>/.req-meta.json create（非 stage 直改）"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p docs/modules/能力匹配卡
  capture_check "Write" "docs/modules/能力匹配卡/.req-meta.json" "" "" '{"id":"req-001","name":"能力匹配卡","stage":1,"status":"active"}'
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow module .req-meta.json create on main (rc=$RC, out=$OUT)"
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
  start_test "I-CB1/CB2 (D10) abs path into req worktree prototype/ → allowed（跨 task 串台移交执行器 adapter_postcheck）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)
  task_file=$(fixture_create_task "$req_dir" "001" "impl" "执行中")
  task_wt=$(fixture_create_task_worktree "$task_file" "req-001-test")

  # 从 task worktree 里，用绝对路径指向 req worktree 下的 prototype/
  cd "$task_wt"
  mkdir -p "$FIXTURE_DIR/.worktrees/req-001-test/prototype" 2>/dev/null || true
  abs_target="$FIXTURE_DIR/.worktrees/req-001-test/prototype/edit.ts"

  capture_check "Write" "$abs_target" "" "" "x"
  # 六步 D10：req worktree 放行 prototype/（原 req-prototype 拦截已删）。跨 task 串台不再靠
  # check-branch，交执行器 adapter_postcheck（扫自身 worktree 超界文件 + rollback）+ 一 task 一执行器。
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    _fail "abs path into req prototype/ should be allowed after D10 (rc=$RC, out=$OUT)"
  else
    pass_test
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
# I-CB5 (D10): req 分支可直接写 prototype/（轻 / 文档 task 在 req worktree 改原型）
# ---------------------------------------------------------------

test_req_branch_allows_prototype_write() {
  start_test "I-CB5 (D10) req branch ALLOWS write to prototype/index.ts"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  cd "$FIXTURE_DIR/.worktrees/req-001-test"
  mkdir -p prototype
  capture_check "Write" "prototype/index.ts" "" "" "console.log(1)"
  # 六步 D10：原 req-prototype 拦截已删；req worktree 放行 prototype/，跨界交执行器层
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    _fail "req branch should ALLOW prototype/ writes after D10 (rc=$RC, out=$OUT)"
  else
    pass_test
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
  task_file=$(fixture_create_task "$req_dir" "001" "impl" "待执行")

  cd "$FIXTURE_DIR/.worktrees/req-001-test"
  # Edit: 把状态从 待执行 改成 执行中
  old='**状态：** 待执行'
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
  start_test "I-CB10 reject task worktree write when status=待执行"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "010" "gate" "待执行" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # Attempt to write a code file from inside the task worktree
  cd "$task_wt"
  capture_check "Write" "prototypes/sneak.ts" "" "" "console.log('leaked')"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q "I-CB10"; then
    pass_test
  else
    _fail "should deny code write when task status=待执行 (rc=$RC, out=$OUT)"
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
  task=$(fixture_create_task "$req_dir" "012" "gate-taskfile" "已完成" "/qa")
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

# ---------------------------------------------------------------
# GATE 3 沉淀分档：mocks/ + decisions/ 无条件可写 main；PRODUCT-STATE marker 门控
# ---------------------------------------------------------------

test_main_allows_mocks_write() {
  start_test "GATE3 main ALLOWS mocks/ write (探索草稿豁免)"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "mocks/manifest.json" "" "" '{"variants":[]}'
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow mocks/ on main unconditionally (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_allows_decisions_write() {
  start_test "GATE3 main ALLOWS docs/decisions/ write (冻结档豁免)"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "docs/decisions/2026-06-04-foo.md" "" "" "# 冻结档"
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow docs/decisions/ on main unconditionally (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# 批1（lifecycle 迁移）：docs/** 全放行 main 直接写、删 deposit marker 门控。
# 原 test_main_rejects_product_state_without_marker（无 marker 拒绝）翻成放行；
# 原 marker 在场放行 / marker blast radius 两例删除（marker 门控已删）。

test_main_allows_product_state_no_marker() {
  start_test "GATE3 (批1) main ALLOWS PRODUCT-STATE write WITHOUT marker (docs/** 全放行)"
  fixture_setup
  cd "$FIXTURE_DIR"
  rm -f .runs/deposit-in-progress 2>/dev/null || true
  capture_check "Write" "docs/PRODUCT-STATE.md" "old" "new" ""
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "批1 后 docs/PRODUCT-STATE 应放行 main（无 marker）(rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_allows_product_rules_and_todo() {
  start_test "GATE3 (批1) main ALLOWS docs/PRODUCT-RULES.md + docs/TODO.md (docs/** 全放行)"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "docs/PRODUCT-RULES.md" "old" "new" ""
  local rc1="$RC" out1="$OUT"
  capture_check "Write" "docs/TODO.md" "old" "new" ""
  if [ "$rc1" = "0" ] && ! echo "$out1" | grep -q '"deny"' \
     && [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "PRODUCT-RULES/TODO 应放行 main (rules rc=$rc1 out=$out1; todo rc=$RC out=$OUT)"
  fi
  fixture_teardown
}

test_main_allows_docs_modules_triplet() {
  start_test "GATE3 (批1) main ALLOWS docs/modules/<模块>/ 三件套写（含已 commit 后再改）"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p docs/modules/能力匹配卡
  # 先建并 commit，再改——验证旧「已 commit 后拒绝」的 git-log 门控已删
  capture_check "Write" "docs/modules/能力匹配卡/spec.md" "" "" "# spec v1"
  local rc1="$RC" out1="$OUT"
  echo "# spec v1" > docs/modules/能力匹配卡/spec.md
  git add -A && git commit -q -m "add module spec"
  capture_check "Write" "docs/modules/能力匹配卡/spec.md" "# spec v1" "# spec v2" ""
  if [ "$rc1" = "0" ] && ! echo "$out1" | grep -q '"deny"' \
     && [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "docs/modules 三件套应放行（含已 commit 后再改）(create rc=$rc1 out=$out1; reedit rc=$RC out=$OUT)"
  fi
  fixture_teardown
}

test_main_still_rejects_prototype_code() {
  start_test "GATE3 (批1) main 仍拒绝 prototype/ 代码（放宽只针对 docs/，业务代码走 worktree）"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p prototype
  capture_check "Write" "prototype/app.ts" "" "" "console.log(1)"
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "批1 main 仍应拒绝 prototype/ 代码 (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_still_rejects_stage_direct_edit() {
  # 批 2：补 GATE2 洞——真相源迁 docs/modules/<模块>/.req-meta.json 后，main 上 docs/** 虽全放行，
  # 但该文件的 stage 字段直改仍必须被 GATE2 拦（走 req-transition）。用新路径验证。
  start_test "GATE2 (批2) main 仍拒绝 docs/modules/<模块>/.req-meta.json 的 stage 直改（走 req-transition）"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p docs/modules/能力匹配卡
  cat > docs/modules/能力匹配卡/.req-meta.json <<'JSON'
{"id":"req-001","name":"能力匹配卡","stage":3,"status":"active"}
JSON
  git add -A && git commit -q -m "seed module meta"
  capture_check "Edit" "docs/modules/能力匹配卡/.req-meta.json" \
    '"stage": 3' '"stage": 4' ""
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"' && echo "$OUT" | grep -q "req-transition"; then
    pass_test
  else
    _fail "批2 main 仍应拒绝 docs/modules stage 直改 (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_rejects_src_write
test_main_allows_claude_settings
test_main_allows_module_meta_create
test_main_rejects_random_toplevel
test_abs_path_from_task_to_req_worktree_gate
test_abs_path_from_task_to_main_repo_gate
test_task_branch_rejects_docs_write
test_req_branch_allows_prototype_write
test_reject_direct_task_status_edit
test_reject_direct_req_stage_edit
test_outside_repo_non_tmp_denied
test_outside_repo_tmp_allowed
test_task_status_gate_rejects_when_pending
test_task_status_gate_allows_when_executing
test_task_status_gate_allows_task_file_edit
test_main_allows_mocks_write
test_main_allows_decisions_write
test_main_allows_product_state_no_marker
test_main_allows_product_rules_and_todo
test_main_allows_docs_modules_triplet
test_main_still_rejects_prototype_code
test_main_still_rejects_stage_direct_edit

report_results "check-branch"
