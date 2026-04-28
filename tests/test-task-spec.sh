#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

TASK_TEMPLATE="$FRAMEWORK_ROOT/templates/task.md.tmpl"
MODULE_TEMPLATE="$FRAMEWORK_ROOT/templates/module.md.tmpl"
DESIGN_TEMPLATE="$FRAMEWORK_ROOT/templates/DESIGN.md.tmpl"
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
# Scenario 1: business module task full generation contract
# -----------------------------------------------------------------

test_business_task_contract() {
  start_test "task-spec business task: 用户使用流程/功能清单/实现指引/用例数据"

  _assert_contains "$TASK_TEMPLATE" "## 用户使用流程（业务模块 task 必填，即验收依据）" "business task user flow section" || return
  _assert_contains "$TASK_TEMPLATE" "## 功能清单（业务模块 task 必填）" "business task function list section" || return
  _assert_contains "$TASK_TEMPLATE" "### 1 · [三级功能名]" "three-level function block" || return
  _assert_contains "$TASK_TEMPLATE" "| 二级功能 | 三级功能 | 使用角色 |" "three-column function table" || return
  _assert_contains "$TASK_TEMPLATE" "## 实现指引" "implementation guide section" || return
  _assert_contains "$TASK_TEMPLATE" "- **组件复用**" "component reuse bullet" || return
  _assert_contains "$TASK_TEMPLATE" "- **状态覆盖**" "state coverage bullet" || return
  _assert_contains "$TASK_TEMPLATE" "- **关键逻辑**" "key logic bullet" || return
  _assert_contains "$TASK_TEMPLATE" "- **易错点 / 禁止项**" "pitfall bullet" || return
  _assert_contains "$TASK_SPEC_SKILL" "用例数据" "solution use-case data handling" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 2: infrastructure task simplified path
# -----------------------------------------------------------------

test_infrastructure_task_contract() {
  start_test "task-spec infrastructure task: skip business sections and require acceptance"

  _assert_contains "$TASK_SPEC_SKILL" '如果 `所属模块` 为 `基础设施`' "infrastructure branch" || return
  _assert_contains "$TASK_SPEC_SKILL" '`用户使用流程` 填 `无（基础设施 task）`' "infra user flow skip" || return
  _assert_contains "$TASK_SPEC_SKILL" '`功能清单` 填 `无（基础设施 task）`' "infra function list skip" || return
  _assert_contains "$TASK_SPEC_SKILL" '`验收标准` 必须填写可验证条件' "infra acceptance required" || return
  _assert_contains "$TASK_TEMPLATE" "基础设施 task 必填" "template acceptance comment" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 3: cross-module chapter format
# -----------------------------------------------------------------

test_cross_module_format() {
  start_test "task-spec cross-module 所属模块章节 format"

  _assert_contains "$TASK_TEMPLATE" "模块A:章节X, 模块B:章节Y" "template cross-module format" || return
  _assert_contains "$TASK_SPEC_SKILL" "模块A:章节X, 模块B:章节Y" "skill cross-module format" || return
  _assert_contains "$TASK_SPEC_SKILL" '跨模块 task 的 `所属模块章节` 使用' "skill cross-module rule" || return

  pass_test
}

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
  _assert_contains "$TASK_SPEC_SKILL" "请选择处理方式" "PM prompt on diff" || { rm -rf "$fake"; return; }
  _assert_contains "$TASK_SPEC_SKILL" "A) 保留 task-plan.md，删除多余 task 文件" "keep plan option" || { rm -rf "$fake"; return; }

  rm -rf "$fake"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 5: PM feedback annotated as pitfalls
# -----------------------------------------------------------------

test_pm_feedback_annotation() {
  start_test "task-spec annotates 易错点 with source task PM feedback"

  local fake
  fake=$(_make_fake_req)

  if ! grep -F -q "错误提示没有区分账号不存在和密码错误" "$fake/tasks/task-001-login.md"; then
    _fail "mock completed task feedback missing"
    rm -rf "$fake"
    return
  fi

  _assert_contains "$TASK_SPEC_SKILL" "状态为「已完成」且所属模块与当前 task 有交集" "completed same-module feedback source" || { rm -rf "$fake"; return; }
  _assert_contains "$TASK_SPEC_SKILL" "（来自 task-XXX 的 PM 反馈）" "feedback source annotation" || { rm -rf "$fake"; return; }

  rm -rf "$fake"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 6: infrastructure task explicitly skips module merge
# -----------------------------------------------------------------

test_infrastructure_no_module_merge_message() {
  start_test "task-spec infrastructure task states no module merge"

  _assert_contains "$TASK_SPEC_SKILL" "本 task 不触发 module 规格 merge（按 Q1 决议）" "infra no module merge message" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 7: template format regression
# -----------------------------------------------------------------

test_template_regression() {
  start_test "template regression: task/module/DESIGN completeness"

  _assert_contains "$TASK_TEMPLATE" "**所属模块：**" "task module field" || return
  _assert_contains "$TASK_TEMPLATE" "**所属模块章节：**" "task module chapter field" || return
  _assert_contains "$TASK_TEMPLATE" "## 启动前必读（按顺序，读完再执行）" "task startup section preserved" || return
  _assert_contains "$TASK_TEMPLATE" "## 任务描述" "task description section preserved" || return
  _assert_contains "$TASK_TEMPLATE" "## 执行范围" "task scope section preserved" || return
  _assert_contains "$TASK_TEMPLATE" "## 执行日志（agent 填写，不要删除历史记录）" "task execution log preserved" || return
  _assert_contains "$TASK_TEMPLATE" "## 文档偏差（execution agent 填写，只记录事实，不判断是否需要修改）" "task doc diff preserved" || return
  _assert_contains "$TASK_TEMPLATE" "## 自审记录（PM 跑完 review 后由 orchestrator 机械追加，不删历史）" "task self-review preserved" || return
  _assert_contains "$TASK_TEMPLATE" "## PM 反馈（orchestrator 代为追加，agent 重跑前必读）" "task PM feedback preserved" || return

  _assert_contains "$MODULE_TEMPLATE" "## 摘要" "module summary preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 一、模块定位" "module positioning preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 二、Scope In / Scope Out" "module scope preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 三、功能清单（硬约束）" "module function list" || return
  _assert_contains "$MODULE_TEMPLATE" "#### 1 · [三级功能名]" "module three-level function block" || return
  _assert_contains "$MODULE_TEMPLATE" "| 二级功能 | 三级功能 | 使用角色 |" "module three-column table" || return
  _assert_contains "$MODULE_TEMPLATE" "## 五、硬约束" "module hard constraints preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 七、验收标准" "module acceptance preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 八、跨模块依赖与占位策略" "module dependencies preserved" || return
  _assert_contains "$MODULE_TEMPLATE" "## 九、Task 拆分提示" "module task split hints preserved" || return
  _assert_missing "$MODULE_TEMPLATE" "## 八、实现指引" "module implementation guide removed" || return

  _assert_contains "$DESIGN_TEMPLATE" "## 创意自由度" "DESIGN creative freedom section" || return
  _assert_contains "$DESIGN_TEMPLATE" "**高自由度区域**：动效、微交互、图表样式、卡片排列方式、空状态文案" "DESIGN high freedom list" || return
  _assert_contains "$DESIGN_TEMPLATE" "**低自由度区域**：信息层级、关键操作按钮位置、状态标签颜色、色彩系统、间距基准" "DESIGN low freedom list" || return
  _assert_contains "$DESIGN_TEMPLATE" "**不可偏离**：模块规格/task 功能清单中的功能行为、数据规则、角色权限" "DESIGN non-negotiable list" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 8: 产物预览 section 在 task.md.tmpl 中
# -----------------------------------------------------------------

test_artifact_preview_template_section() {
  start_test "task-spec 产物预览 section: template has it between 用户使用流程 and 功能清单"

  _assert_contains "$TASK_TEMPLATE" "## 产物预览（按 task 类型生成，由 /task-spec 自动填写）" "artifact preview section header" || return
  _assert_contains "$TASK_TEMPLATE" "UI task" "UI task rule in template comment" || return
  _assert_contains "$TASK_TEMPLATE" "ASCII 线框图" "ASCII wireframe rule" || return
  _assert_contains "$TASK_TEMPLATE" "bullet 树形大纲" "bullet outline rule" || return
  _assert_contains "$TASK_TEMPLATE" "信息层级低自由度" "creative freedom boundary" || return

  # 顺序检查：产物预览 在 用户使用流程 之后、功能清单 之前
  local user_flow_line
  local preview_line
  local function_list_line
  user_flow_line=$(grep -n "^## 用户使用流程" "$TASK_TEMPLATE" | head -1 | cut -d: -f1)
  preview_line=$(grep -n "^## 产物预览" "$TASK_TEMPLATE" | head -1 | cut -d: -f1)
  function_list_line=$(grep -n "^## 功能清单" "$TASK_TEMPLATE" | head -1 | cut -d: -f1)

  if [[ -z "$user_flow_line" || -z "$preview_line" || -z "$function_list_line" ]]; then
    _fail "section ordering check: missing one of 用户使用流程/产物预览/功能清单"
    return
  fi

  if (( preview_line <= user_flow_line || preview_line >= function_list_line )); then
    _fail "section ordering: 产物预览 must be between 用户使用流程 ($user_flow_line) and 功能清单 ($function_list_line), got $preview_line"
    return
  fi

  pass_test
}

# -----------------------------------------------------------------
# Scenario 9: SKILL.md 含 task 类型判定 + 生成规则
# -----------------------------------------------------------------

test_artifact_preview_skill_logic() {
  start_test "task-spec SKILL.md: 步骤 6.5 含 task 类型判定 + UI 线框图 + 大纲生成规则"

  _assert_contains "$TASK_SPEC_SKILL" "### 步骤 6.5：根据 task 类型生成产物预览" "step 6.5 header" || return
  _assert_contains "$TASK_SPEC_SKILL" "/design-review" "UI task detection by review tool" || return
  _assert_contains "$TASK_SPEC_SKILL" "ASCII 线框图" "UI artifact format" || return
  _assert_contains "$TASK_SPEC_SKILL" "bullet 树形大纲" "doc artifact format" || return
  _assert_contains "$TASK_SPEC_SKILL" "无（基础设施 task）" "infra task skip in step 6" || return
  _assert_contains "$TASK_SPEC_SKILL" "信息层级（哪个先看哪个后看）→ **低自由度**" "creative freedom boundary in skill" || return
  _assert_contains "$TASK_SPEC_SKILL" "视觉细节（卡片样式 / 间距 / 颜色 / 微交互）→ **高自由度**" "visual detail freedom boundary" || return

  # 基础设施 task 简化路径含产物预览处理
  _assert_contains "$TASK_SPEC_SKILL" '`产物预览` 填 `无（基础设施 task）`' "infra task fills artifact preview as 无" || return

  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_business_task_contract
test_infrastructure_task_contract
test_cross_module_format
test_plan_tasks_diff_prompt
test_pm_feedback_annotation
test_infrastructure_no_module_merge_message
test_template_regression
test_artifact_preview_template_section
test_artifact_preview_skill_logic

report_results "task-spec"
