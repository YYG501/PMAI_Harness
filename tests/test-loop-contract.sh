#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$REPO_ROOT/skills/_shared/loop-contract.md"
FIXTURE="$REPO_ROOT/tests/fixtures/loop-contract-scenarios.json"

test_shared_protocol_is_single_and_non_persistent() {
  start_test "loop contract: one protocol without a second state machine"
  if [ ! -f "$CONTRACT" ]; then
    _fail "shared Loop Contract is missing"
  elif ! grep -q '每轮固定顺序' "$CONTRACT"; then
    _fail "shared contract must define the full loop order"
  elif ! grep -q '\*\*恢复\*\*' "$CONTRACT" \
    || ! grep -q '\*\*确认目标\*\*' "$CONTRACT" \
    || ! grep -q '\*\*确认边界\*\*' "$CONTRACT" \
    || ! grep -q '\*\*执行最小完整动作\*\*' "$CONTRACT" \
    || ! grep -q '\*\*验证实际结果\*\*' "$CONTRACT" \
    || ! grep -q '\*\*路由\*\*' "$CONTRACT"; then
    _fail "shared contract must define every loop step"
  elif ! grep -q 'lifecycle.*继续是唯一持久状态' "$CONTRACT" \
    || ! grep -q '不新增 `loop state`、task state、decision state' "$CONTRACT"; then
    _fail "Loop Contract must not create persistent state"
  elif find "$REPO_ROOT" -path "$REPO_ROOT/.tmp" -prune -o -type f \
      \( -name 'loop.json' -o -name 'loop-state.json' -o -name 'loop.yml' \) -print | grep -q .; then
    _fail "batch five must not add a parallel loop state file"
  else
    pass_test
  fi
}

test_primary_skills_map_to_the_shared_contract() {
  start_test "loop contract: Proposal, Design, Build, and recovery share one source"
  local file heading
  for pair in \
    "proposal:Proposal Loop Mapping" \
    "design:Design Loop Mapping" \
    "build:Build Loop Mapping"; do
    file="${pair%%:*}"
    heading="${pair#*:}"
    if ! grep -q 'skills/_shared/loop-contract.md' "$REPO_ROOT/skills/$file/SKILL.md" \
      || ! grep -q "$heading" "$REPO_ROOT/skills/$file/SKILL.md"; then
      _fail "$file must read and map to the shared Loop Contract"
      return
    fi
  done
  if ! grep -q 'skills/_shared/loop-contract.md' "$REPO_ROOT/skills/build-close/SKILL.md" \
    || ! grep -q 'resume_checkpoint' "$REPO_ROOT/skills/build-close/SKILL.md"; then
    _fail "build-close must remain a recovery mapping of the same contract"
  else
    pass_test
  fi
}

test_fixed_scenarios_match_the_canonical_table() {
  start_test "loop contract: fixed consumer scenarios match the canonical route table"
  if python3 - "$CONTRACT" "$FIXTURE" <<'PY'
import json
import sys
from pathlib import Path

contract = Path(sys.argv[1]).read_text(encoding="utf-8")
payload = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
assert payload.get("schema_version") == 1
scenarios = payload.get("scenarios")
assert isinstance(scenarios, list) and scenarios

rows = {}
for line in contract.splitlines():
    if not line.startswith("| SCN-"):
        continue
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    assert len(cells) == 6, cells
    rows[cells[0]] = {
        "id": cells[0],
        "phase": cells[1],
        "trigger": cells[2],
        "action": cells[3],
        "destination": cells[4],
        "checkpoint": cells[5],
    }

expected = {item["id"]: item for item in scenarios}
assert len(expected) == len(scenarios), "duplicate scenario id"
assert rows == expected, {"missing": sorted(expected.keys() - rows.keys()), "extra": sorted(rows.keys() - expected.keys())}
assert {item["phase"] for item in scenarios} == {"proposal", "design", "build", "recovery"}
assert {item["action"] for item in scenarios} == {
    "retry_current", "await_pm_decision", "route_proposal", "route_design",
    "advance", "resume_checkpoint", "complete",
}
PY
  then
    pass_test
  else
    _fail "fixed scenarios drifted from the shared contract"
  fi
}

test_route_priority_and_recovery_are_explicit() {
  start_test "loop contract: route priority preserves upstream and checkpoint semantics"
  if ! grep -q '产品方向高于模块设计' "$CONTRACT" \
    || ! grep -q '模块模型高于实现调整' "$CONTRACT" \
    || ! grep -q 'PM 最新反馈高于旧定稿意图' "$CONTRACT"; then
    _fail "cross-stage priority is incomplete"
  elif ! grep -q 'landing 已完成就不重复 merge' "$CONTRACT" \
    || ! grep -q 'Proposal 只读复核通过就不创建新版本' "$CONTRACT" \
    || ! grep -q 'ready_to_build.*不重写设计依据' "$CONTRACT" \
    || ! grep -q '同一 ready checkpoint.*复用既有授权' "$CONTRACT"; then
    _fail "recovery must not replay completed checkpoints"
  elif ! grep -q '不是 Session Eval' "$CONTRACT" \
    || ! grep -q '以后进入 Session Eval' "$CONTRACT"; then
    _fail "static contract checks must not claim session effectiveness"
  else
    pass_test
  fi
}

test_shared_protocol_is_single_and_non_persistent
test_primary_skills_map_to_the_shared_contract
test_fixed_scenarios_match_the_canonical_table
test_route_priority_and_recovery_are_explicit
report_results "loop-contract"
