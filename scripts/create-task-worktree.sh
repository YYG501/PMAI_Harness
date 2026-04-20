#!/usr/bin/env bash
# create-task-worktree.sh — Create a task-level worktree with dependency symlinks and port allocation
# Usage: bash create-task-worktree.sh <task-file> <req-branch>
# Example: bash create-task-worktree.sh requirements/active/req-001/tasks/task-001-auth-ui.md req-001-user-auth
set -euo pipefail

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

WORKTREE_DIR="${REPO_ROOT}/.worktrees/${BRANCH}"

# --- Validate req branch exists ---
if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$REQ_BRANCH" 2>/dev/null; then
  echo "错误：req 分支不存在: $REQ_BRANCH" >&2
  exit 1
fi

# --- Create worktree (idempotent) ---
if [ -d "$WORKTREE_DIR" ] && [ -e "$WORKTREE_DIR/.git" ]; then
  : # Already exists, skip creation
else
  mkdir -p "$(dirname "$WORKTREE_DIR")"

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    git -C "$REPO_ROOT" worktree add "$WORKTREE_DIR" "$BRANCH"
  else
    git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WORKTREE_DIR" "$REQ_BRANCH"
  fi
fi

# ======================================================
# Symlink dependencies
# ======================================================
symlink_if_exists() {
  local src="$1"
  local dst="$2"
  if [ -d "$src" ] && [ ! -e "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
  fi
}

# Detect package manager and symlink dependency directories
if [ -f "$REPO_ROOT/package.json" ]; then
  symlink_if_exists "$REPO_ROOT/node_modules" "$WORKTREE_DIR/node_modules"
fi

if [ -f "$REPO_ROOT/Gemfile" ]; then
  symlink_if_exists "$REPO_ROOT/vendor/bundle" "$WORKTREE_DIR/vendor/bundle"
fi

if [ -f "$REPO_ROOT/go.mod" ]; then
  symlink_if_exists "$REPO_ROOT/vendor" "$WORKTREE_DIR/vendor"
fi

# Handle monorepo: symlink nested node_modules (max depth 4, skip worktrees and nested)
if [ -f "$REPO_ROOT/package.json" ]; then
  find "$REPO_ROOT" -maxdepth 4 -name "node_modules" -type d \
    -not -path "*/.worktrees/*" \
    -not -path "*/node_modules/*/node_modules" \
    2>/dev/null | while read -r nm_path; do
    REL="${nm_path#"$REPO_ROOT"/}"
    TARGET="$WORKTREE_DIR/$REL"
    if [ ! -e "$TARGET" ]; then
      mkdir -p "$(dirname "$TARGET")"
      ln -s "$nm_path" "$TARGET"
    fi
  done
fi

# ======================================================
# Port allocation
# ======================================================
# Base port: md5 hash of project path, mapped to range 3000-9999
BASE_PORT=$(python3 -c "
import hashlib, os
project_path = os.path.realpath('$REPO_ROOT')
h = int(hashlib.md5(project_path.encode()).hexdigest(), 16)
print(3000 + (h % 7000))
" 2>/dev/null || echo "3000")

# Extract task number from filename (e.g., task-001-auth-ui -> 1)
TASK_NUM=$(echo "$TASK_BASENAME" | grep -oE 'task-([0-9]+)' | grep -oE '[0-9]+' | sed 's/^0*//' || true)
if [ -z "$TASK_NUM" ]; then
  TASK_NUM=0
fi

DEV_PORT=$((BASE_PORT + TASK_NUM))

# ======================================================
# Output: line 1 = worktree path, line 2 = port
# ======================================================
echo "$WORKTREE_DIR"
echo "$DEV_PORT"
