#!/usr/bin/env bash
# req-num-resolver.sh — req 编号 helper（v5 vp-6 砍 is_first_req）
#
# 关键：必须扫**三个来源**取最大值，不能凭印象只扫文件目录。
# **事实来源是 git 分支**——active req 都在自己分支上，main 分支视角下
# requirements/active/ 通常是空的（active req 没 merge 回 main），只看目录会漏号导致撞号。
#
# 三个来源：
#   1. closed req 目录（main 分支可见，已 merge 的归档）
#   2. active req 目录（main 分支视角通常空，但兜底扫一下）
#   3. git 所有 req-NNN-* 分支（主要来源，包括其他 worktree 里的 active req）
#
# 使用方法：
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_lib/req-num-resolver.sh"
#
# 暴露函数：
#   next_req_num <repo-root>           # 输出下一个可用编号 NNN（3 位 0 padding）
#   list_req_nums <repo-root>          # 输出所有已占编号（去重 sorted）
#
# 直接执行（用作 CLI）：
#   bash scripts/_lib/req-num-resolver.sh next [repo-root]    → echo "001"
#   bash scripts/_lib/req-num-resolver.sh list [repo-root]    → echo "001\n002\n..."
#
# repo-root 不传时取 git rev-parse --show-toplevel。

# -------- 内部：扫三个来源 --------
_scan_req_nums() {
  local repo_root="$1"
  {
    # 1. closed req 目录
    ls -d "$repo_root/requirements/closed/req-"* 2>/dev/null \
      | sed -E 's|.*/req-([0-9]+)-.*|\1|'
    # 2. active req 目录
    ls -d "$repo_root/requirements/active/req-"* 2>/dev/null \
      | sed -E 's|.*/req-([0-9]+)-.*|\1|'
    # 3. git 所有 req-NNN-* 分支
    git -C "$repo_root" for-each-ref --format='%(refname:short)' 'refs/heads/req-*' 2>/dev/null \
      | sed -E 's|.*req-([0-9]+)-.*|\1|'
  } | grep -E '^[0-9]+$' | sort -nu
}

# -------- 公开 API --------

# next_req_num <repo-root>
# 输出 3 位 0 padding 的下一个编号
next_req_num() {
  local repo_root="${1:?repo-root required}"
  local max
  max=$(_scan_req_nums "$repo_root" | tail -1)
  printf '%03d\n' $((${max:-0} + 1))
}

# list_req_nums <repo-root>
# 输出所有已占编号（去重 + 数字升序）
list_req_nums() {
  local repo_root="${1:?repo-root required}"
  _scan_req_nums "$repo_root"
}

# -------- CLI 模式 --------
# 直接执行（不是 source）时走这里
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cmd="${1:-next}"
  repo_root="${2:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  if [ -z "$repo_root" ]; then
    echo "Error: not in a git repo and no repo-root passed" >&2
    exit 2
  fi

  case "$cmd" in
    next)  next_req_num "$repo_root" ;;
    list)  list_req_nums "$repo_root" ;;
    *)     echo "Usage: $0 {next|list} [repo-root]" >&2; exit 2 ;;
  esac
fi
