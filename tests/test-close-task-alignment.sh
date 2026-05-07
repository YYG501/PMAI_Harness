#!/usr/bin/env bash
# close-task 步骤 0「task 文档 ↔ 原型对齐」契约测试
#
# 验证：
# 1. close-task SKILL 含步骤 0（在 ## Workflow 后、步骤 1 前）
# 2. 步骤 0 含 0.1/0.2/0.3/0.4/0.5 子节
# 3. 步骤 0 PM 三选一含 Y / R / skip
# 4. 步骤 0 patch 必须 commit 到 task 分支（不是 req 分支）
# 5. Rules 含「步骤 0 N=0 或全 skip 不阻塞」
# 6. Rules 含「PM 选 R 但要在本阶段改代码 → 拒绝」
# 7. description 提及「对齐 task 文档与原型」
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLOSE_TASK_SKILL="$REPO_ROOT/skills/close-task/SKILL.md"

# -----------------------------------------------------------------

test_step_0_exists() {
  start_test "close-task SKILL 含步骤 0「task 文档 ↔ 原型对齐」"
  if ! grep -q "### 步骤 0：task 文档 ↔ 原型对齐" "$CLOSE_TASK_SKILL"; then
    _fail "缺少 ### 步骤 0：task 文档 ↔ 原型对齐 标题"
    return
  fi
  pass_test
}

test_step_0_subsections() {
  start_test "步骤 0 含 0.1/0.2/0.3/0.4/0.5 子节"
  for sub in "#### 0.1" "#### 0.2" "#### 0.3" "#### 0.4" "#### 0.5"; do
    if ! grep -q -F "$sub" "$CLOSE_TASK_SKILL"; then
      _fail "缺少子节 $sub"
      return
    fi
  done
  pass_test
}

test_step_0_three_choice() {
  start_test "步骤 0 PM 三选一含 Y / R / skip"
  for marker in "**Y**" "**R**" "**skip**"; do
    if ! grep -q -F "$marker" "$CLOSE_TASK_SKILL"; then
      _fail "PM 三选一缺少标记 $marker"
      return
    fi
  done
  pass_test
}

test_step_0_commits_to_task_branch() {
  start_test "步骤 0 patch 用 git -C \$TASK_WORKTREE（落 task 分支，不是 req 分支）"
  # 0.4 节里必须出现 git -C "$TASK_WORKTREE"
  if ! awk '/#### 0.4/,/#### 0.5/' "$CLOSE_TASK_SKILL" | grep -q -F 'git -C "$TASK_WORKTREE"'; then
    _fail "0.4 节应使用 git -C \$TASK_WORKTREE 在 task 分支落 commit"
    return
  fi
  pass_test
}

test_rules_has_n_zero_skip_no_block() {
  start_test "Rules 含「N=0 或全 skip 不阻塞 close-task」"
  if ! awk '/^## Rules/{flag=1;next} /^## /{flag=0} flag' "$CLOSE_TASK_SKILL" | grep -q -F "N=0 或全 skip 不阻塞"; then
    _fail "Rules 应含「N=0 或全 skip 不阻塞」"
    return
  fi
  pass_test
}

test_rules_rejects_in_step_code_change() {
  start_test "Rules 含「PM 选 R 但要本阶段改代码 → 拒绝」"
  if ! awk '/^## Rules/{flag=1;next} /^## /{flag=0} flag' "$CLOSE_TASK_SKILL" | grep -q "选 R 但要在本阶段改代码"; then
    _fail "Rules 应明确拒绝 close-task 阶段直接改代码（防 mini task-execute）"
    return
  fi
  pass_test
}

test_description_mentions_alignment() {
  start_test "description 提及「对齐 task 文档与原型」"
  # frontmatter 在文件开头
  if ! head -10 "$CLOSE_TASK_SKILL" | grep -q "对齐 task 文档与原型"; then
    _fail "frontmatter description 应提及「对齐 task 文档与原型」"
    return
  fi
  pass_test
}

test_step_0_before_step_1() {
  start_test "步骤 0 出现在步骤 1 之前"
  step_0_line=$(grep -n "^### 步骤 0：" "$CLOSE_TASK_SKILL" | head -1 | cut -d: -f1)
  step_1_line=$(grep -n "^### 步骤 1：" "$CLOSE_TASK_SKILL" | head -1 | cut -d: -f1)
  if [ -z "$step_0_line" ] || [ -z "$step_1_line" ]; then
    _fail "步骤 0 或步骤 1 标题缺失"
    return
  fi
  if [ "$step_0_line" -ge "$step_1_line" ]; then
    _fail "步骤 0 (line $step_0_line) 应出现在步骤 1 (line $step_1_line) 之前"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run

test_step_0_exists
test_step_0_subsections
test_step_0_three_choice
test_step_0_commits_to_task_branch
test_rules_has_n_zero_skip_no_block
test_rules_rejects_in_step_code_change
test_description_mentions_alignment
test_step_0_before_step_1

report_results "close-task-alignment"
