#!/usr/bin/env bash
# v4.5 task md 所有权契约测试
#
# 验证：
# 1. create-task-worktree.sh 在 fork 后从 req 分支移走 task md（v4.5 标记）
# 2. close-task.sh 在 merge 前"认回" task md 防 modify/delete 冲突
# 3. task-confirm SKILL 文档化 v4.5 行为（task 分支独家所有）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CREATE_WT_SCRIPT="$REPO_ROOT/scripts/create-task-worktree.sh"
CLOSE_TASK_SCRIPT="$REPO_ROOT/scripts/close-task.sh"
TASK_CONFIRM_SKILL="$REPO_ROOT/skills/task-confirm/SKILL.md"

# -----------------------------------------------------------------

test_create_wt_removes_task_md_from_req() {
  start_test "create-task-worktree.sh fork 后从 req 分支删 task md（v4.5）"
  if ! grep -q "v4.5" "$CREATE_WT_SCRIPT"; then
    _fail "create-task-worktree.sh 缺少 v4.5 标记"
    return
  fi
  if ! grep -q "git rm" "$CREATE_WT_SCRIPT"; then
    _fail "create-task-worktree.sh 应含 git rm 操作"
    return
  fi
  if ! grep -q "move task md to task branch" "$CREATE_WT_SCRIPT"; then
    _fail "create-task-worktree.sh 应含「move task md to task branch」commit message"
    return
  fi
  pass_test
}

test_close_task_reclaims_task_md_before_merge() {
  start_test "close-task.sh merge 前认回 task md 防 modify/delete 冲突"
  if ! grep -q "reclaim task md from" "$CLOSE_TASK_SCRIPT"; then
    _fail "close-task.sh 应含「reclaim task md from」逻辑"
    return
  fi
  if ! grep -q "modify/delete" "$CLOSE_TASK_SCRIPT"; then
    _fail "close-task.sh 应注释提及 modify/delete 冲突场景"
    return
  fi
  pass_test
}

test_task_confirm_skill_documents_v45() {
  start_test "task-confirm SKILL 文档化 task md 分支独家所有行为"
  # fork 后从 req 分支删 task 文件 —— 描述措辞 v3 重写后不再带字面 "v4.5" 标
  if ! grep -q "自动把 task 文件从 req 分支删除" "$TASK_CONFIRM_SKILL"; then
    _fail "task-confirm SKILL 应说明 fork 后自动从 req 分支删 task 文件"
    return
  fi
  if ! grep -q "task 分支独家所有" "$TASK_CONFIRM_SKILL"; then
    _fail "task-confirm SKILL 应明确「task 分支独家所有」"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run

test_create_wt_removes_task_md_from_req
test_close_task_reclaims_task_md_before_merge
test_task_confirm_skill_documents_v45

report_results "task-md-ownership"
