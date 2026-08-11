#!/usr/bin/env bash
# test-todo-guidance.sh
#
# 验证 TODO「PM 待办池」语义引导覆盖到位（PM 反馈：AI 不该替我反推填充 / 排序）：
#   T1: TODO 模板明确是 PM 待办池（不是 ROADMAP）
#   T2: TODO 模板含三态 todo / doing / done（无序池三态，不是 planned/active/done）
#   T3: TODO 模板明写 AI 不反推填充（不从代码/竞品/历史归档反推）
#   T4: TODO 模板不再含"排序"列 / "历史 + 未来一张表" / "唯一规划视图"旧反模式
#   T5: record 只补录 PM 已确认的无序待办，不再把 TODO 包装成路线规划
#
# 背景：PM 反馈 brownfield 方向讨论时 AI 从代码/竞品反推出一串待做项还替 PM 排好顺序，
# 是 PM 没要的。ROADMAP「历史+未来一张表 / 排序 / 扫 closed 补 done 行」整套被砍，
# 改成 TODO 无序待办池：只记 PM 提过/讨论过想做的，AI 不反推填充、不排序。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECORD_SKILL="$REPO_ROOT/skills/record/SKILL.md"
RECORD_ROUTING="$REPO_ROOT/skills/_shared/record-routing.md"
TODO_TEMPLATE="$REPO_ROOT/templates/TODO.md.tmpl"

# -----------------------------------------------------------------
test_todo_template_is_todo_pool() {
  start_test "T1: TODO 模板含 PM 待办池语义"
  if ! grep -q 'PM 待办池' "$TODO_TEMPLATE"; then
    _fail "TODO 模板缺 PM 待办池语义"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_todo_template_lists_states() {
  start_test "T2: TODO 模板含三态 todo / doing / done"
  for state in todo doing done; do
    if ! grep -qE "(^|[^a-z])$state([^a-z]|$)" "$TODO_TEMPLATE"; then
      _fail "TODO 模板缺待办池三态之一: $state"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
test_todo_template_says_no_backfill() {
  start_test "T3: TODO 模板明写 AI 不反推填充"
  if ! grep -q '不.*反推填充' "$TODO_TEMPLATE"; then
    _fail "TODO 模板缺 AI 不反推填充硬规则"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_todo_template_drops_old_antipatterns() {
  start_test "T4: TODO 模板去掉旧路线规划反模式"
  for bad in '历史 + 未来一张表' '唯一规划视图' '排序（数字小先做'; do
    if grep -qF "$bad" "$TODO_TEMPLATE"; then
      _fail "TODO 模板仍含旧反模式: ${bad}"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
test_record_only_adds_confirmed_unordered_todo() {
  start_test "T5: record 只补录已确认的无序待办"
  local row
  row=$(grep -E '^\| 明确后续事项' "$RECORD_ROUTING" || true)
  if [ -z "$row" ]; then
    _fail "record 找不到已确认后续事项的 TODO 路由"
    return
  fi
  if grep -qE '路线规划|季度规划|半年规划' "$RECORD_SKILL"; then
    _fail "record 不应把 TODO 补录包装成路线规划"
    return
  fi
  if ! echo "$row" | grep -q 'TODO' || ! grep -q 'TODO 保持无序' "$RECORD_SKILL"; then
    _fail "record 应明确只写入无序 TODO 且不排序"
    return
  fi
  if ! grep -q '没有 active work' "$TODO_TEMPLATE" \
     || ! grep -q 'PM 明确说「记一下」' "$TODO_TEMPLATE" \
     || ! grep -q '不替 PM 排优先级' "$TODO_TEMPLATE"; then
    _fail "TODO 模板应把 record 限定为无 active work 下的明确补录"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_todo_template_is_todo_pool
test_todo_template_lists_states
test_todo_template_says_no_backfill
test_todo_template_drops_old_antipatterns
test_record_only_adds_confirmed_unordered_todo

report_results "todo-guidance"
