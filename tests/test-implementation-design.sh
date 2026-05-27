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

test_skill_exists_stage5() {
  start_test "/pmai-implementation-design skill 存在 + stage 5 拆 task 前产出"
  local ok=1
  [ -f "$SKILL" ] || { _fail "skills/implementation-design/SKILL.md 不存在"; ok=0; }
  if [ "$ok" = 1 ]; then
    _has "$SKILL" "implementation-design.md" || { _fail "skill 未声明产物"; ok=0; }
    _has "$SKILL" "HOW-ID" || { _fail "skill 未定义 HOW-ID 消费契约"; ok=0; }
    grep -q "DESIGN.md" "$SKILL" || { _fail "skill 输入未含 DESIGN.md 组件 inventory"; ok=0; }
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

test_stage_gate_wiring() {
  start_test "req-stage-gate Stage 4→5 接 /pmai-implementation-design + speed mode 决策门 + Stage 5→6 gate"
  local ok=1
  _has "$STAGE_GATE" "/pmai-implementation-design" || { _fail "Stage 4→5 未调 /pmai-implementation-design"; ok=0; }
  # speed mode（2026-05-26）后取代原"implementation-design 待确认"全文门：
  # 没有结构决策时直进 5b；有结构决策时逐行 prompt。校验关键文案二选一即可。
  _has "$STAGE_GATE" "implementation-design PM 决策门" \
    || _has "$STAGE_GATE" "命中结构决策" \
    || { _fail "缺 implementation-design PM 决策门 / 结构决策 prompt（speed mode）"; ok=0; }
  grep -q "检查 .implementation-design.md. 存在" "$STAGE_GATE" \
    || _has "$STAGE_GATE" "implementation-design.md\` 存在" \
    || { _fail "Stage 5→6 未检查 implementation-design.md 存在"; ok=0; }
  [ "$ok" = 1 ] && pass_test
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
test_skill_exists_stage5
test_pm_view_lint_skips
test_stage_gate_wiring
test_no_solution_engineering_residual

report_results "implementation-design (delta-8)"
