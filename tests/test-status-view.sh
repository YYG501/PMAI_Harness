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
CONTEXT_PACK="$REPO_ROOT/scripts/context-pack.py"

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

prepare_active_build_currentness() {
  local module_dir="$ACTIVE_BUILD_FIXTURE/docs/modules/demo"
  local pack="$ACTIVE_BUILD_FIXTURE/.pm-workflow/context-current.json"
  mkdir -p "$ACTIVE_BUILD_FIXTURE/.pm-workflow"
  python3 "$CONTEXT_PACK" --repo-root "$ACTIVE_BUILD_FIXTURE" \
    --module "$module_dir" --output "$pack" >/dev/null
  python3 - "$module_dir/.work-meta.json" "$pack" <<'PY'
import json
import sys
from pathlib import Path

meta_path = Path(sys.argv[1])
pack = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
meta = json.loads(meta_path.read_text(encoding="utf-8"))
source_hash = pack["source_hash"]
meta["approved_source_hash"] = source_hash
meta["source_hash_version"] = pack["source_hash_version"]
meta["approved_target"] = {"paths": list(meta["build"]["target"]["paths"])}
meta["build"]["approved_source_hash"] = source_hash
meta["build"]["source_hash_version"] = pack["source_hash_version"]
meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
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
  pass_test
}

test_execution_context_reuses_prototype_contract() {
  start_test "execution-context: canonical lifecycle 输出 prototype 合同"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --execution-context 2>&1)
  if python3 -c '
import json, sys
data = json.load(sys.stdin)
work = data["active_builds"][0]
assert data["status"] == "active"
assert work["target"]["kind"] == "prototype"
assert work["delivery_policy"]["implementation_mode"] == "interactive-simulation"
assert work["approved_paths"] == ["src/index.ts"]
assert work["acceptance_lane"]["name"] == "iteration"
assert work["acceptance_lane"]["checks"] == ["typecheck"]
assert work["project"]["commands"]["build"] == "npm run build"
' <<<"$out"; then
    pass_test
  else
    _fail "prototype execution context mismatch: $out"
  fi
  active_build_fixture_teardown
}

test_execution_context_keeps_product_depth() {
  start_test "execution-context: product 保持 production implementation"
  active_build_fixture_setup product final_check
  prepare_active_build_currentness
  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --execution-context 2>&1)
  if python3 -c '
import json, sys
work = json.load(sys.stdin)["active_builds"][0]
assert work["delivery_policy"]["implementation_mode"] == "production-implementation"
assert work["acceptance_lane"]["name"] == "final"
assert "scope-coverage" in work["acceptance_lane"]["checks"]
' <<<"$out"; then
    pass_test
  else
    _fail "product execution context mismatch: $out"
  fi
  active_build_fixture_teardown
}

test_execution_context_fails_closed_on_policy_drift() {
  start_test "execution-context: delivery policy 漂移时失败关闭"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  python3 - "$ACTIVE_BUILD_FIXTURE/docs/modules/demo/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["build"]["delivery_policy"]["implementation_mode"] = "production-implementation"
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  local out rc
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --execution-context 2>&1)
  rc=$?
  if [ "$rc" = "2" ] \
     && echo "$out" | grep -q '"status": "invalid"' \
     && echo "$out" | grep -q "delivery_policy 与当前 target"; then
    pass_test
  else
    _fail "policy drift should fail closed rc=$rc out=$out"
  fi
  active_build_fixture_teardown
}

test_execution_context_does_not_guess_multiple_builds() {
  start_test "execution-context: 多个 active build 返回歧义"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  active_build_fixture_add_second
  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --execution-context 2>&1)
  if python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["status"] == "ambiguous"
assert len(data["active_builds"]) == 2
assert {item["name"] for item in data["active_builds"]} == {"demo", "second"}
' <<<"$out"; then
    pass_test
  else
    _fail "multiple builds should be ambiguous: $out"
  fi
  active_build_fixture_teardown
}

test_execution_context_supports_legacy_v2_recovery() {
  start_test "execution-context: legacy v2 从 project type 派生保守恢复策略"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  python3 - "$ACTIVE_BUILD_FIXTURE/docs/modules/demo/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
build = meta["build"]
build["contract_version"] = 2
build.pop("delivery_policy")
build.pop("delivery_policy_hash")
build["acceptance"] = {
    "required_checks": ["typecheck", "browser-smoke"],
    "evidence": [],
}
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --execution-context 2>&1)
  if python3 -c '
import json, sys
work = json.load(sys.stdin)["active_builds"][0]
assert work["contract_version"] == 2
assert work["delivery_policy_source"] == "legacy-v2-derived"
assert work["delivery_policy"]["implementation_mode"] == "interactive-simulation"
assert work["acceptance_lane"]["checks"] == []
' <<<"$out"; then
    pass_test
  else
    _fail "legacy v2 recovery context mismatch: $out"
  fi
  active_build_fixture_teardown
}

test_active_build_currentness_blocks_status_resume() {
  start_test "status: stale active build cannot be resumed"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  printf '\n跨模块产品规则在 build 开始后发生变化。\n' >> "$ACTIVE_BUILD_FIXTURE/PRODUCT-RULES.md"

  local execution narrative execution_rc
  execution=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --execution-context 2>&1)
  execution_rc=$?
  narrative=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if [ "$execution_rc" = "2" ] \
     && echo "$execution" | grep -q '"status": "invalid"' \
     && echo "$execution" | grep -q "设计依据在批准后发生变化" \
     && echo "$narrative" | grep -q "建造依据有变化，需要重新确认后才能继续" \
     && echo "$narrative" | grep -q "继续 /pmai-design，重新核对变化" \
     && ! echo "$narrative" | grep -q "继续看构建结果并直接说要改哪里"; then
    pass_test
  else
    _fail "stale active build should fail closed rc=$execution_rc execution=$execution narrative=$narrative"
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
test_execution_context_reuses_prototype_contract
test_execution_context_keeps_product_depth
test_execution_context_fails_closed_on_policy_drift
test_execution_context_does_not_guess_multiple_builds
test_execution_context_supports_legacy_v2_recovery
test_active_build_currentness_blocks_status_resume

report_results "status-view"
