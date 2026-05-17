#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REQ_STAGE_GATE_SKILL="$FRAMEWORK_ROOT/skills/req-stage-gate/SKILL.md"

_contains() {
  local file="$1"
  local text="$2"
  grep -F -q -- "$text" "$file"
}

_assert_contains() {
  local file="$1"
  local text="$2"
  local desc="$3"
  if _contains "$file" "$text"; then
    return 0
  fi
  _fail "$desc: missing '$text'"
  sed -n '130,230p' "$file" >&2
  return 1
}

_make_fake_req_for_gate() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/pmaigate.XXXXXX")
  mkdir -p "$dir/tasks"

  cat > "$dir/task-plan.md" <<'EOF'
# Task Plan

| id | title | 所属模块 | summary |
|----|-------|----------|---------|
| task-001 | 登录 | 账号模块 | 登录主流程 |
| task-002 | 权限提示 | 权限模块 | 权限提示 |
| task-003 | 旧导出 | 报表模块 | 已删 |
| task-004 | API client | 基础设施 | 请求封装 |

## 变更记录

- 2026-04-25：删除 task-003，旧导出不再单独实现
EOF

  cat > "$dir/tasks/task-001-login.md" <<'EOF'
# Task 001: 登录

**状态：** 已完成
**分支：** task-001-login
**worktree：**

## 文档偏差
无偏差
EOF

  cat > "$dir/tasks/task-002-permission.md" <<'EOF'
# Task 002: 权限提示

**状态：** 已完成
**分支：** task-002-permission
**worktree：**

## 文档偏差
skip-doc-update reason marker: docs/modules/permission.md 暂时冲突，人工 cleanup TODO 未完成
EOF

  cat > "$dir/tasks/task-004-api-client.md" <<'EOF'
# Task 004: API client

**状态：** 执行中
**分支：** task-004-api-client
**worktree：** .worktrees/task-004-api-client

## 文档偏差
无偏差
EOF

  echo "$dir"
}

_extract_active_plan_ids() {
  local plan="$1"
  local all_ids deleted_ids id
  all_ids=$(awk '/^## 变更记录/{exit} {print}' "$plan" | grep -Eo 'task-[0-9]{3}' | sort -u)
  deleted_ids=$(awk 'found {print} /^## 变更记录/{found=1}' "$plan" | grep '删除' | grep -Eo 'task-[0-9]{3}' | sort -u)
  for id in $all_ids; do
    if ! echo "$deleted_ids" | grep -Fx -q "$id"; then
      echo "$id"
    fi
  done
}

_mock_gate_missing_report() {
  local req_dir="$1"
  local id file status
  for id in $(_extract_active_plan_ids "$req_dir/task-plan.md"); do
    file=$(find "$req_dir/tasks" -name "${id#task-}-*.md" -o -name "$id-*.md" | head -1)
    if [ -z "$file" ]; then
      echo "$id: missing task file"
      continue
    fi
    status=$(grep -E '^\*\*状态：\*\*' "$file" | sed 's/.*\*\*状态：\*\* *//')
    if [ "$status" != "已完成" ]; then
      echo "$id: status is $status"
    fi
    if grep -F -q "skip-doc-update reason marker" "$file"; then
      echo "$id: half-close detected"
    fi
    if grep -E '^\*\*worktree：\*\* *\.worktrees/' "$file" >/dev/null; then
      echo "$id: task worktree still exists"
    fi
  done
}

test_stage67_steps_replaced() {
  start_test "req-stage-gate stage 6→7 judgment steps are replaced"

  _assert_contains "$REQ_STAGE_GATE_SKILL" 'Read `task-plan.md`, extract task id list' "step 1 reads task-plan" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "For each id verify" "step 2 verify each id" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "All satisfied → 对话式确认门" "new confirmation gate (v3 dialog style)" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "Stage 6（task 执行）— 全部 task 已完成" "gate uses v3 stage marker" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "是否确认关闭此需求" "gate uses v3 close phrasing" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "Not satisfied → list which tasks are missing which steps" "missing output" || return

  pass_test
}

