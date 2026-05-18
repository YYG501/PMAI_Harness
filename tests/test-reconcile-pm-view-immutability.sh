#!/usr/bin/env bash
# 守护 reconcile 流程的 PM 视图不变性硬约束（2026-05-18 req-007 stage 3 事故修复）。
# 核心断言：reconcile / lint 流程禁止往 PM 视图（solution.md / task.md）写入任何 AI 维护性内容。
# 违反 = 触发 hash 自指死循环（hash 算自全文 → 加一行就让 hash 失效 → 下次 reconcile 又加一行）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REQ_SOLUTION_SKILL="$FRAMEWORK_ROOT/skills/req-solution/SKILL.md"
TASK_SPEC_SKILL="$FRAMEWORK_ROOT/skills/task-spec/SKILL.md"
INPUT_FLOW="$FRAMEWORK_ROOT/skills/_shared/pm-view/input-flow.md"
SOLUTION_TMPL="$FRAMEWORK_ROOT/templates/solution.md.tmpl"
TASK_TMPL="$FRAMEWORK_ROOT/templates/task.md.tmpl"

_contains() {
  grep -F -q -- "$2" "$1"
}

_assert_contains() {
  local file="$1" text="$2" desc="$3"
  if _contains "$file" "$text"; then
    return 0
  fi
  _fail "$desc: missing literal '$text' in $file"
  return 1
}

_assert_not_contains() {
  local file="$1" pattern="$2" desc="$3"
  if grep -E -q -- "$pattern" "$file"; then
    _fail "$desc: forbidden pattern '$pattern' found in $file"
    grep -nE -- "$pattern" "$file" >&2
    return 1
  fi
  return 0
}

# ---------- Test 1: req-solution 步骤 R reconcile 禁止动 PM 视图 ----------

test_req_solution_reconcile_no_pm_view_write() {
  start_test "req-solution 步骤 R reconcile 禁止动 solution.md"

  # 残留旧指令检测：原 bug 是 "同步在 solution.md 末尾「📁 历史档案」加一行"
  _assert_not_contains "$REQ_SOLUTION_SKILL" \
    "同步在.*solution\.md.*末尾.*历史档案.*加一行" \
    "reconcile 不应再指示写 PM 视图历史档案" || return
  _assert_not_contains "$REQ_SOLUTION_SKILL" \
    "仅允许在.*历史档案.*append" \
    "硬约束不应再有 'append 一行' 例外" || return

  # 正向断言：明确禁止动 PM 视图任何字节
  _assert_contains "$REQ_SOLUTION_SKILL" \
    "禁止动 \`solution.md\` 一个字节" \
    "reconcile 步骤 R.f 应明示禁止动 PM 视图" || return
  _assert_contains "$REQ_SOLUTION_SKILL" \
    "禁止改 PM 视图主文件一个字节" \
    "硬约束段应明示禁止动一个字节" || return
  _assert_contains "$REQ_SOLUTION_SKILL" \
    "hash 自指会死循环" \
    "禁止项应解释根因（hash 自指）" || return

  pass_test
}

# ---------- Test 2: task-spec 步骤 12.5 同款约束 ----------

test_task_spec_reconcile_no_pm_view_write() {
  start_test "task-spec 步骤 12.5 reconcile 禁止动 task PM 视图"

  _assert_not_contains "$TASK_SPEC_SKILL" \
    "同步在 PM 视图主文件末尾.*历史档案.*加一行" \
    "task-spec reconcile 不应再写 PM 视图历史档案" || return

  _assert_contains "$TASK_SPEC_SKILL" \
    "禁止动 PM 视图主文件一个字节" \
    "task-spec 12.5 应明示禁止动 PM 视图" || return

  pass_test
}

# ---------- Test 3: input-flow.md §9.6.4 权威定义对齐 + 反模式段 ----------

test_input_flow_reconcile_anti_pattern_doc() {
  start_test "input-flow §9.6.4 仅写工程合同 + 反模式段说明"

  _assert_not_contains "$INPUT_FLOW" \
    "PM 视图主文件.*历史档案.*工程合同末尾追加" \
    "§9.6.4 不应再让 reconcile 同时写两个视图" || return

  _assert_contains "$INPUT_FLOW" \
    "反模式：reconcile 不允许动 PM 视图主文件" \
    "§9.6.4 后应有反模式段警示" || return
  _assert_contains "$INPUT_FLOW" \
    "自指死循环" \
    "反模式段应解释自指机制" || return
  _assert_contains "$INPUT_FLOW" \
    "2026-05-18 req-007 stage 3" \
    "反模式段应保留事故案例引用" || return

  pass_test
}

# ---------- Test 4: lint 步骤 hash 不变性硬约束（req-solution + task-spec 同款） ----------

