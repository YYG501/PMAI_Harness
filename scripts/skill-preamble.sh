#!/usr/bin/env bash
# skill-preamble.sh — 统一 preamble，所有 skill 的 preamble 调用它
# 用法: source "$PMAI_HOME/scripts/skill-preamble.sh"（I-mini 模式，推荐）
#       或 source $HOME/.pmai/scripts/skill-preamble.sh（老消费仓 backward compat，不推荐）
# 输出环境变量:
#   PMAI_HOME            - 框架代码根目录（~/.pmai/ 或 env 覆盖），I-mini 后 skill 内部用此路径调脚本
#   MAIN_REPO_ROOT       - 主仓根目录（共享元数据：.runs/、.worktrees/）
#   REPO_ROOT            - 当前 worktree 根目录（业务数据：requirements/、docs/、prototypes/）
#                          向后兼容：如果在 main 分支，REPO_ROOT == MAIN_REPO_ROOT
#   BRANCH               - 当前分支
#   WORKTREE_TYPE        - main / req / legacy-task
#   ACTIVE_REQ           - 活跃 req ID（cwd 唯一确定 req 时设值；main + 多 active 时留空）
#   ACTIVE_REQ_STAGE     - 活跃 req 当前 stage（同 ACTIVE_REQ 的留空规则）
#   ACTIVE_REQ_DIR       - 活跃 req 目录绝对路径（同上）
#   ACTIVE_REQ_COUNT     - 检测到的 active req 数量（0 / 1 / 多）
#
# 多 active req 语义：
#   - 在 req worktree 里：cwd 唯一确定 req，ACTIVE_REQ 必单值
#   - 在主仓 main：可能有 0/1/多 active req
#       0: 三个变量空
#       1: ACTIVE_REQ 单值（同旧行为）
#       多: ACTIVE_REQ 留空（不要默选第一个），输出列出所有候选
#         skill 自己判断 ACTIVE_REQ_COUNT，决定报错或让 PM 进具体 worktree

# --- -1. 解析 PMAI_HOME（I-mini 入口，skill 后续都用它）---
# 顺序：env 显式覆盖 → 本脚本所在目录推导（开发本仓内跑 / clone 到 ~/.pmai/ 都对）→ ~/.pmai fallback
if [ -n "${PMAI_HOME:-}" ] && [ -d "$PMAI_HOME/scripts" ]; then
  : # PM/外部已显式传，尊重
else
  # 本脚本自身所在目录 = $PMAI_HOME/scripts（无论是 ~/.pmai/scripts 还是开发本仓 scripts）
  _SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _CANDIDATE="$(cd "$_SELF_DIR/.." && pwd)"
  if [ -d "$_CANDIDATE/scripts" ] && [ -d "$_CANDIDATE/templates" ]; then
    PMAI_HOME="$_CANDIDATE"
  elif [ -d "$HOME/.pmai/scripts" ]; then
    PMAI_HOME="$HOME/.pmai"
  else
    echo "❌ PMAI_HOME 解析失败：$HOME/.pmai 不存在且当前脚本路径不像 framework 源。" >&2
    echo "   修复：跑 pmai install 装框架到 ~/.pmai/，或显式 export PMAI_HOME=/path/to/framework" >&2
    return 1 2>/dev/null || exit 1
  fi
fi
export PMAI_HOME

# --- 0. 加载 worktree 解析 helper（branch ↔ 物理路径，问 git，不假设 .worktrees/） ---
if [ -f "$PMAI_HOME/scripts/_lib/worktree.sh" ]; then
  source "$PMAI_HOME/scripts/_lib/worktree.sh"
fi

