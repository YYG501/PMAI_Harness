#!/usr/bin/env bash
# worktree.sh — branch ↔ worktree 物理路径解析 helper
#
# 使用方法：
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_lib/worktree.sh"
#
# 暴露函数：
#   resolve_worktree_path <branch>          # 输出物理路径，找不到 -> 退出码 1
#   list_worktrees_by_branch_prefix <prefix> # 输出多行 "<branch>\t<path>"，按 branch 排序
#
# 设计原则：worktree 物理位置由 git 决定，不假设在 <main-repo>/.worktrees/。
# conductor / 用户自定义路径都能正确解析。

# 内部：解析 git worktree list --porcelain，输出 "<branch>\t<path>" 每行
_worktree_list_pairs() {
  local repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  if [ -z "$repo" ]; then
    return 1
  fi
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { path=substr($0, 10); branch=""; next }
    /^branch refs\/heads\// { branch=substr($0, 19) }
    /^$/ {
      if (branch != "" && path != "") { print branch "\t" path }
      path=""; branch=""
    }
    END {
      if (branch != "" && path != "") { print branch "\t" path }
    }
  '
}

# resolve_worktree_path <branch> [<repo>]
# 输出对应 worktree 的物理路径。找不到时输出空 + 退出码 1。
resolve_worktree_path() {
  local branch="$1"
  local repo="${2:-}"
  if [ -z "$branch" ]; then
    echo "resolve_worktree_path: 缺少 <branch> 参数" >&2
    return 2
  fi
  local path
  path=$(_worktree_list_pairs "$repo" | awk -F'\t' -v b="$branch" '$1 == b { print $2; exit }')
  if [ -z "$path" ]; then
    return 1
  fi
  printf '%s\n' "$path"
}

# list_worktrees_by_branch_prefix <prefix> [<repo>]
# 输出 "<branch>\t<path>" 每行，按 branch 字典序排序。
# 没有匹配时输出空（退出码 0）。
list_worktrees_by_branch_prefix() {
  local prefix="$1"
  local repo="${2:-}"
  if [ -z "$prefix" ]; then
    echo "list_worktrees_by_branch_prefix: 缺少 <prefix> 参数" >&2
    return 2
  fi
  _worktree_list_pairs "$repo" | awk -F'\t' -v p="$prefix" 'index($1, p) == 1' | sort
}
