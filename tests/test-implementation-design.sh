#!/usr/bin/env bash
# delta-8：req 级实现设计视图（implementation-design）测试
#
# 验证：
# - skills/implementation-design/templates/implementation-design.md.tmpl 4 段结构 + HOW-ID 可消费 schema
# - /pmai-implementation-design skill 存在 + stage 5 拆 task 前产出契约
# - check-doc-pm-view.py 跳过 implementation-design.md（工程合同格式豁免）
# - req-stage-gate Stage 4→5 编排调 /pmai-implementation-design + PM 确认门 + Stage 5→6 gate 检查文件
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPL="$REPO_ROOT/skills/implementation-design/templates/implementation-design.md.tmpl"
SKILL="$REPO_ROOT/skills/implementation-design/SKILL.md"
STAGE_GATE="$REPO_ROOT/skills/req-stage-gate/SKILL.md"
CHECK_PM="$REPO_ROOT/scripts/check-doc-pm-view.py"

_has() { grep -F -q -- "$2" "$1"; }

test_template_4_segments() {
  start_test "implementation-design.md.tmpl 含 4 段 + HOW-ID schema"
  local ok=1
  for seg in "段 1 · 架构决策表" "段 2 · 文件·模式索引" "段 3 · 约束与验收" "段 4 · 审计与修订记录"; do
    _has "$TMPL" "$seg" || { _fail "缺段: $seg"; ok=0; }
  done
  _has "$TMPL" "HOW-ID" || { _fail "缺 HOW-ID schema"; ok=0; }
  _has "$TMPL" "约束失效条件" || { _fail "段 1 缺「约束失效条件」决策字段"; ok=0; }
  [ "$ok" = 1 ] && pass_test
}

test_skill_is_build_background_helper() {
  start_test "/pmai-implementation-design skill 存在 + 降本 build 后台辅助（不产正式文档）"
  local ok=1
  [ -f "$SKILL" ] || { _fail "skills/implementation-design/SKILL.md 不存在"; ok=0; }
  if [ "$ok" = 1 ]; then
    # 六步降后台后：本 skill 不产正式 implementation-design.md 文档，只做 build 的 AI 后台 HOW context。
    # 旧断言「skill 声明产出 implementation-design.md / 定义 HOW-ID 消费契约」随这两个机制（独立工程文档 + HOW-ID schema）一起砍——
    # 这是契约规则 3「旧机制被砍的断言连测试一起迁/删」。新断言改查降后台语义。
    _has "$SKILL" "不产正式" || { _fail "skill 未声明「不产正式文档」降后台性质"; ok=0; }
    grep -q "DESIGN.md" "$SKILL" || { _fail "skill 输入未含 DESIGN.md 组件 inventory"; ok=0; }
    # 产品口径实现文档（范围清单 + 决策页）的家是 new-req 产的 req-plan.md，本 skill 应指过去
    _has "$SKILL" "req-plan" || { _fail "skill 未把产品口径实现文档指向 task-plan/req-plan"; ok=0; }
    # /pmai-next 驱动（接管被砍的 req-stage-gate 推进）
    _has "$SKILL" "/pmai-next" || { _fail "skill 未由 /pmai-next 驱动"; ok=0; }
  fi
  [ "$ok" = 1 ] && pass_test
}

test_pm_view_lint_skips() {
  start_test "check-doc-pm-view.py 跳过 implementation-design.md"
  local d; d=$(mktemp -d)
  cat > "$d/implementation-design.md" <<'EOF'
# 实现设计 — test
## 段 1 · 架构决策表
用 reducer dispatch props hook TS 类型 LicenseRecord，像素 24px。
EOF
  local out; out=$(python3 "$CHECK_PM" "$d/implementation-design.md" 2>&1)
  local rc=$?
  rm -rf "$d"
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "跳过"; then
    pass_test
  else
    _fail "implementation-design.md 未被跳过 lint: rc=$rc out=$out"
  fi
}

test_no_solution_engineering_residual() {
  start_test "全仓无现役 solution.engineering.md 模板残留"
  if [ -f "$REPO_ROOT/templates/solution.engineering.md.tmpl" ]; then
    _fail "solution.engineering.md.tmpl 应已删除"
  else
    pass_test
  fi
}

test_template_4_segments
test_skill_is_build_background_helper
test_pm_view_lint_skips
test_no_solution_engineering_residual

report_results "implementation-design (delta-8)"
