#!/usr/bin/env bash
# test-speed-mode.sh
#
# 验证 speed mode（2026-05-26）：
#   T1: status-view.py 含 --stage6-entry argparse
#   T2: scripts/_lib/stage6_summary.py 模块存在 + build_summary / render 函数
#   T3: implementation-design.md.tmpl 段 1 含「决策类型」列 + 填写规则注释
#   T4: task-plan.md.tmpl §一 含「决策类型」列 + 填写规则
#   T5: req-stage-gate SKILL.md 含 ## Speed Mode 段
#   T6: fixture 全机械 HOW → render 输出"AI 自决 N 件" + "PM 拍过 0 件结构决策"
#   T7: fixture 全结构 HOW → render 输出"AI 自决 0 件" + "PM 拍过 N 件结构决策"
#   T8: fixture 老 req（无「决策类型」列）→ 默认按结构（保守 / 兼容）
#   T9: fixture 有 SIMP 行 → 全部归入"PM 拍过"段
#   T10: fixture task 表有结构 task → 出现在"PM 拍过"段 + task 拆分段
#   T11: build_summary 缺 implementation-design.md → 返回 None（CLI exit 3）
#   T12: SKILL.md Stage 4 4B 含 speed 自动续条件文案
#   T13: SKILL.md Stage 5→6 含 status-view.py --stage6-entry 调用

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_VIEW="$REPO_ROOT/scripts/status-view.py"
STAGE6_MOD="$REPO_ROOT/scripts/_lib/stage6_summary.py"
IMPL_TMPL="$REPO_ROOT/templates/implementation-design.md.tmpl"
PLAN_TMPL="$REPO_ROOT/templates/task-plan.md.tmpl"
SKILL_MD="$REPO_ROOT/skills/req-stage-gate/SKILL.md"
TASK_SPEC_MD="$REPO_ROOT/skills/task-spec/SKILL.md"
TASK_CONFIRM_MD="$REPO_ROOT/skills/task-confirm/SKILL.md"
TASK_PLAN_MD="$REPO_ROOT/skills/task-plan/SKILL.md"

