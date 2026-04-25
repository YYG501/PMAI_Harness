#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

TASK_PLAN_SKILL="$FRAMEWORK_ROOT/skills/task-plan/SKILL.md"

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
  sed -n '1,240p' "$file" >&2
  return 1
}

_assert_missing() {
  local file="$1"
  local text="$2"
  local desc="$3"
  if _contains "$file" "$text"; then
    _fail "$desc: should not contain '$text'"
    return 1
  fi
  return 0
}

test_step3_opening_granularity() {
  start_test "task-plan step 3 opening: granularity and end-to-end slicing"

  _assert_contains "$TASK_PLAN_SKILL" "### 步骤 3：拆分 task" "step 3 heading" || return
  _assert_contains "$TASK_PLAN_SKILL" "颗粒度核心规则" "granularity core rule" || return
  _assert_contains "$TASK_PLAN_SKILL" "一个 task = PM 能在一次原型 demo 里完整验收的功能单元" "one demo validation unit" || return
  _assert_contains "$TASK_PLAN_SKILL" "业务模块 task" "business task granularity" || return
  _assert_contains "$TASK_PLAN_SKILL" "基础设施 task" "infrastructure task granularity" || return
  _assert_contains "$TASK_PLAN_SKILL" "端到端切片原则" "end-to-end slice principle" || return
  _assert_contains "$TASK_PLAN_SKILL" "technical layering cuts are FORBIDDEN" "technical layering forbidden" || return

  pass_test
}

test_step31_attributable_and_ru1() {
  start_test "task-plan step 3.1: attributable principle and DX RU1 callout"

  _assert_contains "$TASK_PLAN_SKILL" "#### 3.1 基本原则" "step 3.1 heading" || return
  _assert_contains "$TASK_PLAN_SKILL" "DX RU1 固定提示" "DX RU1 callout" || return
  _assert_contains "$TASK_PLAN_SKILL" "产出在任何业务页面/流程上直接可见时，必须归到对应业务模块" "business hard rule" || return
  _assert_contains "$TASK_PLAN_SKILL" '只有产出不在任何业务页面/流程上直接可见，才允许标 `基础设施`' "infra hard rule" || return
  _assert_contains "$TASK_PLAN_SKILL" "基础设施识别示例：项目脚手架、共用 Button/Modal 组件库、API client、auth context、构建配置" "infra examples" || return
  _assert_contains "$TASK_PLAN_SKILL" "可归属" "attributable principle" || return
  _assert_contains "$TASK_PLAN_SKILL" '每个业务功能 task 必须可归属到一个模块章节' "module chapter attribution" || return

  pass_test
}

test_step32_antipattern_e() {
  start_test "task-plan step 3.2: anti-pattern E with judgment and examples"

  _assert_contains "$TASK_PLAN_SKILL" "#### 3.2 反模式（必须避免）" "step 3.2 heading" || return
  _assert_contains "$TASK_PLAN_SKILL" "反模式 E：业务功能 task 没有模块归属" "anti-pattern E heading" || return
  _assert_contains "$TASK_PLAN_SKILL" "判断逻辑：产出在任何业务页面/流程上直接可见" "anti-pattern E judgment" || return
  _assert_contains "$TASK_PLAN_SKILL" "典型错误示例：登录流程、列表筛选、批量导出、权限提示、详情页状态展示都不是基础设施" "anti-pattern E examples" || return

  pass_test
}

test_step33_soft_cap() {
  start_test "task-plan step 3.3: single-module soft cap 3"

  _assert_contains "$TASK_PLAN_SKILL" "#### 3.3 task 数量启发式" "step 3.3 heading" || return
  _assert_contains "$TASK_PLAN_SKILL" "单模块软上限 = 3 tasks" "single module soft cap" || return
  _assert_contains "$TASK_PLAN_SKILL" "单个模块被拆成超过 3 个 task 时" "single module review trigger" || return

  pass_test
}

test_step34_self_check_item5() {
  start_test "task-plan step 3.4: self-check item 5"

  _assert_contains "$TASK_PLAN_SKILL" "#### 3.4 拆分后自检清单" "step 3.4 heading" || return
  _assert_contains "$TASK_PLAN_SKILL" "5. [ ] 所有 task 的模块归属是否满足硬规则" "self-check item 5" || return

  pass_test
}

test_deleted_old_steps() {
  start_test "task-plan deletes old module-spec and batch task file steps"

  _assert_missing "$TASK_PLAN_SKILL" "### 步骤 2：生成模块规格" "old step 2 deleted" || return
  _assert_missing "$TASK_PLAN_SKILL" "### 步骤 2.5：PM 确认模块规格" "old step 2.5 deleted" || return
  _assert_missing "$TASK_PLAN_SKILL" "### 步骤 5：生成 task 文件" "old step 5 deleted" || return
  _assert_missing "$TASK_PLAN_SKILL" "为每个 task 从模板创建文件" "old batch task file generation deleted" || return

  pass_test
}

test_output_contract() {
  start_test "task-plan output contract: title list only plus change log"

  _assert_contains "$TASK_PLAN_SKILL" "### 步骤 4：写 task-plan.md" "step 4 heading" || return
  _assert_contains "$TASK_PLAN_SKILL" "内容只包含 task 标题列表，不生成具体 task 文档" "title list only" || return
  _assert_contains "$TASK_PLAN_SKILL" '`id` / `title` / `所属模块` / `所属模块章节` / 一句话 summary / order / risk' "task-plan columns" || return
  _assert_contains "$TASK_PLAN_SKILL" "**变更记录** section" "change log section required" || return
  _assert_contains "$TASK_PLAN_SKILL" 'Stage 5 只写 `task-plan.md`' "stage 5 only writes task-plan" || return

  pass_test
}

test_step5_gate() {
  start_test "task-plan step 5: PM confirms then req-stage-gate advances"

  _assert_contains "$TASK_PLAN_SKILL" "### 步骤 5：PM 确认 task-plan.md → /req-stage-gate advances to stage 6" "new step 5 heading" || return
  _assert_contains "$TASK_PLAN_SKILL" '具体 task 文档由 stage 6 的 `/task-spec <task-id>` 按 `task-plan.md` 逐个生成' "stage 6 task-spec one by one" || return

  pass_test
}

test_step3_opening_granularity
test_step31_attributable_and_ru1
test_step32_antipattern_e
test_step33_soft_cap
test_step34_self_check_item5
test_deleted_old_steps
test_output_contract
test_step5_gate

report_results "task-plan"
