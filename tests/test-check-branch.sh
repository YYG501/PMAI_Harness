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

test_main_allows_codex_hooks() {
  start_test "I-CB3 main allows .codex/hooks.json (whitelisted host config)"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p .codex
  capture_check "Write" ".codex/hooks.json" "" "" "{}"
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow .codex/hooks.json on main (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_allows_opencode_config() {
  start_test "I-CB3 main allows OpenCode host config"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p .opencode/commands
  capture_check "Write" ".opencode/commands/pmai-build.md" "" "" "route"
  local rc1="$RC" out1="$OUT"
  capture_check "Write" "opencode.json" "" "" "{}"
  if [ "$rc1" = "0" ] && ! echo "$out1" | grep -q '"deny"' \
     && [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow OpenCode host config on main (command rc=$rc1 out=$out1; json rc=$RC out=$OUT)"
  fi
  fixture_teardown
}


test_main_allows_module_meta_create() {
  # 批 2：真相源迁 docs/modules/*；旧 requirements/active 白名单已删。模块 .work-meta.json
  # 在 main 上首建（/pmai-design 开工）放行——走 docs/* 全放行；stage 字段直改仍由 GATE2 拦。
  start_test "I-CB3 (批2) main allows docs/modules/<模块>/.work-meta.json create（非 stage 直改）"
  fixture_setup
  cd "$FIXTURE_DIR"
  mkdir -p docs/modules/能力匹配卡
  capture_check "Write" "docs/modules/能力匹配卡/.work-meta.json" "" "" '{"id":"work-001","name":"能力匹配卡","stage":1,"status":"active"}'
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow module .work-meta.json create on main (rc=$RC, out=$OUT)"
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

# ---------------------------------------------------------------
# I-CB5: build worktree 可直接写 prototype/
# ---------------------------------------------------------------

test_build_branch_allows_prototype_write() {
  start_test "I-CB5 build branch ALLOWS write to prototype/index.ts"
  fixture_setup
  work_dir=$(fixture_create_work "work-001" "test" 3)

  cd "$FIXTURE_DIR/.worktrees/build-work-001-test"
  mkdir -p prototype
  capture_check "Write" "prototype/index.ts" "" "" "console.log(1)"
  # build worktree 放行 prototype/，跨界交执行器层。
  if [ "$RC" = "2" ] && echo "$OUT" | grep -q '"deny"'; then
    _fail "build branch should ALLOW prototype/ writes (rc=$RC, out=$OUT)"
  else
    pass_test
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
# GATE3 沉淀分档：mockups/ + decisions/ + docs/** 可写 main；业务代码仍走 worktree
# ---------------------------------------------------------------

test_main_allows_mockups_write() {
  start_test "GATE3 main ALLOWS mockups/ write (探索草稿豁免)"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "mockups/manifest.json" "" "" '{"variants":[]}'
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow mockups/ on main unconditionally (rc=$RC, out=$OUT)"
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

test_main_allows_pm_workflow_audits_write() {
  start_test "GATE3 main ALLOWS .pm-workflow/audits/ write (内部审计记录)"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" ".pm-workflow/audits/demo/coverage.json" "" "" '{"items":[]}'
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "should allow .pm-workflow/audits/ on main (rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

# 批1（lifecycle 迁移）：docs/** 全放行 main 直接写。
# 原 test_main_rejects_product_state_without_marker（无 marker 拒绝）翻成放行。

test_main_allows_product_state_no_marker() {
  start_test "GATE3 main ALLOWS root PRODUCT-STATE write WITHOUT marker"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "PRODUCT-STATE.md" "old" "new" ""
  if [ "$RC" = "0" ] && ! echo "$OUT" | grep -q '"deny"'; then
    pass_test
  else
    _fail "根目录 PRODUCT-STATE 应放行 main（无 marker）(rc=$RC, out=$OUT)"
  fi
  fixture_teardown
}

test_main_allows_product_rules_and_todo() {
  start_test "GATE3 main ALLOWS root PRODUCT-RULES.md + TODO.md"
  fixture_setup
  cd "$FIXTURE_DIR"
  capture_check "Write" "PRODUCT-RULES.md" "old" "new" ""
  local rc1="$RC" out1="$OUT"
  capture_check "Write" "TODO.md" "old" "new" ""
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

test_main_rejects_src_write
test_main_allows_claude_settings
test_main_allows_codex_hooks
test_main_allows_opencode_config
test_main_allows_module_meta_create
test_main_rejects_random_toplevel
test_build_branch_allows_prototype_write
test_outside_repo_non_tmp_denied
test_outside_repo_tmp_allowed
test_main_allows_mockups_write
test_main_allows_decisions_write
test_main_allows_pm_workflow_audits_write
test_main_allows_product_state_no_marker
test_main_allows_product_rules_and_todo
test_main_allows_docs_modules_triplet
test_main_still_rejects_prototype_code

report_results "check-branch"