# --- 1. 检测当前分支 ---
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# --- 2. 区分主仓根目录和当前 worktree 根目录 ---
# MAIN_REPO_ROOT: 主仓（共享 .runs/、.worktrees/）
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  # git-common-dir 是 /path/to/repo/.git 或 /path/to/repo/.git/worktrees/...
  # 需要找到 .git 的父目录
  if [[ "$GIT_COMMON" == */.git ]]; then
    MAIN_REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
  elif [[ "$GIT_COMMON" == */.git/worktrees/* ]]; then
    # git-common-dir 在 worktree 里指向主仓的 .git
    MAIN_REPO_ROOT=$(cd "$GIT_COMMON" && cd .. && pwd)
    # 从 .../.git/worktrees/xxx 回退两层到 .git，再一层到 repo root
    MAIN_REPO_ROOT=$(echo "$GIT_COMMON" | sed 's|/\.git.*||')
  else
    MAIN_REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
  fi
else
  MAIN_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# CURRENT_WORKTREE_ROOT: 当前 worktree（业务数据在这里）
CURRENT_WORKTREE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# 向后兼容：REPO_ROOT 指向当前 worktree（业务数据）
REPO_ROOT="$CURRENT_WORKTREE_ROOT"

# --- 3. 检测 worktree 类型 ---
WORKTREE_TYPE="main"
if [[ "$BRANCH" == req-* ]]; then
  WORKTREE_TYPE="req"
elif [[ "$BRANCH" == task-* ]]; then
  WORKTREE_TYPE="legacy-task"
fi

# --- 4. 读取活跃 req（cwd 优先；main 时可能多 active） ---
ACTIVE_REQ=""
ACTIVE_REQ_STAGE=""
ACTIVE_REQ_DIR=""
ACTIVE_REQ_COUNT=0
_ACTIVE_REQ_IDS=()
_ACTIVE_REQ_DIRS=()
_ACTIVE_REQ_STAGES=()

# 把单个 root 下所有 status=active 的 req 加进候选列表（按 id 去重）
# 批 2 单读：真相源 = docs/modules/<模块>/.req-meta.json（模块名可为中文，不限 req- 前缀）。
_collect_active_reqs_in() {
  local root="$1"
  local modules_dir="$root/docs/modules"
  [ -d "$modules_dir" ] || return 0
  for req_dir in "$modules_dir"/*/; do
    [ -d "$req_dir" ] || continue
    local meta="$req_dir/.req-meta.json"
    [ -f "$meta" ] || continue
    local status id stage
    status=$(python3 -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null || echo "")
    [ "$status" = "active" ] || continue
    id=$(python3 -c "import json; print(json.load(open('$meta'))['id'])" 2>/dev/null || echo "")
    stage=$(python3 -c "import json; print(json.load(open('$meta'))['stage'])" 2>/dev/null || echo "")
    [ -n "$id" ] || continue
    local already=0
    if [ "${#_ACTIVE_REQ_IDS[@]}" -gt 0 ]; then
      for existing in "${_ACTIVE_REQ_IDS[@]}"; do
        [ "$existing" = "$id" ] && { already=1; break; }
      done
    fi
    [ "$already" = "1" ] && continue
    _ACTIVE_REQ_IDS+=("$id")
    _ACTIVE_REQ_DIRS+=("${req_dir%/}")
    _ACTIVE_REQ_STAGES+=("$stage")
  done
}

# req worktree 里 cwd 唯一确定 req（自身 active/ 必只含一个）
# 主仓 main：扫主仓 + 所有 .worktrees/req-*，可能 0/1/多 active
if [ "$WORKTREE_TYPE" != "main" ]; then
  _collect_active_reqs_in "$CURRENT_WORKTREE_ROOT"
  if [ "${#_ACTIVE_REQ_IDS[@]}" -eq 0 ]; then
    _collect_active_reqs_in "$MAIN_REPO_ROOT"
  fi
else
  _collect_active_reqs_in "$MAIN_REPO_ROOT"
  # 通过 git worktree list 遍历所有 attached 的 req-* worktree（不假设在 .worktrees/）
  if command -v list_worktrees_by_branch_prefix >/dev/null 2>&1; then
    while IFS=$'\t' read -r _wt_branch _wt_path; do
      [ -n "$_wt_path" ] && [ -d "$_wt_path" ] && _collect_active_reqs_in "$_wt_path"
    done < <(list_worktrees_by_branch_prefix "req-" "$MAIN_REPO_ROOT" 2>/dev/null)
  else
    # fallback：helper 不可用时退回旧 glob
    for _req_wt in "$MAIN_REPO_ROOT"/.worktrees/req-*; do
      [ -d "$_req_wt" ] || continue
      _collect_active_reqs_in "$_req_wt"
    done
  fi
fi

ACTIVE_REQ_COUNT="${#_ACTIVE_REQ_IDS[@]}"

# 单值兼容：仅 1 个时填 ACTIVE_REQ；多个时留空，强制 skill 走"按 cwd 选 req 或拒绝默选"路径
if [ "$ACTIVE_REQ_COUNT" -eq 1 ]; then
  ACTIVE_REQ="${_ACTIVE_REQ_IDS[0]}"
  ACTIVE_REQ_DIR="${_ACTIVE_REQ_DIRS[0]}"
  ACTIVE_REQ_STAGE="${_ACTIVE_REQ_STAGES[0]}"
fi

# --- 6. 中断恢复检测（使用主仓的 .runs/） ---
_PENDING_DIR="$MAIN_REPO_ROOT/.runs"
if [ -d "$_PENDING_DIR" ]; then
  for _pf in "$_PENDING_DIR"/.pending-*; do
    [ -f "$_pf" ] || continue
    # Skip manual pending files — they have their own aggregation block below
    case "$(basename "$_pf")" in
      .pending-manual-*) continue ;;
    esac
    _skill_name=$(python3 -c "import json; print(json.load(open('$_pf')).get('skill','unknown'))" 2>/dev/null || echo "unknown")
    _started=$(python3 -c "import json; print(json.load(open('$_pf')).get('started_at',''))" 2>/dev/null || echo "")

    # 检查是否超过 24 小时
    if [ -n "$_started" ]; then
      _age=$(python3 -c "
from datetime import datetime, timezone
try:
    started = datetime.fromisoformat('$_started')
    age = (datetime.now(timezone.utc) - started.replace(tzinfo=timezone.utc)).total_seconds()
    print(int(age))
except: print(0)
" 2>/dev/null || echo "0")
      if [ "$_age" -gt 86400 ] 2>/dev/null; then
        rm -f "$_pf"
        continue
      fi
    fi

    echo "⚠️ 检测到上次 /$_skill_name 执行中断。运行 /pmai-status 查看当前状态。"
    rm -f "$_pf"
  done
fi

# --- 6b. quick-fix 残留 worktree 提醒（非阻塞） ---
if [ -d "$MAIN_REPO_ROOT/.worktrees" ]; then
  _quickfix_leftovers=()
  for _qf_wt in "$MAIN_REPO_ROOT"/.worktrees/tmp-quick-*; do
    [ -d "$_qf_wt" ] || continue
    _quickfix_leftovers+=("$_qf_wt")
  done

  if [ "${#_quickfix_leftovers[@]}" -gt 0 ]; then
    echo "⚠️  检测到残留 quick-fix worktree："
    for _qf_wt in "${_quickfix_leftovers[@]}"; do
      echo "  - $_qf_wt"
    done
    echo "可运行 /pmai-quick-fix --cleanup 清理。"
  fi
fi

# --- 7. 输出环境信息 ---
echo "MAIN_REPO_ROOT: $MAIN_REPO_ROOT"
echo "REPO_ROOT: $REPO_ROOT"
echo "BRANCH: $BRANCH"
echo "WORKTREE_TYPE: $WORKTREE_TYPE"
if [ "$ACTIVE_REQ_COUNT" -eq 1 ]; then
  echo "ACTIVE_REQ: $ACTIVE_REQ (stage $ACTIVE_REQ_STAGE)"
elif [ "$ACTIVE_REQ_COUNT" -gt 1 ]; then
  echo "ACTIVE_REQS ($ACTIVE_REQ_COUNT 个并行)："
  for _i in "${!_ACTIVE_REQ_IDS[@]}"; do
    echo "  - ${_ACTIVE_REQ_IDS[$_i]} (stage ${_ACTIVE_REQ_STAGES[$_i]})  →  ${_ACTIVE_REQ_DIRS[$_i]}"
  done
  echo "提示：当前在主仓视角，多 active req 并行 — 操作具体 req 请先 cd 进对应 worktree。"
fi
# 主窗口兜底收口：preamble 输出当前需求摘要。
if [ -n "$ACTIVE_REQ" ] || ls "$MAIN_REPO_ROOT"/.worktrees/req-* >/dev/null 2>&1; then
  python3 "$PMAI_HOME/scripts/status-view.py" --summary 2>/dev/null || true
fi

export MAIN_REPO_ROOT REPO_ROOT CURRENT_WORKTREE_ROOT BRANCH WORKTREE_TYPE
export ACTIVE_REQ ACTIVE_REQ_STAGE ACTIVE_REQ_DIR ACTIVE_REQ_COUNT
