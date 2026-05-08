#!/usr/bin/env bash
# create-req-worktree.sh — Create a req-level worktree
# Usage: bash create-req-worktree.sh <req-id>
# Example: bash create-req-worktree.sh req-001-user-auth
set -euo pipefail

usage() {
  echo "用法: bash create-req-worktree.sh <req-id>" >&2
  echo "例如: bash create-req-worktree.sh req-001-user-auth" >&2
  exit 1
}

if [ $# -lt 1 ] || [ -z "$1" ]; then
  usage
fi

REQ_ID="$1"

# --- Find the real repo root (not the worktree root) ---
# git rev-parse --git-common-dir returns the shared .git dir,
# which for worktrees points to the main repo's .git directory.
GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null || true)
if [ -z "$GIT_COMMON_DIR" ]; then
  echo "错误：当前目录不在 git 仓库中" >&2
  exit 1
fi

# Resolve to absolute path
GIT_COMMON_DIR=$(cd "$GIT_COMMON_DIR" && pwd)

# If GIT_COMMON_DIR ends with /.git, repo root is the parent
if [[ "$GIT_COMMON_DIR" == */.git ]]; then
  REPO_ROOT="${GIT_COMMON_DIR%/.git}"
else
  # Fallback
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi

if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  echo "错误：无法确定主仓库根目录" >&2
  exit 1
fi

# --- Derive branch name ---
if [[ "$REQ_ID" == req-* ]]; then
  BRANCH="$REQ_ID"
else
  BRANCH="req-${REQ_ID}"
fi

WORKTREE_DIR="${PM_AI_WORKTREE_BASE:-${REPO_ROOT}/.worktrees}/${BRANCH}"

# --- Idempotent: 先问 git，branch 是否已 attached worktree（不假设在 .worktrees/） ---
SCRIPT_DIR_RW="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_RW/_lib/worktree.sh"
EXISTING_WT=$(resolve_worktree_path "$BRANCH" "$REPO_ROOT" || true)
if [ -n "$EXISTING_WT" ] && [ -d "$EXISTING_WT" ]; then
  echo "$EXISTING_WT"
  exit 0
fi

# --- Create parent directory ---
mkdir -p "$(dirname "$WORKTREE_DIR")"

# --- Create worktree ---
if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
  # Branch exists, attach worktree to existing branch
  git -C "$REPO_ROOT" worktree add "$WORKTREE_DIR" "$BRANCH"
else
  # Create new branch from main
  git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WORKTREE_DIR" main
fi

# --- Output worktree path ---
echo "$WORKTREE_DIR"
