#!/usr/bin/env bash
# delta-9：跨功能产品行为规则 + 设计规范与组件复用 测试
#
# 验证：
# - PRODUCT-RULES.md.tmpl 结构 + 条目含 scope 字段（全局 / 域限定）
# - DESIGN.md.tmpl 升级：布局合约 / 响应式 / 无障碍 / 共享组件 inventory / Checker Sign-Off
# - close-task selective promote（步骤 1.6）+ worktree-clean 白名单含 PRODUCT-RULES.md（D9-4 回归）
# - close-task.sh carry-forward / clean-check 含 docs/PRODUCT-RULES.md（6382baf-class 回归）
# - gap-check 每 req 无条件跑（D9-2）—— req-stage-gate stage 4 必跑
# - task-spec / prd-writing 必读清单含 PRODUCT-RULES.md
# - init-project.sh 分发 PRODUCT-RULES.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PR_TMPL="$REPO_ROOT/templates/PRODUCT-RULES.md.tmpl"
DESIGN_TMPL="$REPO_ROOT/templates/DESIGN.md.tmpl"
CLOSE_TASK="$REPO_ROOT/skills/close-task/SKILL.md"
CLOSE_TASK_SH="$REPO_ROOT/scripts/close-task.sh"
STAGE_GATE="$REPO_ROOT/skills/req-stage-gate/SKILL.md"
TASK_SPEC="$REPO_ROOT/skills/task-spec/SKILL.md"
PRD_WRITING="$REPO_ROOT/skills/prd-writing/SKILL.md"
INIT_PROJECT="$REPO_ROOT/scripts/init-project.sh"
INPUT_FLOW="$REPO_ROOT/skills/_shared/pm-view/input-flow.md"

_has() { grep -F -q -- "$2" "$1"; }

test_product_rules_template() {
  start_test "PRODUCT-RULES.md.tmpl 结构 + scope 字段"
  local ok=1
  [ -f "$PR_TMPL" ] || { _fail "PRODUCT-RULES.md.tmpl 不存在"; ok=0; }
  if [ "$ok" = 1 ]; then
    _has "$PR_TMPL" "跨功能产品行为规则" || { _fail "缺标题语义"; ok=0; }
    _has "$PR_TMPL" "scope：全局 | 域限定" || { _fail "条目缺 scope 字段（全局/域限定）"; ok=0; }
    _has "$PR_TMPL" "来源：req-NNN" || { _fail "条目缺来源字段"; ok=0; }
  fi
  [ "$ok" = 1 ] && pass_test
}

test_design_template_upgrade() {
  start_test "DESIGN.md.tmpl 升级：布局/响应式/无障碍/inventory/Checker"
  local ok=1
  for blk in "布局合约" "响应式" "无障碍" "共享组件 inventory" "Checker Sign-Off" "创意自由度"; do
    _has "$DESIGN_TMPL" "$blk" || { _fail "DESIGN.md.tmpl 缺块: $blk"; ok=0; }
  done
  [ "$ok" = 1 ] && pass_test
}

test_close_task_promote() {
  start_test "close-task 步骤 1.6 PRODUCT-RULES selective promote"
  local ok=1
  _has "$CLOSE_TASK" "PRODUCT-RULES" || { _fail "close-task 未接 PRODUCT-RULES promote"; ok=0; }
  grep -q "步骤 1.6" "$CLOSE_TASK" || { _fail "close-task 缺步骤 1.6"; ok=0; }
  [ "$ok" = 1 ] && pass_test
}

test_worktree_clean_whitelist() {
  start_test "close-task worktree-clean 白名单含 PRODUCT-RULES.md（D9-4 回归）"
  local ok=1
  # SKILL §2.1（白名单 grep -vE 'docs/(DESIGN|PRODUCT-RULES)...'）
  grep -q "DESIGN|PRODUCT-RULES" "$CLOSE_TASK" || { _fail "close-task SKILL §2.1 白名单未含 PRODUCT-RULES.md"; ok=0; }
  # close-task.sh carry-forward + clean-check
  _has "$CLOSE_TASK_SH" "docs/PRODUCT-RULES.md" || { _fail "close-task.sh carry-forward 未含 PRODUCT-RULES.md"; ok=0; }
  grep -q "PRODUCT-RULES" "$CLOSE_TASK_SH" || { _fail "close-task.sh clean-check 未含 PRODUCT-RULES"; ok=0; }
  [ "$ok" = 1 ] && pass_test
}

test_gap_check_every_req() {
  start_test "gap-check 每 req 无条件跑（D9-2）—— stage 4 必跑"
  local ok=1
  _has "$STAGE_GATE" "gap-check" || { _fail "req-stage-gate 缺 gap-check"; ok=0; }
  _has "$STAGE_GATE" "组件复用关口" || { _fail "缺组件复用关口表述"; ok=0; }
  _has "$STAGE_GATE" "必跑 gap-check" || { _fail "未声明 gap-check 必跑"; ok=0; }
  [ "$ok" = 1 ] && pass_test
}

test_readers_wired() {
  start_test "task-spec / prd-writing 必读清单含 PRODUCT-RULES.md"
  local ok=1
  _has "$TASK_SPEC" "PRODUCT-RULES.md" || { _fail "task-spec 未接 PRODUCT-RULES.md"; ok=0; }
  _has "$TASK_SPEC" "scope=全局" || { _fail "task-spec 未按 scope 读"; ok=0; }
  _has "$PRD_WRITING" "PRODUCT-RULES.md" || { _fail "prd-writing 未接 PRODUCT-RULES.md"; ok=0; }
  grep -q "候选跨功能产品规则 promote" "$PRD_WRITING" || { _fail "prd-writing 缺 candidate promote 入口"; ok=0; }
  [ "$ok" = 1 ] && pass_test
}

test_init_project_distributes() {
  start_test "init-project.sh 分发 PRODUCT-RULES.md"
  if _has "$INIT_PROJECT" "PRODUCT-RULES.md)"; then
    pass_test
  else
    _fail "init-project.sh 未分发 PRODUCT-RULES.md"
  fi
}

test_routing_table_collapsed() {
  start_test "input-flow §9.4 收口为 relevance 二分 + 多去向 routing"
  local ok=1
  _has "$INPUT_FLOW" "relevance 二分" || { _fail "§9.4 未含 relevance 二分"; ok=0; }
  _has "$INPUT_FLOW" "PRODUCT-RULES.md" || { _fail "§9.4 routing 未含 PRODUCT-RULES.md"; ok=0; }
  [ "$ok" = 1 ] && pass_test
}

test_product_rules_template
test_design_template_upgrade
test_close_task_promote
test_worktree_clean_whitelist
test_gap_check_every_req
test_readers_wired
test_init_project_distributes
test_routing_table_collapsed

report_results "product-rules + design 升级 (delta-9)"
