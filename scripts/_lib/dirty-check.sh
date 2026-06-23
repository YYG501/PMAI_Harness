#!/usr/bin/env bash
# dirty-check.sh — 文档级 worktree dirty 检查与自动 commit helper
#
# 使用方法：
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_lib/dirty-check.sh"
#
# 暴露函数：
#   list_doc_dirty <worktree> <pathspec...>      # 输出 dirty 文件清单（含 untracked），退出码 0=clean / 1=dirty
#   auto_commit_docs <worktree> <message> <pathspec...>  # 把 pathspec 范围内的改动 git add + commit；零改动时静默跳过
#
# 不变式：I-DC1（pre-dispatch worktree clean）—— 任何把文档从 working tree fork
# 给下游消费（git worktree add / build 派发）的边界，必须先确保对应文档
# 不在 working tree 飘着。"事后 commit 救不回延迟落盘"原则同样适用文档边界。

# 内部：在指定 worktree 下解析 dirty 文件（含 staged / unstaged / untracked）。
# 可选 pathspec 参数收窄范围（pathspec 由 git status 解释）。
_dirty_status_in() {
  local wt="$1"; shift
  if [ ! -d "$wt" ]; then
    return 0
  fi
  if [ "$#" -gt 0 ]; then
    git -C "$wt" status --porcelain -- "$@" 2>/dev/null
  else
    git -C "$wt" status --porcelain 2>/dev/null
  fi
}

# list_doc_dirty <worktree> [<pathspec>...]
# stdout：dirty 文件清单（每行一条，去掉 git status 前缀），逐行原样输出方便上层提示
# 退出码：0 = clean / 1 = dirty
list_doc_dirty() {
  local wt="$1"; shift
  local out
  out=$(_dirty_status_in "$wt" "$@")
  if [ -z "$out" ]; then
    return 0
  fi
  # 去掉 status 前缀两列（'XY '）输出文件路径，便于上层 echo 给 PM 看
  printf '%s\n' "$out" | awk '{ sub(/^.. /, ""); print }'
  return 1
}

# auto_commit_docs <worktree> <message> [<pathspec>...]
# 在 worktree 内 `git add` 指定 pathspec（默认全部）+ `git commit -m <message>`
# 若 add 后没 staged 改动，静默 return 0（noop）
# 退出码：0 = 成功（commit 或 noop） / 非 0 = git 失败
auto_commit_docs() {
  local wt="$1"; shift
  local msg="$1"; shift
  if [ -z "$wt" ] || [ -z "$msg" ]; then
    echo "auto_commit_docs: 用法 auto_commit_docs <worktree> <message> [<pathspec>...]" >&2
    return 2
  fi
  if [ ! -d "$wt" ]; then
    echo "auto_commit_docs: worktree 不存在: $wt" >&2
    return 2
  fi
  if [ "$#" -gt 0 ]; then
    git -C "$wt" add -- "$@" 2>/dev/null || true
  else
    git -C "$wt" add -A 2>/dev/null || true
  fi
  if git -C "$wt" diff --cached --quiet 2>/dev/null; then
    return 0
  fi
  git -C "$wt" commit -q -m "$msg"
}
