#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

TASK_TEMPLATE="$FRAMEWORK_ROOT/templates/task.md.tmpl"
MODULE_TEMPLATE="$FRAMEWORK_ROOT/templates/module.md.tmpl"
TASK_SPEC_SKILL="$FRAMEWORK_ROOT/skills/task-spec/SKILL.md"

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
  echo "--- file: $file ---" >&2
  sed -n '1,220p' "$file" >&2
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

_make_fake_req() {
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/pmaitaskspec.XXXXXX")
  mkdir -p "$dir/tasks" "$dir/docs/modules"

  cat > "$dir/task-plan.md" <<'EOF'
# Task Plan

| id | 标题 | 所属模块 | 简述 |
|----|------|----------|------|
| task-001 | 登录流程 | 账号模块 | 用户登录 |
| task-002 | API client | 基础设施 | 请求封装 |
| task-003 | 跨模块权限提示 | 账号模块, 权限模块 | 多模块提示 |
EOF

  cat > "$dir/tasks/task-001-login.md" <<'EOF'
# Task 001: 登录流程

**所属模块：** 账号模块
**状态：** 已完成

## PM 反馈
### 反馈 1 - 2026-04-25
**问题描述：** 错误提示没有区分账号不存在和密码错误
**要求修改：** 按后端错误码展示不同提示
**处理结果：** 已处理
EOF

  cat > "$dir/tasks/task-004-orphan.md" <<'EOF'
# Task 004: Orphan
EOF

  echo "$dir"
}

# -----------------------------------------------------------------
# Scenario 1: v3 单文件 typed contract — 三区结构（delta-3）
# -----------------------------------------------------------------

test_business_task_contract() {
  start_test "task-spec v3 单文件 typed contract: 三区 region 标记 + 各区核心段"

  # 格式标记 + 三区 region 标记
  _assert_contains "$TASK_TEMPLATE" "<!-- task_format: single-typed-v3 -->" "v3 格式标记" || return
  _assert_contains "$TASK_TEMPLATE" "<!-- region: PM-CONFIRM begin -->" "PM 确认区 begin 标记" || return
  _assert_contains "$TASK_TEMPLATE" "<!-- region: EXEC begin -->" "执行区 begin 标记" || return
  _assert_contains "$TASK_TEMPLATE" "<!-- region: AUDIT begin -->" "审计区 begin 标记" || return

  # PM 确认区：任务卡 / 范围 / 验收清单 / PM 反馈承接清单
  _assert_contains "$TASK_TEMPLATE" "## 📌 任务卡" "PM 确认区 任务卡" || return
  _assert_contains "$TASK_TEMPLATE" "## 📦 范围（改 / 不改）" "PM 确认区 范围" || return
  _assert_contains "$TASK_TEMPLATE" "## ✅ 验收清单（PM 走查）" "PM 确认区 验收清单" || return
  _assert_contains "$TASK_TEMPLATE" "## 📥 PM 反馈承接清单" "PM 确认区 反馈承接清单" || return

  # 执行区：实现规格 / 实现设计引用 / 约束与易错 / 自测说明 / 工程层验收
  _assert_contains "$TASK_TEMPLATE" "## 🔧 实现规格" "执行区 实现规格" || return
  _assert_contains "$TASK_TEMPLATE" "## 🗂️ 文件范围（机器校验）" "执行区 文件范围机器校验" || return
  _assert_contains "$TASK_TEMPLATE" "## 🧩 实现设计引用（HOW）" "执行区 实现设计引用" || return
  _assert_contains "$TASK_TEMPLATE" "## ⚠️ 约束与易错" "执行区 约束与易错" || return
  _assert_contains "$TASK_TEMPLATE" "HOW-ID" "实现设计引用含 HOW-ID 列" || return

  # 审计区：文档偏差 / 自审记录 / 历史档案
  _assert_contains "$TASK_TEMPLATE" "## 📋 文档偏差" "审计区 文档偏差" || return
  _assert_contains "$TASK_TEMPLATE" "## 🔍 自审记录" "审计区 自审记录" || return

  # 单文件塌缩：删旧 req 级段（已移 prd.md）
  _assert_missing "$TASK_TEMPLATE" "## 📋 功能清单" "task 模板不再含功能清单（已移 prd.md）" || return
  _assert_missing "$TASK_TEMPLATE" "## 📐 产物预览" "task 模板不再含产物预览（已移 prd.md）" || return
  _assert_missing "$TASK_TEMPLATE" "## 🎯 关键产品决策" "task 模板不再含关键产品决策（已移 prd.md）" || return

  pass_test
}

