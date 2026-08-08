#!/usr/bin/env bash
# test-todo-guidance.sh
#
# 验证 TODO「PM 待办池」语义引导覆盖到位（PM 反馈：AI 不该替我反推填充 / 排序）：
#   T1: _shared/project-questioning.md §5.2 是 TODO.md（不是 ROADMAP.md），含"待办池"语义
#   T2: §5.2 含三态 todo / doing / done（无序池三态，不是 planned/active/done）
#   T3: §5.2 明写 AI 不反推填充（不从代码/竞品/requirements/pmai-closed 反推）—— 反向断言
#   T4: §5.2 不再含"排序"列 / "历史 + 未来一张表" / "唯一规划视图"旧反模式
#   T5: direction 只承诺无序待办整理，不再把 TODO 包装成路线规划
#
# 背景：PM 反馈 brownfield 方向讨论时 AI 从代码/竞品反推出一串待做项还替 PM 排好顺序，
# 是 PM 没要的。ROADMAP「历史+未来一张表 / 排序 / 扫 closed 补 done 行」整套被砍，
# 改成 TODO 无序待办池：只记 PM 提过/讨论过想做的，AI 不反推填充、不排序。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUESTIONING="$REPO_ROOT/skills/_shared/project-questioning.md"
DIRECTION_SKILL="$REPO_ROOT/skills/direction/SKILL.md"

# §5.2 段提取（到 §5.3 之前）—— 锚点已改 TODO.md
_section_5_2() {
  awk '/^### §5\.2 TODO\.md/,/^### §5\.3/' "$QUESTIONING"
}

# -----------------------------------------------------------------
test_section_5_2_is_todo_pool() {
  start_test "T1: §5.2 是 TODO.md + 含\"待办池\"语义"
  local section
  section=$(_section_5_2)
  if [ -z "$section" ]; then
    _fail "_shared/project-questioning.md 缺 §5.2 TODO.md 段（锚点应为 ### §5.2 TODO.md）"
    return
  fi
  if ! echo "$section" | grep -q '待办池'; then
    _fail "§5.2 缺\"待办池\"语义"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_section_5_2_lists_todo_states() {
  start_test "T2: §5.2 含三态 todo / doing / done"
  local section
  section=$(_section_5_2)
  for state in todo doing done; do
    if ! echo "$section" | grep -qE "\`$state\`"; then
      _fail "§5.2 缺待办池三态之一: \`$state\`"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
test_section_5_2_says_no_backfill() {
  start_test "T3: §5.2 明写 AI 不反推填充（反向断言）"
  local section
  section=$(_section_5_2)
  if ! echo "$section" | grep -q '不.*反推填充'; then
    _fail "§5.2 缺\"AI 不反推填充\"硬规则（防 AI 替 PM 脑补待办队列）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_section_5_2_drops_old_antipatterns() {
  start_test "T4: §5.2 去掉旧反模式（排序列 / 历史+未来一张表 / 唯一规划视图）"
  local section
  section=$(_section_5_2)
  for bad in '历史 + 未来一张表' '唯一规划视图' '排序（数字小先做'; do
    if echo "$section" | grep -qF "$bad"; then
      _fail "§5.2 仍含旧反模式: ${bad}（应已随 TODO 改造删除）"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
test_direction_only_promises_unordered_todo() {
  start_test "T5: direction 只承诺无序待办整理"
  local row
  row=$(grep -E '^\| \*\*待办整理\*\*' "$DIRECTION_SKILL" || true)
  if [ -z "$row" ]; then
    _fail "找不到待办整理表格行"
    return
  fi
  if grep -qE '路线规划|季度规划|半年规划' "$DIRECTION_SKILL"; then
    _fail "direction 仍承诺当前没有产物支撑的路线规划能力"
    return
  fi
  if ! echo "$row" | grep -q 'TODO' || ! echo "$row" | grep -q '不排序'; then
    _fail "待办整理应明确写入无序 TODO 且不排序"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_section_5_2_is_todo_pool
test_section_5_2_lists_todo_states
test_section_5_2_says_no_backfill
test_section_5_2_drops_old_antipatterns
test_direction_only_promises_unordered_todo

report_results "todo-guidance"
