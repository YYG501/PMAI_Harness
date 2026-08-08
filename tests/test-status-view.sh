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
  start_test "execution-context: build lifecycle 优先并输出 prototype 合同"
  active_build_fixture_setup prototype iterating
  python3 - "$ACTIVE_BUILD_FIXTURE/docs/modules/demo/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["lifecycle_state"] = "designing"
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
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

test_summary_lists_active_work
test_status_suggests_build_not_task
test_banner_only_renders_active_work
test_timeline_has_no_task_counts
test_narrative_dirty_main_has_pm_action
test_narrative_multiple_active_work_pm_view
test_default_multi_work_hides_worktree_instructions
test_landed_docs_failure_resumes_without_merge
test_status_skill_blocks_internal_diagnostics
test_execution_context_reuses_prototype_contract
test_execution_context_keeps_product_depth
test_execution_context_fails_closed_on_policy_drift
test_execution_context_does_not_guess_multiple_builds
test_execution_context_supports_legacy_v2_recovery

report_results "status-view"
