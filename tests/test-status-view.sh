#!/usr/bin/env bash
# Tests for status-view.py after task pipeline removal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"
source "$SCRIPT_DIR/helpers/active-build-fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_VIEW="$REPO_ROOT/scripts/status-view.py"
STATUS_SKILL="$REPO_ROOT/skills/status/SKILL.md"

render_pending_handoff_view() {
  local view="$1" handoffs_json="$2"
  python3 - "$STATUS_VIEW" "$REPO_ROOT" "$view" "$handoffs_json" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

script, repo_root, view, handoffs_json = sys.argv[1:]
spec = importlib.util.spec_from_file_location("pmai_status_view", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module._pending_lark_resumables = lambda _root: ([], None)
module._pending_lark_handoffs = lambda _root: (json.loads(handoffs_json), None)
state = {"active_work": []}
if view == "narrative":
    module.render_narrative(state, Path(repo_root))
elif view == "status":
    module.render_status(state, Path(repo_root))
else:
    raise SystemExit(f"unknown view: {view}")
PY
}

test_summary_lists_active_work() {
  start_test "summary: lists active work by stage, no task wording"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --summary 2>&1)
  if echo "$out" | grep -q "active work" \
     && echo "$out" | grep -q "work-001" \
     && ! echo "$out" | grep -qi "task"; then
    pass_test
  else
    _fail "summary output unexpected: $out"
  fi
  fixture_teardown
}

test_status_suggests_build_not_task() {
  start_test "status: build stage suggests /pmai-build path, no /pmai-task command"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" 2>&1)
  if echo "$out" | grep -q "当前进度：build" \
     && echo "$out" | grep -q "/pmai-build" \
     && ! echo "$out" | grep -q "/pmai-task" \
     && ! echo "$out" | grep -q "Stage："; then
    pass_test
  else
    _fail "status output unexpected: $out"
  fi
  fixture_teardown
}

test_banner_only_renders_active_work() {
  start_test "banner-only: active work renders without task dependency"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out rc
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --banner-only --skill status 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "status" && echo "$out" | grep -q "build"; then
    pass_test
  else
    _fail "banner-only failed rc=$rc out=$out"
  fi
  fixture_teardown
}

test_timeline_has_no_task_counts() {
  start_test "timeline: no task counts"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --timeline 2>&1)
  if echo "$out" | grep -q "Active" && ! echo "$out" | grep -qi "task"; then
    pass_test
  else
    _fail "timeline output unexpected: $out"
  fi
  fixture_teardown
}

test_narrative_dirty_main_has_pm_action() {
  start_test "narrative: 无 active 但有未提交改动时先给 PM 收口动作"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/Sources"
  echo "print(\"dirty\")" > "$FIXTURE_DIR/Sources/Foo.swift"

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "当前状态：有一轮改动还没收口" \
     && echo "$out" | grep -q "建议下一步：先把这轮改动固定到独立分支或提交点" \
     && ! echo "$out" | grep -q "active work" \
     && ! echo "$out" | grep -q "PMAI 状态脚本"; then
    pass_test
  else
    _fail "dirty main narrative unexpected: $out"
  fi
  fixture_teardown
}

test_explicit_repo_alias_is_normalized_before_review_scan() {
  start_test "status: 显式只读仓根别名在飞书恢复扫描前规范化"
  fixture_setup
  local alias_path out rc
  alias_path="${FIXTURE_DIR}-alias"
  ln -s "$FIXTURE_DIR" "$alias_path"

  out=$(python3 "$STATUS_VIEW" "$alias_path" --narrative 2>&1)
  rc=$?
  rm -f "$alias_path"
  if [ "$rc" -eq 0 ] \
     && echo "$out" | grep -q "当前状态：没有进行中的工作" \
     && ! echo "$out" | grep -q "未完成批次无法安全读取"; then
    pass_test
  else
    _fail "explicit repo alias should remain a read-only status input: rc=$rc out=$out"
  fi
  fixture_teardown
}

test_narrative_new_project_routes_to_proposal() {
  start_test "narrative: newly initialized project routes to Product Proposal"
  fixture_setup
  printf '# Product\n\n<!-- PMAI_PROPOSAL_REQUIRED -->\n' > "$FIXTURE_DIR/PRODUCT.md"
  git -C "$FIXTURE_DIR" add -- PRODUCT.md
  git -C "$FIXTURE_DIR" commit -q -m "mark proposal required"

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "建议下一步：发 /pmai-proposal" \
     && ! echo "$out" | grep -q "建议下一步：发 /pmai-design"; then
    pass_test
  else
    _fail "new project should route to Proposal: $out"
  fi
  fixture_teardown
}