test_task_templates_use_four_state_machine() {
  start_test "task template uses current 4-state task status machine"

  _assert_contains "$TASK_TEMPLATE" "合法状态值（4 态）：待执行 / 执行中 / 已完成 / 已废弃" "v3 模板 4 态说明" || return
  _assert_contains "$TASK_TEMPLATE" "| **状态** | 待执行 |" "v3 模板默认待执行" || return
  _assert_missing "$TASK_TEMPLATE" "待确认 / 执行中 / 待验收" "v3 模板不含旧 5 态说明" || return

  pass_test
}

test_no_engineering_template() {
  start_test "task-spec 不再产 .engineering.md（delta-3 双→单文件塌缩）"

  if [ -f "$FRAMEWORK_ROOT/templates/task.engineering.md.tmpl" ]; then
    _fail "task.engineering.md.tmpl 应已删除（delta-3）"
    return
  fi
  _assert_contains "$TASK_SPEC_SKILL" "不再产 \`.engineering.md\`" "SKILL 明确不产 .engineering.md" || return
  _assert_contains "$TASK_SPEC_SKILL" "单文件 typed contract" "SKILL 明确单文件 typed contract" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 2: infrastructure task simplified path
# -----------------------------------------------------------------

test_infrastructure_task_contract() {
  start_test "task-spec infrastructure task: 走简化路径 + require acceptance"

  _assert_contains "$TASK_SPEC_SKILL" "基础设施 task 走简化路径" "infrastructure simplified path step" || return
  _assert_contains "$TASK_SPEC_SKILL" '`所属模块` 为 `基础设施`' "infrastructure branch condition" || return
  _assert_contains "$TASK_SPEC_SKILL" "PM 确认区·验收清单必须填可验证条件" "infra acceptance required" || return
  _assert_contains "$TASK_TEMPLATE" "基础设施 task" "template infra reference" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 3: (已删除) cross-module 章节格式
# 职责迁到 doc-update SKILL（doc-update/SKILL.md `模块A:章节X, 模块B:章节Y`）。
# task-spec 只产出 `所属模块章节` 字段本身（test_template_regression 已覆盖）。
# -----------------------------------------------------------------

# -----------------------------------------------------------------
# Scenario 4: task-plan vs tasks/ validation prompt
# -----------------------------------------------------------------

test_plan_tasks_diff_prompt() {
  start_test "task-spec validates task-plan.md vs tasks/ and prompts PM"

  local fake
  fake=$(_make_fake_req)

  local plan_ids
  plan_ids=$(grep -Eo 'task-[0-9]{3}' "$fake/task-plan.md" | sort -u | tr '\n' ' ')
  local file_ids
  file_ids=$(find "$fake/tasks" -name 'task-[0-9][0-9][0-9]-*.md' -print | sed -E 's|.*/(task-[0-9]{3})-.*|\1|' | sort -u | tr '\n' ' ')

  if [[ "$plan_ids" != *"task-002"* ]] || [[ "$file_ids" == *"task-002"* ]]; then
    _fail "mock diff did not include plan-only task-002"
    rm -rf "$fake"
    return
  fi
  if [[ "$file_ids" != *"task-004"* ]] || [[ "$plan_ids" == *"task-004"* ]]; then
    _fail "mock diff did not include file-only task-004"
    rm -rf "$fake"
    return
  fi

  _assert_contains "$TASK_SPEC_SKILL" "task-plan.md ↔ tasks/" "consistency validation heading" || { rm -rf "$fake"; return; }
  _assert_contains "$TASK_SPEC_SKILL" "选择处理路径" "PM prompt on diff" || { rm -rf "$fake"; return; }

  rm -rf "$fake"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 5: PM feedback annotated as pitfalls
# -----------------------------------------------------------------

test_pm_feedback_annotation() {
  start_test "task-spec collects 前序「已完成」task PM 反馈，按 relevance 二分（delta-3 §2.4）"

  local fake
  fake=$(_make_fake_req)

  if ! grep -F -q "错误提示没有区分账号不存在和密码错误" "$fake/tasks/task-001-login.md"; then
    _fail "mock completed task feedback missing"
    rm -rf "$fake"
    return
  fi

  # 数据源：前序「已完成」task 文件的「PM 反馈」段
  _assert_contains "$TASK_SPEC_SKILL" '前序「已完成」task 文件的「PM 反馈」段' "completed task feedback source" || { rm -rf "$fake"; return; }
  # delta-3：relevance 二分（适用 / 不适用），不再 sentiment 三类分流
  _assert_contains "$TASK_SPEC_SKILL" "relevance 二分" "relevance 二分 mechanism" || { rm -rf "$fake"; return; }
  _assert_contains "$TASK_SPEC_SKILL" "适用当前 task" "relevance 适用 分支" || { rm -rf "$fake"; return; }
  _assert_contains "$TASK_SPEC_SKILL" "不适用" "relevance 不适用 分支" || { rm -rf "$fake"; return; }
  # 每条登记进 PM 反馈承接清单
  _assert_contains "$TASK_SPEC_SKILL" "PM 反馈承接清单" "PM 反馈承接清单 登记" || { rm -rf "$fake"; return; }
  # 旧 sentiment 三类已删
  _assert_missing "$TASK_SPEC_SKILL" "正向规则 / 反向约束 / 决策记录" "旧 sentiment 三类分流已删" || { rm -rf "$fake"; return; }

  rm -rf "$fake"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 6: infrastructure task explicitly skips module merge
# -----------------------------------------------------------------

test_infrastructure_no_module_merge_message() {
  start_test "task-spec infrastructure task states no module merge"

  _assert_contains "$TASK_SPEC_SKILL" "本 task 不触发 module 规格 merge" "infra no module merge message" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 7: template format regression
# -----------------------------------------------------------------

test_template_regression() {
  start_test "template regression: task/module/DESIGN completeness"

  # task.md.tmpl v3 单文件 typed contract：元字段在「📌 任务卡」表格内；
  # delta-3 后启动前必读 / 文档偏差 / 自审记录 全部回到单文件三区
  _assert_contains "$TASK_TEMPLATE" "| **所属模块** |" "task module field (table row)" || return
  _assert_contains "$TASK_TEMPLATE" "| **所属模块章节** |" "task module chapter field (table row)" || return
  _assert_contains "$TASK_TEMPLATE" "## 📌 任务卡" "task card section preserved" || return
  _assert_contains "$TASK_TEMPLATE" "## 📦 范围" "task scope section preserved" || return
  _assert_contains "$TASK_TEMPLATE" "### 执行日志" "task execution log preserved" || return
  _assert_contains "$TASK_TEMPLATE" "### PM 反馈" "task PM feedback preserved" || return
  # 启动前必读 / 文档偏差 / 自审记录 在 v3 单文件执行区 / 审计区
  _assert_contains "$TASK_TEMPLATE" "## 🚦 启动前必读" "v3 startup section" || return
  _assert_contains "$TASK_TEMPLATE" "## 📋 文档偏差" "v3 doc diff section" || return
  _assert_contains "$TASK_TEMPLATE" "## 🔍 自审记录" "v3 self-review section" || return

  # module spec = 模块活文档：只留跨 req 长期为真的章节；req 时态章节已砍（详见 templates/module.md.tmpl 顶部说明）
  _assert_contains "$MODULE_TEMPLATE" "## 摘要" "module summary preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 一、模块定位" "module positioning preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 二、功能清单（硬约束）" "module function list" || return
  _assert_contains "$MODULE_TEMPLATE" "#### 1 · [三级功能名]" "module three-level function block" || return
  _assert_contains "$MODULE_TEMPLATE" "> **使用角色**：" "module section 级使用角色 blockquote（§5.1）" || return
  _assert_contains "$MODULE_TEMPLATE" "| 二级功能 | 三级功能 | 使用角色 | 需求描述 |" "module 4 列表格 header（§5.1）" || return
  _assert_missing "$MODULE_TEMPLATE" "**业务规则**：" "module 模板不再用 4 块结构 业务规则 heading（§5.1）" || return
  _assert_missing "$MODULE_TEMPLATE" "**字段口径**（仅当" "module 模板不再用字段口径独立表（§5.1）" || return
  _assert_contains "$MODULE_TEMPLATE" "## 三、页面与交互范围" "module pages section preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 四、硬约束" "module hard constraints preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 五、跨模块依赖与占位策略" "module dependencies preserved" || return
  _assert_missing "$MODULE_TEMPLATE" "Scope In / Scope Out" "module 模板不再含 req 级 Scope 章节" || return
  _assert_missing "$MODULE_TEMPLATE" "## 六、本批不做" "module 模板不再含 req 级 本批不做 章节" || return
  _assert_missing "$MODULE_TEMPLATE" "## 七、验收标准" "module 模板不再含 req 级 验收标准 章节" || return
  _assert_missing "$MODULE_TEMPLATE" "Task 拆分提示" "module 模板不再含 req 级 Task 拆分提示 章节" || return
  _assert_missing "$MODULE_TEMPLATE" "## 八、实现指引" "module implementation guide removed" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 8: 单文件 typed contract 模板 region 边界完整
# -----------------------------------------------------------------

test_typed_contract_region_boundaries() {
  start_test "task-spec v3 模板: 三区 region begin/end 标记成对完整"

  for region in "PM-CONFIRM" "EXEC" "AUDIT"; do
    _assert_contains "$TASK_TEMPLATE" "<!-- region: $region begin -->" "$region begin 标记" || return
    _assert_contains "$TASK_TEMPLATE" "<!-- region: $region end -->" "$region end 标记" || return
  done

  # 顺序检查：PM-CONFIRM → EXEC → AUDIT
  local pm_line exec_line audit_line
  pm_line=$(grep -n "region: PM-CONFIRM begin" "$TASK_TEMPLATE" | head -1 | cut -d: -f1)
  exec_line=$(grep -n "region: EXEC begin" "$TASK_TEMPLATE" | head -1 | cut -d: -f1)
  audit_line=$(grep -n "region: AUDIT begin" "$TASK_TEMPLATE" | head -1 | cut -d: -f1)

  if [[ -z "$pm_line" || -z "$exec_line" || -z "$audit_line" ]]; then
    _fail "region ordering check: missing one of PM-CONFIRM / EXEC / AUDIT begin marker"
    return
  fi
  if (( pm_line >= exec_line || exec_line >= audit_line )); then
    _fail "region ordering: PM-CONFIRM($pm_line) < EXEC($exec_line) < AUDIT($audit_line) 不满足"
    return
  fi

  pass_test
}

# -----------------------------------------------------------------
# Scenario 9: SKILL.md 步骤 7 派生 task-scoped 自测说明 + 占位值
# -----------------------------------------------------------------

test_step7_derives_uat_and_placeholders() {
  start_test "task-spec SKILL.md: 步骤 7 派生 task-scoped 自测说明 + 占位值（delta-3 §2.6）"

  _assert_contains "$TASK_SPEC_SKILL" "派生 task-scoped 自测说明" "step 7 header (UAT 派生)" || return
  _assert_contains "$TASK_SPEC_SKILL" "冷启动 smoke" "step 7 冷启动 smoke 追加" || return
  _assert_contains "$TASK_SPEC_SKILL" "非 UI task" "step 7 非 UI task 跳过" || return
  _assert_contains "$TASK_SPEC_SKILL" "占位值" "step 7 占位值内联进执行区" || return

  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_business_task_contract
test_task_templates_use_four_state_machine
test_no_engineering_template
test_infrastructure_task_contract
test_plan_tasks_diff_prompt
test_pm_feedback_annotation
test_infrastructure_no_module_merge_message
test_template_regression
test_typed_contract_region_boundaries
test_step7_derives_uat_and_placeholders

report_results "task-spec"
