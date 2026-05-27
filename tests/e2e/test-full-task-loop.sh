#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TEST_ROOT/helpers/assert.sh"
source "$TEST_ROOT/helpers/fixture.sh"

TASK_PLAN_SKILL="$FRAMEWORK_ROOT/skills/task-plan/SKILL.md"
TASK_SPEC_SKILL="$FRAMEWORK_ROOT/skills/task-spec/SKILL.md"
DOC_UPDATE_SKILL="$FRAMEWORK_ROOT/skills/doc-update/SKILL.md"
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
  return 1
}

_make_loop_fixture() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/pmailoop.XXXXXX")
  mkdir -p "$dir/tasks" "$dir/docs/modules"

  cat > "$dir/task-plan.md" <<'EOF'
| id | title | 所属模块 | 所属模块章节 | summary | order | risk |
|----|-------|----------|--------------|---------|-------|------|
| task-001 | 登录主流程 | 账号模块 | 登录与会话 | 用户登录并看到错误反馈 | 1 | 无 |

## 变更记录
- （暂无）
EOF

  cat > "$dir/tasks/task-001-login.md" <<'EOF'
# Task 001: 登录主流程

**所属模块：** 账号模块
**所属模块章节：** 登录与会话
**状态：** 已完成

## 功能清单

### 1 · 登录表单

| 二级功能 | 三级功能 | 使用角色 | 需求描述 |
|---------|---------|---------|---------|
| 登录 | 登录表单 | 普通用户 | 1. 用户输入邮箱和密码后可以提交登录。 |
EOF

  cat > "$dir/docs/modules/account.md" <<'EOF'
# 账号模块

## 三、功能清单（硬约束）

### 登录与会话
EOF

  echo "$dir"
}

test_task_spec_reads_task_plan_contract() {
  start_test "e2e contract: /pmai-task-spec reads task-plan.md"

  _assert_contains "$TASK_SPEC_SKILL" '读 `$ACTIVE_REQ_DIR/task-plan.md` 的 task id 列表' "task-spec reads plan ids" || return
  _assert_contains "$TASK_SPEC_SKILL" '从 `task-plan.md` 定位参数指定的 `<task-id>`' "task-spec locates requested id" || return
  # delta-3：从一行 task 生成单文件 typed contract（不再产 .engineering.md）
  _assert_contains "$TASK_SPEC_SKILL" '用于从 `task-plan.md` 中的单行 task 生成完整的 `tasks/task-NNN-<slug>.md`' "task-spec generates single-file contract" || return
  _assert_contains "$TASK_SPEC_SKILL" "不再产 \`.engineering.md\`" "task-spec drops engineering contract file" || return

  pass_test
}

test_doc_update_four_situations_with_mock_fixture() {
  start_test "e2e contract: doc-update handles 4 situations against mock task/module"

  local fake
  fake=$(_make_loop_fixture)

  if ! grep -F -q "### 1 · 登录表单" "$fake/tasks/task-001-login.md"; then
    _fail "mock task feature missing"
    rm -rf "$fake"
    return
  fi
  if grep -F -q "#### 1 · 登录表单" "$fake/docs/modules/account.md"; then
    _fail "mock module should start without feature, representing ADD"
    rm -rf "$fake"
    return
  fi

  _assert_contains "$DOC_UPDATE_SKILL" "Item in task list but NOT in module spec" "ADD contract" || { rm -rf "$fake"; return; }
  _assert_contains "$DOC_UPDATE_SKILL" "Content identical" "SKIP contract" || { rm -rf "$fake"; return; }
  _assert_contains "$DOC_UPDATE_SKILL" "Content different" "MODIFY contract" || { rm -rf "$fake"; return; }
  _assert_contains "$DOC_UPDATE_SKILL" "Item in module spec but NOT in task list" "LEAVE contract" || { rm -rf "$fake"; return; }
  _assert_contains "$DOC_UPDATE_SKILL" "ADD/SKIP/LEAVE UNCHANGED 不打断 PM；只有 MODIFY 进位置清单审核门" "PM interaction contract" || { rm -rf "$fake"; return; }

  rm -rf "$fake"
  pass_test
}

test_end_to_end_flow_description_complete() {
  start_test "e2e contract: Stage 5/6 flow description is complete"

  _assert_contains "$TASK_PLAN_SKILL" '不生成具体 task 文档' "stage 5 only plan, not task docs" || return
  _assert_contains "$TASK_PLAN_SKILL" '具体 task 文档由 stage 6 的 `/pmai-task-spec <task-id>`' "stage 6 task-spec handoff" || return
  _assert_contains "$TASK_SPEC_SKILL" "一次只生成一个 task 的**一个文件**" "one task at a time (single-file typed contract)" || return
  _assert_contains "$DOC_UPDATE_SKILL" '沉淀模式由 `/pmai-close-task` 在 task acceptance 后调用' "close-task calls settlement" || return
  _assert_contains "$DOC_UPDATE_SKILL" '允许继续运行 `close-task.sh` 的后续 merge / cleanup' "close-task continues after doc-update" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "task branch has been merged to req branch" "gate checks merge" || return
  _assert_contains "$REQ_STAGE_GATE_SKILL" "task worktree has been cleaned up" "gate checks cleanup" || return

  pass_test
}

test_task_spec_reads_task_plan_contract
test_doc_update_four_situations_with_mock_fixture
test_end_to_end_flow_description_complete

report_results "e2e-full-task-loop"
