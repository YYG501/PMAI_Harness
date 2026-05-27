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

# cleanup_stale_worktrees <repo_root>
# 兜底清理：按 requirements/{active,closed}/*/tasks/task-*.md + requirements/<req-stem>
# 真相源定向枚举，对每个推导出的 worktree 路径（${PM_AI_WORKTREE_BASE:-<repo>/.worktrees}/<stem>）
# 检查是否 git 已不认 + 物理还在 → rm -rf。close-task / close-req 末尾调用。
#
# 不无差别扫 .worktrees/* — path 必须从 task/req 记录推导。
# 护栏：跳过 live worktree、跳过当前 cwd 所在的目录。
cleanup_stale_worktrees() {
  local repo_root="$1"
  if [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; then
    return 0
  fi

  # 先 prune git 索引死引用，确保 worktree list 准确
  git -C "$repo_root" worktree prune 2>/dev/null || true

  local live_paths
  live_paths=$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print substr($0, 10)}')

  local cleaned=0 caller_cwd
  caller_cwd=$(pwd -P 2>/dev/null || echo "")

  # 枚举 requirements/{active,closed}/* 下所有 task + req
  local req_dir task_file stem
  for state_dir in "$repo_root/requirements/active" "$repo_root/requirements/closed"; do
    [ -d "$state_dir" ] || continue
    for req_dir in "$state_dir"/*; do
      [ -d "$req_dir" ] || continue

      # 检查每个 task 的 worktree
      if [ -d "$req_dir/tasks" ]; then
        for task_file in "$req_dir/tasks"/task-*.md; do
          [ -f "$task_file" ] || continue
          case "$task_file" in *.engineering.md) continue ;; esac
          stem=$(basename "$task_file" .md)
          _stale_worktree_check_one "$repo_root" "$stem" "$live_paths" "$caller_cwd" \
            && cleaned=$((cleaned + 1))
        done
      fi

      # 检查 req 自己的 worktree
      stem=$(basename "$req_dir")
      _stale_worktree_check_one "$repo_root" "$stem" "$live_paths" "$caller_cwd" \
        && cleaned=$((cleaned + 1))
    done
  done

  [ "$cleaned" -gt 0 ] && echo "🧹 顺手清掉 $cleaned 个孤儿 worktree（按 task/req 记录定向）"
  return 0
}

# 内部：检查单个 stem 的 worktree 物理路径，孤儿则清。
# 返回 0 = 清掉了，1 = 跳过（live / cwd 在内 / 不存在）。
_stale_worktree_check_one() {
  local repo_root="$1"
  local stem="$2"
  local live_paths="$3"
  local caller_cwd="$4"

  local wt_path="${PM_AI_WORKTREE_BASE:-$repo_root/.worktrees}/$stem"
  [ -d "$wt_path" ] || return 1

  local abs_wt
  abs_wt=$(cd "$wt_path" 2>/dev/null && pwd -P) || return 1

  # live worktree → 跳过
  printf '%s\n' "$live_paths" | grep -qFx "$abs_wt" && return 1

  # cwd 在内 → 跳过（不删自己脚下）
  [ -n "$caller_cwd" ] && [[ "$caller_cwd" == "$abs_wt"* ]] && return 1

  rm -rf "$wt_path"
  return 0
}