test_narrative_product_handoff_routes_to_proposal() {
  start_test "narrative: 飞书产品评审交接优先返回 Proposal"
  local out
  out=$(render_pending_handoff_view narrative \
    '[{"route":"proposal","phase":"proposal","module":"docs/modules/orders"}]')
  if echo "$out" | grep -q "/pmai-proposal" \
     && ! echo "$out" | grep -q "/pmai-design"; then
    pass_test
  else
    _fail "product handoff should route to Proposal: $out"
  fi
}

test_narrative_module_handoff_routes_to_exact_design() {
  start_test "narrative: 飞书模块评审交接返回对应 design"
  local out
  out=$(render_pending_handoff_view narrative \
    '[{"route":"proposal","phase":"design","module":"docs/modules/orders"}]')
  if echo "$out" | grep -q '/pmai-design "orders"' \
     && ! echo "$out" | grep -q "/pmai-proposal"; then
    pass_test
  else
    _fail "module handoff should route to exact design: $out"
  fi
}

test_default_multiple_module_handoffs_are_individually_actionable() {
  start_test "status: 多个模块级交接输出逐条可执行的 design 动作"
  local out command_count
  out=$(render_pending_handoff_view status \
    '[{"route":"design","phase":"design","module":"docs/modules/orders"},{"route":"design","phase":"design","module":"docs/modules/billing"}]')
  command_count=$(echo "$out" | grep -c '^- 发 /pmai-design ' || true)
  if [ "$command_count" = "2" ] \
     && echo "$out" | grep -q -- '- 发 /pmai-design "billing"' \
     && echo "$out" | grep -q -- '- 发 /pmai-design "orders"'; then
    pass_test
  else
    _fail "module handoffs should render separate executable design commands: $out"
  fi
}

test_default_mixed_handoffs_prioritize_proposal() {
  start_test "status: 产品级与模块级交接并存时 Proposal 优先"
  local out
  out=$(render_pending_handoff_view status \
    '[{"route":"design","phase":"design","module":"docs/modules/orders"},{"route":"proposal","phase":"proposal","module":"docs/modules/billing"}]')
  if echo "$out" | grep -q "/pmai-proposal" \
     && ! echo "$out" | grep -q "/pmai-design"; then
    pass_test
  else
    _fail "mixed handoffs should prioritize Proposal: $out"
  fi
}

test_handoff_lark_review_phase_routes_back_to_review() {
  start_test "status: handoff 已完成上游规格时只恢复飞书评审"
  local out
  out=$(render_pending_handoff_view status \
    '[{"route":"proposal","phase":"lark_review","module":"docs/modules/orders"}]')
  if echo "$out" | grep -q "/pmai-lark-review" \
     && ! echo "$out" | grep -q "/pmai-proposal" \
     && ! echo "$out" | grep -q "/pmai-design"; then
    pass_test
  else
    _fail "lark_review phase should route only to review: $out"
  fi
}

