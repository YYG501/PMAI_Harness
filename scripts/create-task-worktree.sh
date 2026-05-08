#!/usr/bin/env bash
# create-task-worktree.sh — Create a task-level worktree with dependency symlinks and port allocation
# Usage: bash create-task-worktree.sh <task-file> <req-branch>
# Example: bash create-task-worktree.sh requirements/active/req-001/tasks/task-001-auth-ui.md req-001-user-auth
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_setup-deps.sh"
source "$SCRIPT_DIR/_lib/worktree.sh"

usage() {
  echo "用法: bash create-task-worktree.sh <task-file> <req-branch>" >&2
  echo "例如: bash create-task-worktree.sh requirements/active/req-001/tasks/task-001-auth-ui.md req-001-user-auth" >&2
  exit 1
}

if [ $# -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  usage
fi

TASK_FILE="$1"
REQ_BRANCH="$2"

# --- Validate task file ---
if [ ! -f "$TASK_FILE" ]; then
  echo "错误：task 文件不存在: $TASK_FILE" >&2
  exit 1
fi

# --- Find the real repo root ---
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -z "$GIT_COMMON_DIR" ]; then
  echo "错误：当前目录不在 git 仓库中" >&2
  exit 1
fi

GIT_COMMON_DIR=$(cd "$GIT_COMMON_DIR" && pwd)

if [[ "$GIT_COMMON_DIR" == */.git ]]; then
  REPO_ROOT="${GIT_COMMON_DIR%/.git}"
else
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi

if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  echo "错误：无法确定主仓库根目录" >&2
  exit 1
fi

# --- Extract task ID from filename (strip .md) ---
TASK_BASENAME=$(basename "$TASK_FILE" .md)

# Add task- prefix if not already present
if [[ "$TASK_BASENAME" == task-* ]]; then
  BRANCH="$TASK_BASENAME"
else
  BRANCH="task-${TASK_BASENAME}"
fi

WORKTREE_DIR="${PM_AI_WORKTREE_BASE:-${REPO_ROOT}/.worktrees}/${BRANCH}"

# --- Validate req branch exists ---
if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$REQ_BRANCH" 2>/dev/null; then
  echo "错误：req 分支不存在: $REQ_BRANCH" >&2
  exit 1
fi

# --- Create worktree (idempotent) ---
# 先问 git：branch 是否已 attached 任何 worktree（不假设在 .worktrees/）。
EXISTING_WT=$(resolve_worktree_path "$BRANCH" "$REPO_ROOT" || true)
if [ -n "$EXISTING_WT" ] && [ -d "$EXISTING_WT" ]; then
  # 已存在 worktree（可能在 .worktrees/、conductor 路径、或自定义位置），直接复用。
  WORKTREE_DIR="$EXISTING_WT"
else
  mkdir -p "$(dirname "$WORKTREE_DIR")"

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    git -C "$REPO_ROOT" worktree add "$WORKTREE_DIR" "$BRANCH"
  else
    git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WORKTREE_DIR" "$REQ_BRANCH"
  fi
fi

setup_dependency_symlinks "$REPO_ROOT" "$WORKTREE_DIR"

# 4.5f：fork 时 worktree == req 分支，drift = 0，无需预 sync。
# task-execute 入口步骤 2.4 会跑 check-req-doc-drift.sh，PM 决定是否拉
# req 分支后续变更。

# ======================================================
# v4.5：把 task md 从 req 分支移走，task 分支独家所有
# ======================================================
# 改造背景：v4 task md 双份共存（req 分支 placeholder + task 分支真本）
# 导致 close-task 路径解析赌博。v4.5 改成 task md 只在 task 分支存在；
# req 分支 task-plan.md 仅记 task row。close-task merge 时 task md 自然
# 跟着 task 分支 commit 进入 req 分支作为最终历史档案。
#
# 注：task-spec 阶段（task-confirm 之前）task md 仍在 req 分支，无歧义。
# fork 之后才移走。
ABS_TASK_FILE=$(cd "$(dirname "$TASK_FILE")" && pwd -P)/$(basename "$TASK_FILE")
REQ_WT=$(resolve_worktree_path "$REQ_BRANCH" "$REPO_ROOT" || true)
if [ -n "$REQ_WT" ] && [ -d "$REQ_WT" ]; then
  REQ_WT_REAL=$(cd "$REQ_WT" && pwd -P)
  if [[ "$ABS_TASK_FILE" == "$REQ_WT_REAL"/* ]]; then
    REL_PATH="${ABS_TASK_FILE#${REQ_WT_REAL}/}"
    ENG_REL="${REL_PATH%.md}.engineering.md"

    TO_RM=()
    if [ -f "$REQ_WT_REAL/$REL_PATH" ]; then
      TO_RM+=("$REL_PATH")
    fi
    if [ -f "$REQ_WT_REAL/$ENG_REL" ]; then
      TO_RM+=("$ENG_REL")
    fi

    if [ ${#TO_RM[@]} -gt 0 ]; then
      (
        cd "$REQ_WT_REAL"
        git rm -q "${TO_RM[@]}" 2>/dev/null || true
        # commit 仅当真有 staged 改动
        if ! git diff --cached --quiet 2>/dev/null; then
          git commit -q -m "task-${TASK_BASENAME#task-}: move task md to task branch (v4.5)"
        fi
      )
    fi
  fi
fi

# ======================================================
# Port allocation
# ======================================================
DEV_PORT=$(derive_task_port "$REPO_ROOT" "$TASK_BASENAME")

# ======================================================
# Output: line 1 = worktree path, line 2 = port
# ======================================================
echo "$WORKTREE_DIR"
echo "$DEV_PORT"