# -----------------------------------------------------------------
# T1: status-view.py 含 --stage6-entry argparse
# -----------------------------------------------------------------
test_stage6_entry_argparse() {
  start_test "T1: status-view.py 含 --stage6-entry argparse"
  if ! grep -q '"--stage6-entry"' "$STATUS_VIEW"; then
    _fail "scripts/status-view.py 缺 --stage6-entry argparse"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T2: stage6_summary.py 模块存在 + 关键函数
# -----------------------------------------------------------------
test_stage6_module_exists() {
  start_test "T2: scripts/_lib/stage6_summary.py 模块 + build_summary / render"
  assert_file_exists "$STAGE6_MOD" "stage6_summary.py" || return
  if ! grep -q "^def build_summary" "$STAGE6_MOD"; then
    _fail "stage6_summary.py 缺 def build_summary"
    return
  fi
  if ! grep -q "^def render" "$STAGE6_MOD"; then
    _fail "stage6_summary.py 缺 def render"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T3: implementation-design.md.tmpl 段 1 HOW 表含「决策类型」列
# -----------------------------------------------------------------
test_impl_tmpl_decision_kind_column() {
  start_test "T3: implementation-design.md.tmpl 段 1 HOW 表含「决策类型」列"
  assert_file_contains "$IMPL_TMPL" "决策类型" "段 1 HOW 表头含决策类型列" || return
  if ! grep -q "结构.*机械\|机械.*结构\|<结构 / 机械>" "$IMPL_TMPL"; then
    _fail "tmpl 缺「结构 / 机械」填写示例"
    return
  fi
  if ! grep -q "拿不准.*默认.*结构\|默认填.*结构" "$IMPL_TMPL"; then
    _fail "tmpl 缺「拿不准默认结构」保守规则"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T4: task-plan.md.tmpl §一 含「决策类型」列
# -----------------------------------------------------------------
test_plan_tmpl_decision_kind_column() {
  start_test "T4: task-plan.md.tmpl §一 含「决策类型」列"
  assert_file_contains "$PLAN_TMPL" "决策类型" "§一 task 表头含决策类型列" || return
  # 表头本身要有这一列（不是只在注释里）
  if ! grep -q "| id |.*| 决策类型 |" "$PLAN_TMPL"; then
    _fail "§一 表头 row 缺「决策类型」列"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T5: req-stage-gate SKILL.md 含 ## Speed Mode 段
# -----------------------------------------------------------------
test_skill_speed_mode_section() {
  start_test "T5: req-stage-gate SKILL.md 含 ## Speed Mode 段"
  if ! grep -q "^## Speed Mode" "$SKILL_MD"; then
    _fail "SKILL.md 缺 ## Speed Mode 段（一级标题）"
    return
  fi
  # 段内必含的关键约束
  for kw in "决策类型=结构" "stage6-entry" "未决问题闸门" "硬规则"; do
    if ! grep -q "$kw" "$SKILL_MD"; then
      _fail "SKILL.md Speed Mode 段缺关键字「$kw」"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
# Fixture helpers
# -----------------------------------------------------------------
_make_req_dir_with_files() {
  # $1 = impl 文件内容；$2 = plan 文件内容
  local tmp; tmp=$(mktemp -d)
  cat > "$tmp/implementation-design.md" <<< "$1"
  cat > "$tmp/task-plan.md" <<< "$2"
  echo "$tmp"
}

_impl_with_mechanical_only() {
  cat <<'EOF'
# impl test fixture
## 段 1 · 架构决策表

| HOW-ID | 适用模块 / task 关键词 | 选择 | 备选 | 理由 | 约束失效条件 | 决策类型 | 来源 |
|---|---|---|---|---|---|---|---|
| HOW-01 | menu | 集中式 | 无非平凡备选 | brief 硬约束 | — | 机械 | 新增 |
| HOW-02 | schema | 不加字段 | — | PRD 硬约束 | — | 机械 | 新增 |

## 段 1.5 · 原型简化项

| SIMP-ID | PRD 锚点 | 真实需求 | 原型本次计划简化为 | 为什么简化 | 来源 |
|---|---|---|---|---|---|

EOF
}

_impl_with_structural_only() {
  cat <<'EOF'
# impl test fixture
## 段 1 · 架构决策表

| HOW-ID | 适用模块 / task 关键词 | 选择 | 备选 | 理由 | 约束失效条件 | 决策类型 | 来源 |
|---|---|---|---|---|---|---|---|
| HOW-01 | menu | 集中式 | DB / 抽 schema | 最简 | — | 结构 | 新增 |
| HOW-02 | check | 自审 | lint / runtime | 一次性 | — | 结构 | 新增 |

## 段 1.5 · 原型简化项

| SIMP-ID | PRD 锚点 | 真实需求 | 原型本次计划简化为 | 为什么简化 | 来源 |
|---|---|---|---|---|---|

EOF
}

_impl_legacy_no_kind_column() {
  cat <<'EOF'
# impl test fixture (legacy, no 决策类型 column)
## 段 1 · 架构决策表

| HOW-ID | 适用模块 / task 关键词 | 选择 | 备选 | 理由 | 约束失效条件 | 来源 |
|---|---|---|---|---|---|---|
| HOW-01 | menu | 集中式 | DB | 最简 | — | 新增 |

## 段 1.5 · 原型简化项

| SIMP-ID | PRD 锚点 | 真实需求 | 原型本次计划简化为 | 为什么简化 | 来源 |
|---|---|---|---|---|---|

EOF
}

_impl_with_simp() {
  cat <<'EOF'
# impl test fixture
## 段 1 · 架构决策表

| HOW-ID | 适用模块 / task 关键词 | 选择 | 备选 | 理由 | 约束失效条件 | 决策类型 | 来源 |
|---|---|---|---|---|---|---|---|
| HOW-01 | menu | 集中式 | 无非平凡备选 | brief | — | 机械 | 新增 |

## 段 1.5 · 原型简化项

| SIMP-ID | PRD 锚点 | 真实需求 | 原型本次计划简化为 | 为什么简化 | 来源 |
|---|---|---|---|---|---|
| SIMP-01 | §5.3 非目标 | 见 PRD §5.3 | 本功能原型不实现 | brief 划在 scope 外 | kind 2 |

EOF
}

_plan_simple() {
  cat <<'EOF'
# task-plan test fixture
## 一、Task 列表

| id | title | 所属模块 | 所属模块章节 | summary | order | risk | 决策类型 |
|----|-------|---------|------------|---------|-------|------|---------|
| task-001 | menu A | shell | 侧边栏 | rewrite A nav | 1 | R1 | 机械 |

## 二、执行顺序与并行性

串行执行。
EOF
}

_plan_with_structural_task() {
  cat <<'EOF'
# task-plan test fixture
## 一、Task 列表

| id | title | 所属模块 | 所属模块章节 | summary | order | risk | 决策类型 |
|----|-------|---------|------------|---------|-------|------|---------|
| task-001 | menu A + DESIGN rule | shell | 侧边栏 | rewrite A + 规范段写入 | 1 | R1 | 结构 |
| task-002 | menu B | shell | 侧边栏 | rewrite B nav | 2 | R1 | 机械 |

## 二、执行顺序与并行性

并行执行。
EOF
}

# -----------------------------------------------------------------
# T6: fixture 全机械 HOW → render 输出"AI 自决 N 件" + "PM 拍过 0 件"
# -----------------------------------------------------------------
test_render_all_mechanical() {
  start_test "T6: 全机械 HOW → AI 自决 N 件 + PM 拍过 0 件结构"
  local req_dir; req_dir=$(_make_req_dir_with_files "$(_impl_with_mechanical_only)" "$(_plan_simple)")
  local out; out=$(python3 "$STATUS_VIEW" --stage6-entry "$req_dir" 2>&1)
  rm -rf "$req_dir"
  if ! echo "$out" | grep -q "AI 自决 2 件"; then
    _fail "应输出「AI 自决 2 件」，实际：$out"
    return
  fi
  if ! echo "$out" | grep -q "PM 拍过 0 件"; then
    _fail "应输出「PM 拍过 0 件」"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T7: fixture 全结构 HOW → render 输出"AI 自决 0 件" + "PM 拍过 N 件"
# -----------------------------------------------------------------
test_render_all_structural() {
  start_test "T7: 全结构 HOW → AI 自决 0 件 + PM 拍过 N 件"
  local req_dir; req_dir=$(_make_req_dir_with_files "$(_impl_with_structural_only)" "$(_plan_simple)")
  local out; out=$(python3 "$STATUS_VIEW" --stage6-entry "$req_dir" 2>&1)
  rm -rf "$req_dir"
  if ! echo "$out" | grep -q "AI 自决 0 件"; then
    _fail "应输出「AI 自决 0 件」，实际：$out"
    return
  fi
  if ! echo "$out" | grep -q "PM 拍过 2 件"; then
    _fail "应输出「PM 拍过 2 件」（2 结构 HOW + 0 SIMP + 0 task 结构）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T8: 老 req（无「决策类型」列）→ 默认按结构（保守 / 兼容）
# -----------------------------------------------------------------
test_render_legacy_no_kind_column() {
  start_test "T8: 老 req（无决策类型列）→ 默认按结构（保守）"
  local req_dir; req_dir=$(_make_req_dir_with_files "$(_impl_legacy_no_kind_column)" "$(_plan_simple)")
  local out; out=$(python3 "$STATUS_VIEW" --stage6-entry "$req_dir" 2>&1)
  rm -rf "$req_dir"
  if ! echo "$out" | grep -q "AI 自决 0 件"; then
    _fail "老 req 应保守按结构，AI 自决 0 件；实际：$out"
    return
  fi
  if ! echo "$out" | grep -q "PM 拍过 1 件"; then
    _fail "老 req 应有 1 件结构（HOW-01）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T9: 有 SIMP 行 → 全部归入"PM 拍过"段
# -----------------------------------------------------------------
test_render_simp_into_pm_section() {
  start_test "T9: SIMP 行全部归入 PM 拍过段"
  local req_dir; req_dir=$(_make_req_dir_with_files "$(_impl_with_simp)" "$(_plan_simple)")
  local out; out=$(python3 "$STATUS_VIEW" --stage6-entry "$req_dir" 2>&1)
  rm -rf "$req_dir"
  if ! echo "$out" | grep -q "SIMP-01"; then
    _fail "总览应渲染 SIMP-01 行；实际：$out"
    return
  fi
  # 1 SIMP 即至少 1 件 PM 拍过；HOW 全机械
  if ! echo "$out" | grep -q "PM 拍过 1 件"; then
    _fail "应「PM 拍过 1 件」（0 HOW 结构 + 1 SIMP + 0 task 结构）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T10: task 表有结构 task → 出现在 PM 拍过段 + task 拆分段
# -----------------------------------------------------------------
test_render_structural_task() {
  start_test "T10: task 表有结构 task → PM 拍过段 + task 拆分段"
  local req_dir; req_dir=$(_make_req_dir_with_files "$(_impl_with_mechanical_only)" "$(_plan_with_structural_task)")
  local out; out=$(python3 "$STATUS_VIEW" --stage6-entry "$req_dir" 2>&1)
  rm -rf "$req_dir"
  if ! echo "$out" | grep -q "task-001.*拆分 / 合并 / 重排"; then
    _fail "结构 task-001 应在 PM 拍过段且标注「拆分 / 合并 / 重排」"
    return
  fi
  # task 拆分段应列两个 task
  if ! echo "$out" | grep -q "task-002"; then
    _fail "task 拆分段应列 task-002（机械）"
    return
  fi
  if ! echo "$out" | grep -q "执行：并行"; then
    _fail "执行模式应识别为并行（§二 含「并行」）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T11: 缺 implementation-design.md → CLI exit 3
# -----------------------------------------------------------------
test_missing_impl_design() {
  start_test "T11: 缺 implementation-design.md → CLI exit 3"
  local tmp; tmp=$(mktemp -d)
  cat > "$tmp/task-plan.md" <<< "(only plan, no impl)"
  python3 "$STATUS_VIEW" --stage6-entry "$tmp" >/dev/null 2>&1
  local rc=$?
  rm -rf "$tmp"
  if [ "$rc" -ne 3 ]; then
    _fail "缺 impl-design 应 exit 3，实际 exit $rc"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T12: SKILL.md Stage 4 4B 含 speed 自动续条件文案
# -----------------------------------------------------------------
test_skill_stage4_speed_auto_continue() {
  start_test "T12: SKILL.md Stage 4 4B 含 speed 自动续条件文案"
  # "Speed mode 自动续条件" 应在 Stage 4 4B 确认门段内
  if ! grep -q "Speed mode 自动续条件\|自动续条件" "$SKILL_MD"; then
    _fail "SKILL.md 缺「Speed mode 自动续条件」段文案"
    return
  fi
  if ! grep -q "0 个新建组件\|全部复用" "$SKILL_MD"; then
    _fail "SKILL.md 缺「0 个新建组件 / 全部复用」自动续条件"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T13: SKILL.md Stage 5→6 含 status-view.py --stage6-entry 调用
# -----------------------------------------------------------------
test_skill_stage6_entry_call() {
  start_test "T13: SKILL.md Stage 5→6 含 status-view.py --stage6-entry 调用"
  if ! grep -qE 'status-view\.py("?[[:space:]]+|"[[:space:]]+)--stage6-entry' "$SKILL_MD"; then
    _fail "SKILL.md 缺 status-view.py --stage6-entry 调用"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

# -----------------------------------------------------------------
# T14: task-spec SKILL 步骤 11 续跑文案（speed mode 2026-05-26 vp-7）
# -----------------------------------------------------------------
test_task_spec_continuation() {
  start_test "T14: task-spec SKILL 步骤 11 续跑 task-confirm（不再让 PM 手动贴）"
  if ! grep -q "续跑 /task-confirm\|续跑 task-confirm" "$TASK_SPEC_MD"; then
    _fail "task-spec SKILL 缺「续跑 task-confirm」speed mode 文案"
    return
  fi
  # 旧"下一步运行 /task-confirm <task 文件路径>"硬复制提示应已替换
  if grep -q "^✅ task 已定稿，下一步运行 /task-confirm <task 文件路径>$" "$TASK_SPEC_MD"; then
    _fail "task-spec 仍保留旧"手动贴 /task-confirm <path>"提示"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T15: task-confirm SKILL When To Use 含「续跑触发」分支
# -----------------------------------------------------------------
test_task_confirm_when_to_use_continuation() {
  start_test "T15: task-confirm SKILL When To Use 含续跑触发分支"
  if ! grep -q "续跑触发\|续跑.*task-spec" "$TASK_CONFIRM_MD"; then
    _fail "task-confirm SKILL When To Use 段缺「续跑触发」分支"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T16: task-plan SKILL 含步骤 3.5 执行模式结构决策门
# -----------------------------------------------------------------
test_task_plan_step_3_5_exec_mode() {
  start_test "T16: task-plan SKILL 含步骤 3.5 PM 拍板执行模式"
  if ! grep -q "步骤 3.5.*执行模式\|步骤 3\\.5.*执行模式" "$TASK_PLAN_MD"; then
    _fail "task-plan SKILL 缺步骤 3.5 标题"
    return
  fi
  # 必含的关键词
  for kw in "串行" "并行" "混合" "AI 倾向" "PM 拍板" "pm-explicit"; do
    if ! grep -q "$kw" "$TASK_PLAN_MD"; then
      _fail "task-plan 步骤 3.5 缺关键字「$kw」"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
# T17: task-plan.md.tmpl §二 含「执行模式（PM 拍板）」行
# -----------------------------------------------------------------
test_task_plan_tmpl_exec_mode_marker() {
  start_test "T17: task-plan.md.tmpl §二 含「执行模式（PM 拍板）」结构决策标记"
  if ! grep -q "执行模式（PM 拍板）" "$PLAN_TMPL"; then
    _fail "task-plan.md.tmpl §二 缺「执行模式（PM 拍板）」标记行"
    return
  fi
  if ! grep -q "task 级结构决策\|结构决策" "$PLAN_TMPL"; then
    _fail "task-plan.md.tmpl §二 填写注释缺「结构决策」说明"
    return
  fi
  pass_test
}

test_stage6_entry_argparse
test_stage6_module_exists
test_impl_tmpl_decision_kind_column
test_plan_tmpl_decision_kind_column
test_skill_speed_mode_section
test_render_all_mechanical
test_render_all_structural
test_render_legacy_no_kind_column
test_render_simp_into_pm_section
test_render_structural_task
test_missing_impl_design
test_skill_stage4_speed_auto_continue
test_skill_stage6_entry_call
test_task_spec_continuation
test_task_confirm_when_to_use_continuation
test_task_plan_step_3_5_exec_mode
test_task_plan_tmpl_exec_mode_marker

report_results "speed-mode"