test_lint_step_hash_immutability_enforced() {
  start_test "lint 步骤加 PRE/POST hash 自检（PM 决策 = binding）"

  _assert_contains "$REQ_SOLUTION_SKILL" \
    "PRE_LINT_HASH=" \
    "req-solution 步骤 5.5 应算 lint 前 hash" || return
  _assert_contains "$REQ_SOLUTION_SKILL" \
    "POST_LINT_HASH=" \
    "req-solution 步骤 5.5 应算 lint 后 hash" || return
  _assert_contains "$REQ_SOLUTION_SKILL" \
    "hash 不变性硬约束" \
    "req-solution 步骤 5.5 应有硬约束段标题" || return
  _assert_contains "$REQ_SOLUTION_SKILL" \
    "不能凌驾 PM 决策" \
    "req-solution 步骤 5.5 应禁顺手 normalize" || return

  _assert_contains "$TASK_SPEC_SKILL" \
    "PRE_LINT_HASH=" \
    "task-spec 步骤 10.5 应算 lint 前 hash" || return
  _assert_contains "$TASK_SPEC_SKILL" \
    "POST_LINT_HASH=" \
    "task-spec 步骤 10.5 应算 lint 后 hash" || return
  _assert_contains "$TASK_SPEC_SKILL" \
    "hash 不变性硬约束" \
    "task-spec 步骤 10.5 应有硬约束段标题" || return

  pass_test
}

# ---------- Test 5: 模板有用途约束注释 ----------

test_template_changelog_usage_comment() {
  start_test "solution.md / task.md 模板有变更记录用途约束注释"

  _assert_contains "$SOLUTION_TMPL" \
    "变更记录用途约束" \
    "solution.md.tmpl 应有用途约束注释" || return
  _assert_contains "$SOLUTION_TMPL" \
    "AI 维护性动作" \
    "solution.md.tmpl 应明示 AI 维护性动作禁止写入" || return
  _assert_contains "$SOLUTION_TMPL" \
    "lint normalize / reconcile" \
    "solution.md.tmpl 应列具体禁止动作" || return

  _assert_contains "$TASK_TMPL" \
    "AI 维护性动作" \
    "task.md.tmpl 历史档案段应明示 AI 维护性动作禁止写入" || return
  _assert_contains "$TASK_TMPL" \
    "reconcile / hash 对齐" \
    "task.md.tmpl 应列具体禁止动作" || return

  pass_test
}

# ---------- Test 6: 端到端：模拟 reconcile 流程的 hash 稳定性 ----------

test_reconcile_idempotent_hash_stability_e2e() {
  start_test "端到端：reconcile 修改 engineering.md 后 solution.md hash 必须稳定"

  local tmpdir
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/reconcile-test.XXXXXX")
  trap 'rm -rf "$tmpdir"' RETURN

  # 模拟 first-gen：PM 视图 + 工程合同（hash 对齐）
  cat > "$tmpdir/solution.md" <<'EOF'
# Solution — test
## 1. 方案摘要
最初的方案内容。

## 📁 历史档案
### 变更记录
| 日期 | 变更内容 | 负责人 |
|---|---|---|
| 2026-05-18 | 初稿 | tester |
EOF
  local pm_hash_v1
  pm_hash_v1=$(shasum -a 256 "$tmpdir/solution.md" | cut -c1-12)

  cat > "$tmpdir/solution.engineering.md" <<EOF
# Solution Engineering — test
<!-- synced_pm_view_hash: $pm_hash_v1 -->
## 1. 数据结构
最初的工程内容。
EOF

  # 模拟 PM 改 solution.md（加章节）→ hash 必然变
  cat >> "$tmpdir/solution.md" <<'EOF'

## 2. 新增方案章节
PM 主动加的内容。
EOF
  local pm_hash_v2
  pm_hash_v2=$(shasum -a 256 "$tmpdir/solution.md" | cut -c1-12)

  if [ "$pm_hash_v1" = "$pm_hash_v2" ]; then
    _fail "fixture sanity: PM 改 solution.md 后 hash 应变化"
    return 1
  fi

  # 模拟 reconcile 标准动作（修法版）：只动工程合同，PM 视图 0 改动
  # a) 改 engineering 顶部 hash
  sed -i.bak "s/synced_pm_view_hash: $pm_hash_v1/synced_pm_view_hash: $pm_hash_v2/" \
    "$tmpdir/solution.engineering.md"
  rm "$tmpdir/solution.engineering.md.bak"
  # b) 追加 reconcile 注释行到 engineering 末尾
  echo "<!-- reconcile 2026-05-18 12:00: $pm_hash_v1 → $pm_hash_v2; 变更范围: 新增 §2 -->" \
    >> "$tmpdir/solution.engineering.md"

  # 关键断言：reconcile 后 solution.md hash 必须仍 == pm_hash_v2（即 reconcile 没动 PM 视图）
  local pm_hash_v3
  pm_hash_v3=$(shasum -a 256 "$tmpdir/solution.md" | cut -c1-12)
  if [ "$pm_hash_v2" != "$pm_hash_v3" ]; then
    _fail "reconcile 后 solution.md hash 不应变化（v2=$pm_hash_v2, post-reconcile=$pm_hash_v3）"
    return 1
  fi

  # 再跑一次 reconcile（无 PM 改动）：no-op 路径，hash 仍稳定
  local pm_hash_v4
  pm_hash_v4=$(shasum -a 256 "$tmpdir/solution.md" | cut -c1-12)
  if [ "$pm_hash_v3" != "$pm_hash_v4" ]; then
    _fail "二次 reconcile no-op 后 solution.md hash 不应变化"
    return 1
  fi

  pass_test
}

# ---------- Runner ----------

test_req_solution_reconcile_no_pm_view_write
test_task_spec_reconcile_no_pm_view_write
test_input_flow_reconcile_anti_pattern_doc
test_lint_step_hash_immutability_enforced
test_template_changelog_usage_comment
test_reconcile_idempotent_hash_stability_e2e

report_results "reconcile-pm-view-immutability"
