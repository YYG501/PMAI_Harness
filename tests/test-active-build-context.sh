#!/usr/bin/env bash
# Tests for the read-only active build resume context.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/active-build-fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIVE_BUILD_CONTEXT="$REPO_ROOT/scripts/active-build-context.py"
CONTEXT_PACK="$REPO_ROOT/scripts/context-pack.py"

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

test_execution_context_reuses_prototype_contract() {
  start_test "active build context: canonical lifecycle 输出 prototype 合同"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
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
  start_test "active build context: product 保持 production implementation"
  active_build_fixture_setup product final_check
  prepare_active_build_currentness
  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
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
  start_test "active build context: delivery policy 漂移时失败关闭"
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
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
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
  start_test "active build context: 多个 active build 返回歧义"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  active_build_fixture_add_second
  local out
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
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
  start_test "active build context: legacy v2 从 project type 派生保守恢复策略"
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
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
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

test_execution_context_fails_closed_on_authority_drift() {
  start_test "active build context: 建造依据变化时失败关闭"
  active_build_fixture_setup prototype iterating
  prepare_active_build_currentness
  printf '\n跨模块产品规则在 build 开始后发生变化。\n' >> "$ACTIVE_BUILD_FIXTURE/PRODUCT-RULES.md"

  local out rc
  out=$(cd "$ACTIVE_BUILD_FIXTURE" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
  rc=$?
  if [ "$rc" = "2" ] \
     && echo "$out" | grep -q '"status": "invalid"' \
     && echo "$out" | grep -q "设计依据在批准后发生变化"; then
    pass_test
  else
    _fail "authority drift should fail closed rc=$rc out=$out"
  fi
  active_build_fixture_teardown
}

test_execution_context_reuses_prototype_contract
test_execution_context_keeps_product_depth
test_execution_context_fails_closed_on_policy_drift
test_execution_context_does_not_guess_multiple_builds
test_execution_context_supports_legacy_v2_recovery
test_execution_context_fails_closed_on_authority_drift

report_results "active-build-context"