test_closed_task_verification_contract() {
  start_test "req-stage-gate verifies task file, status, branch merge, worktree cleanup"

  _assert_contains "$REQ_STAGE_GATE_SKILL" '`tasks/task-NNN-*.md` file exists' "task file exists check" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" 'task status is `「已完成」`' "status done check" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "task branch has been merged to req branch" "branch merged check" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "task worktree has been cleaned up" "worktree cleanup check" || return

  pass_test
}

test_change_log_exclusion_algorithm() {
  start_test "req-stage-gate excludes deleted ids from 变更记录"

  local fake ids
  fake=$(_make_fake_req_for_gate)
  ids=$(_extract_active_plan_ids "$fake/task-plan.md" | tr '\n' ' ')

  if [[ "$ids" != *"task-001"* ]] || [[ "$ids" != *"task-002"* ]] || [[ "$ids" != *"task-004"* ]]; then
    _fail "active ids missing expected task: $ids"
    rm -rf "$fake"
    return
  fi
  if [[ "$ids" == *"task-003"* ]]; then
    _fail "deleted task-003 should be excluded: $ids"
    rm -rf "$fake"
    return
  fi

  _assert_contains "$REQ_STAGE_GATE_SKILL" "变更记录 exclusion algorithm" "algorithm documented" || { rm -rf "$fake"; return; }
  _assert_contains "$REQ_STAGE_GATE_SKILL" '找到包含关键词 `删除` 的条目' "delete keyword documented" || { rm -rf "$fake"; return; }

  rm -rf "$fake"
  pass_test
}

# test_half_close_detection_behavior 已删（D13 final, 2026-05-16, polish-10/11）
# C2 half-close detection 在 req-stage-gate SKILL 已废弃（close-task vp-1 后永不写 marker）。
# 详见 docs/归档/完成/modulespec-维护/主方案.md §3 vp-2 + polish-11。

test_boundary_cases_and_output_format() {
  start_test "req-stage-gate boundary cases and missing-step output format"

  local fake report
  fake=$(_make_fake_req_for_gate)
  report=$(_mock_gate_missing_report "$fake")

  if ! echo "$report" | grep -F -q "task-004: status is 执行中"; then
    _fail "mock report should include unfinished infrastructure task"
    echo "$report" >&2
    rm -rf "$fake"
    return
  fi
  if ! echo "$report" | grep -F -q "task-004: task worktree still exists"; then
    _fail "mock report should include uncleared worktree"
    echo "$report" >&2
    rm -rf "$fake"
    return
  fi

  _assert_contains "$REQ_STAGE_GATE_SKILL" "task in task-plan.md but task file not yet generated" "task not generated boundary" || { rm -rf "$fake"; return; }
  _assert_contains "$REQ_STAGE_GATE_SKILL" "Infrastructure tasks → same close requirement" "infrastructure close boundary" || { rm -rf "$fake"; return; }
  _assert_contains "$REQ_STAGE_GATE_SKILL" "Stage 6 → 7 blocked: 以下 task 尚未完整关闭" "blocked output header" || { rm -rf "$fake"; return; }
  _assert_contains "$REQ_STAGE_GATE_SKILL" "missing task file" "missing file output" || { rm -rf "$fake"; return; }
  _assert_contains "$REQ_STAGE_GATE_SKILL" "task branch not merged to req branch" "missing branch output" || { rm -rf "$fake"; return; }

  rm -rf "$fake"
  pass_test
}

test_stage56_consistency() {
  start_test "req-stage-gate stage 5→6 no longer requires generated task files"

  _assert_contains "$REQ_STAGE_GATE_SKILL" '具体 task 文件由 stage 6 的 `/task-spec` 逐个生成' "stage 5 no task files" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" '检查 `task-plan.md` 包含 task 标题列表和 `## 变更记录` section' "stage 5 task-plan contract" || return

  pass_test
}

test_stage67_steps_replaced
test_closed_task_verification_contract
test_change_log_exclusion_algorithm
# test_half_close_detection_behavior 已删（D13 final polish-11，C2 detection 已废弃）
test_boundary_cases_and_output_format
test_stage56_consistency

report_results "req-stage-gate"