test_resumable_review_precedes_active_work() {
  start_test "status: 普通未完成飞书批次优先于 active work"
  local out
  out=$(python3 - "$STATUS_VIEW" "$REPO_ROOT" <<'PY'
import importlib.util
import sys
from pathlib import Path

script, repo_root = sys.argv[1:]
spec = importlib.util.spec_from_file_location("pmai_status_resumable_test", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module._pending_lark_resumables = lambda _root: ([{
    "markdown_relative": "docs/modules/orders/spec.md",
}], None)
module._pending_lark_handoffs = lambda _root: ([], None)
module.render_status({"active_work": [{"meta": {"id": "work-orders", "name": "orders"}}]}, Path(repo_root))
PY
  )
  if echo "$out" | grep -q '/pmai-lark-review "docs/modules/orders/spec.md"' \
     && ! echo "$out" | grep -q "当前工作"; then
    pass_test
  else
    _fail "resumable review should take status priority: $out"
  fi
}

test_narrative_multiple_active_work_pm_view() {
  start_test "narrative: 多个进行中工作按 PM 视图列状态和下一步"
  fixture_setup
  fixture_create_work "work-001" "import" 2 >/dev/null
  fixture_create_work "work-002" "bubble" 1 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "当前状态：有 2 个进行中的工作" \
     && echo "$out" | grep -q "进行中的工作：" \
     && echo "$out" | grep -q "1. import" \
     && echo "$out" | grep -q "2. bubble" \
     && echo "$out" | grep -q "下一步：" \
     && ! echo "$out" | grep -q "active work" \
     && ! echo "$out" | grep -q "Worktree"; then
    pass_test
  else
    _fail "multiple active narrative unexpected: $out"
  fi
  fixture_teardown
}

test_default_multi_work_hides_worktree_instructions() {
  start_test "status: 多工作默认视图不暴露 worktree 和 cd 指令"
  fixture_setup
  fixture_create_work "work-001" "import" 2 >/dev/null
  fixture_create_work "work-002" "bubble" 1 >/dev/null
  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" 2>&1)
  if echo "$out" | grep -q "当前工作" \
     && ! echo "$out" | grep -q "Worktree" \
     && ! echo "$out" | grep -q "cd 进" \
     && echo "$out" | grep -q "直接说模块名"; then
    pass_test
  else
    _fail "default multi-work status leaked infrastructure: $out"
  fi
  fixture_teardown
}

test_landed_docs_failure_resumes_without_merge() {
  start_test "status: landed/docs failed 提示只恢复文档、不重复合并"
  fixture_setup
  local work_dir
  work_dir=$(fixture_create_work "work-001" "import" 4)
  python3 - "$work_dir/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
meta = json.load(open(path))
meta["lifecycle_state"] = "landed"
meta["build"].update({"contract_version": 2, "lifecycle_state": "landed", "docs_status": "failed"})
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "从上次失败处继续正式文档更新" \
     && echo "$out" | grep -q "不重复合并"; then
    pass_test
  else
    _fail "docs recovery guidance mismatch: $out"
  fi
  fixture_teardown
}

test_status_skill_blocks_internal_diagnostics() {
  start_test "status skill: 禁止把内部诊断当 PM 现状汇报"

  assert_file_contains "$STATUS_SKILL" "当前状态：有 <N> 个进行中的工作" "status skill should define multi-work PM output" || return
  assert_file_contains "$STATUS_SKILL" "禁止输出“PMAI 状态脚本显示”" "status skill should ban script-diagnostic phrasing" || return
  assert_file_contains "$STATUS_SKILL" "有未提交改动就说“有一轮改动还没收口”" "status skill should collapse dirty-state conflict into PM action" || return
  assert_file_contains "$STATUS_SKILL" '统一交给 `/pmai-doctor`' "status skill should route health checks to doctor" || return
  pass_test
}

test_status_view_has_no_execution_context_mode() {
  start_test "status: 不再承载 build execution context"
  local out rc
  out=$(python3 "$STATUS_VIEW" --execution-context 2>&1)
  rc=$?
  if [ "$rc" = "2" ] \
     && echo "$out" | grep -q "unrecognized arguments" \
     && ! grep -q -- "--execution-context" "$STATUS_VIEW"; then
    pass_test
  else
    _fail "status-view should reject the removed execution mode: rc=$rc out=$out"
  fi
}

test_status_reports_stale_active_build_as_product_route() {
  start_test "status: 建造依据变化时仍给出产品流程下一步"
  active_build_fixture_setup prototype iterating
  printf '\n跨模块产品规则在 build 开始后发生变化。\n' >> "$ACTIVE_BUILD_FIXTURE/PRODUCT-RULES.md"

  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "建造依据有变化，需要重新确认后才能继续" \
     && echo "$out" | grep -q "继续 /pmai-design，重新核对变化" \
     && ! echo "$out" | grep -q "项目体检"; then
    pass_test
  else
    _fail "stale active build should remain visible as a product route: $out"
  fi
  active_build_fixture_teardown
}

test_summary_lists_active_work
test_status_suggests_build_not_task
test_banner_only_renders_active_work
test_timeline_has_no_task_counts
test_narrative_dirty_main_has_pm_action
test_explicit_repo_alias_is_normalized_before_review_scan
test_narrative_new_project_routes_to_proposal
test_narrative_product_handoff_routes_to_proposal
test_narrative_module_handoff_routes_to_exact_design
test_default_multiple_module_handoffs_are_individually_actionable
test_default_mixed_handoffs_prioritize_proposal
test_handoff_lark_review_phase_routes_back_to_review
test_resumable_review_precedes_active_work
test_narrative_multiple_active_work_pm_view
test_default_multi_work_hides_worktree_instructions
test_landed_docs_failure_resumes_without_merge
test_status_skill_blocks_internal_diagnostics
test_status_view_has_no_execution_context_mode
test_status_reports_stale_active_build_as_product_route
report_results "status-view"
