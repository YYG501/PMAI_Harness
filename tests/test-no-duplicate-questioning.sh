#!/usr/bin/env bash
# 验证已有项目等价产品基线核验保持单一职责，不回流旧 direction 问卷。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_FILE="$REPO_ROOT/skills/_shared/project-questioning.md"
CODEBASE_AUDIT="$REPO_ROOT/skills/_internal/codebase-audit/SKILL.md"
INIT_PROJECT="$REPO_ROOT/skills/init-project/SKILL.md"

test_init_owns_both_internal_callers_and_no_retired_route() {
  start_test "T1: init 的资料与代码分支共用基线核验且无 direction 死路"
  if [ ! -f "$SHARED_FILE" ]; then
    _fail "_shared/project-questioning.md 不存在"
    return
  fi
  if ! grep -q '调用方.*资料目录分支.*codebase-audit step 4' "$SHARED_FILE" \
     || ! grep -q '_shared/project-questioning.md' "$INIT_PROJECT" \
     || grep -qE '/pmai-direction|skills/direction|direction skill' "$SHARED_FILE" "$CODEBASE_AUDIT" "$INIT_PROJECT"; then
    _fail "等价产品基线核验的调用边界不正确"
    return
  fi
  pass_test
}

test_complete_baseline_criteria_present() {
  start_test "T2: 等价产品基线覆盖六项判断和显式确认依据"
  local term
  for term in '产品定位' '主用户' '核心问题与价值' '产品边界' 'MVP 或当前产品结果' '当前有效性'; do
    if ! grep -q "$term" "$SHARED_FILE"; then
      _fail "等价产品基线缺判断项: $term"
      return
    fi
  done
  for term in '接入前已有等价产品基线' '主要依据' '真实存在的仓内相对路径' 'PM 确认日期' 'proposal-contract.py' 'equivalent_baseline'; do
    if ! grep -q "$term" "$SHARED_FILE" "$CODEBASE_AUDIT"; then
      _fail "等价产品基线缺显式确认合同: $term"
      return
    fi
  done
  pass_test
}

test_old_questionnaire_gates_are_removed() {
  start_test "T3: 不再用完整问卷和旧临时闸门补方向"
  if grep -qE 'check-project-sections\.py|check-open-questions\.py|\.project-solution-open-questions\.md|这个项目要解决什么核心问题' "$SHARED_FILE"; then
    _fail "project-questioning 仍保留旧方向问卷或补齐闸门"
    return
  fi
  if ! grep -q '不要用一套新问题把缺失项补齐' "$SHARED_FILE"; then
    _fail "project-questioning 应明确禁止在接入流程补问产品方向"
    return
  fi
  pass_test
}

test_gaps_route_to_proposal() {
  start_test "T4: 产品缺口转 Proposal，模块与已确认事实分流明确"
  for command in /pmai-proposal /pmai-design /pmai-record; do
    if ! grep -q "$command" "$SHARED_FILE"; then
      _fail "project-questioning 缺路由: $command"
      return
    fi
  done
  if ! grep -q 'PMAI_PROPOSAL_REQUIRED' "$SHARED_FILE"; then
    _fail "project-questioning 缺 Proposal required marker 处理"
    return
  fi
  pass_test
}

test_init_owns_both_internal_callers_and_no_retired_route
test_complete_baseline_criteria_present
test_old_questionnaire_gates_are_removed
test_gaps_route_to_proposal

report_results "no-duplicate-questioning"
