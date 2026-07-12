#!/usr/bin/env bash
# skill-preamble.sh — 统一 preamble，所有 skill 的 preamble 调用它
# 用法: source "$PMAI_HOME/scripts/skill-preamble.sh"（I-mini 模式，推荐）
#       或 source $HOME/.pmai/scripts/skill-preamble.sh
# 输出环境变量:
#   PMAI_HOME            - 框架代码根目录（~/.pmai/ 或 env 覆盖），I-mini 后 skill 内部用此路径调脚本
#   MAIN_REPO_ROOT       - 主仓根目录（共享元数据：.runs/、.worktrees/）
#   REPO_ROOT            - 当前 worktree 根目录（业务数据：docs/ 与 project.yml 声明的实现入口）
#   BRANCH               - 当前分支
#   WORKTREE_TYPE        - main / work / legacy-task
#   ACTIVE_WORK          - 活跃工作 ID（cwd 唯一确定工作时设值；main + 多 active 时留空）
#   ACTIVE_WORK_STAGE    - 活跃工作当前阶段（同 ACTIVE_WORK 的留空规则）
#   ACTIVE_WORK_DIR      - 活跃工作目录绝对路径（同上）
#   ACTIVE_WORK_COUNT    - 检测到的 active work 数量（0 / 1 / 多）
#
# 多 active work 语义：
#   - 在工作 worktree 里：cwd 唯一确定工作，ACTIVE_WORK 必单值
#   - 在主仓 main：可能有 0/1/多 active work
#       0: 三个变量空
#       1: ACTIVE_WORK 单值（同旧行为）
#       多: ACTIVE_WORK 留空（不要默选第一个），输出列出所有候选
#         skill 自己判断 ACTIVE_WORK_COUNT，决定报错或让 PM 进具体 worktree

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

REPO_ROOT="$CURRENT_WORKTREE_ROOT"

# --- 2b. 检测当前业务仓是否已接入 PMAI ---
# 用 marker 判断，不用 "docs/ 是否存在"：已有代码库常自带 docs/，但仍未初始化 PMAI。
_pmai_is_generator_repo() {
  [ -f "$REPO_ROOT/scripts/init-project.sh" ]
}

_pmai_file_mentions_pmai() {
  local file="$1"
  [ -f "$file" ] || return 1
  grep -qE 'PMAI|/pmai-' "$file" 2>/dev/null
}

_pmai_has_project_marker() {
  [ -f "$REPO_ROOT/PRODUCT.md" ] && return 0
  [ -f "$REPO_ROOT/PRODUCT-STATE.md" ] && return 0
  [ -f "$REPO_ROOT/docs/CONTEXT.md" ] && return 0
  [ -f "$REPO_ROOT/.pm-workflow/config.yml" ] && return 0
  [ -f "$REPO_ROOT/.codex/hooks.json" ] && return 0
  _pmai_file_mentions_pmai "$REPO_ROOT/AGENTS.md" && return 0
  _pmai_file_mentions_pmai "$REPO_ROOT/CLAUDE.md" && return 0
  return 1
}

PMAI_PROJECT_INITIALIZED=1
if ! _pmai_is_generator_repo && ! _pmai_has_project_marker; then
  PMAI_PROJECT_INITIALIZED=0
fi

# --- 3. 检测 worktree 类型 ---
WORKTREE_TYPE="main"
if [[ "$BRANCH" == build-* ]]; then
  WORKTREE_TYPE="work"
elif [[ "$BRANCH" == task-* ]]; then
  WORKTREE_TYPE="legacy-task"
fi

# --- 4. 读取活跃工作（cwd 优先；main 时可能多 active） ---
ACTIVE_WORK=""
ACTIVE_WORK_STAGE=""
ACTIVE_WORK_DIR=""
ACTIVE_WORK_COUNT=0
_ACTIVE_WORK_IDS=()
_ACTIVE_WORK_DIRS=()
_ACTIVE_WORK_STAGES=()

# 把单个 root 下所有 status=active 的工作加进候选列表（按 id 去重）。
# 真相源 = docs/modules/<模块>/.work-meta.json。
_collect_active_work_in() {
  local root="$1"
  local modules_dir="$root/docs/modules"
  [ -d "$modules_dir" ] || return 0
  for work_dir in "$modules_dir"/*/; do
    [ -d "$work_dir" ] || continue
    local meta="$work_dir/.work-meta.json"
    [ -f "$meta" ] || continue
    local status id stage
    status=$(python3 -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null || echo "")
    [ "$status" = "active" ] || continue
    id=$(python3 -c "import json; print(json.load(open('$meta'))['id'])" 2>/dev/null || echo "")
    stage=$(python3 -c "import json; print(json.load(open('$meta'))['stage'])" 2>/dev/null || echo "")
    [ -n "$id" ] || continue
    local already=0
    if [ "${#_ACTIVE_WORK_IDS[@]}" -gt 0 ]; then
      for existing in "${_ACTIVE_WORK_IDS[@]}"; do
        [ "$existing" = "$id" ] && { already=1; break; }
      done
    fi
    [ "$already" = "1" ] && continue
    _ACTIVE_WORK_IDS+=("$id")
    _ACTIVE_WORK_DIRS+=("${work_dir%/}")
    _ACTIVE_WORK_STAGES+=("$stage")
  done
}

# 工作 worktree 里 cwd 唯一确定工作（自身 active work 优先）。
# 主仓 main：扫主仓 + 所有 attached worktree，可能 0/1/多 active。
if [ "$WORKTREE_TYPE" != "main" ]; then
  _collect_active_work_in "$CURRENT_WORKTREE_ROOT"
  if [ "${#_ACTIVE_WORK_IDS[@]}" -eq 0 ]; then
    _collect_active_work_in "$MAIN_REPO_ROOT"
  fi
else
  _collect_active_work_in "$MAIN_REPO_ROOT"
  # 通过 git worktree list 遍历所有 attached 的 build worktree（不假设在 .worktrees/）
  if command -v list_worktrees_by_branch_prefix >/dev/null 2>&1; then
    while IFS=$'\t' read -r _wt_branch _wt_path; do
      [ -n "$_wt_path" ] && [ -d "$_wt_path" ] && _collect_active_work_in "$_wt_path"
    done < <(list_worktrees_by_branch_prefix "build-" "$MAIN_REPO_ROOT" 2>/dev/null)
  else
    for _work_wt in "$MAIN_REPO_ROOT"/.worktrees/build-*; do
      [ -d "$_work_wt" ] || continue
      _collect_active_work_in "$_work_wt"
    done
  fi
fi

ACTIVE_WORK_COUNT="${#_ACTIVE_WORK_IDS[@]}"

# 仅 1 个时填 ACTIVE_WORK；多个时留空，强制 skill 走"按 cwd 选工作或拒绝默选"路径
if [ "$ACTIVE_WORK_COUNT" -eq 1 ]; then
  ACTIVE_WORK="${_ACTIVE_WORK_IDS[0]}"
  ACTIVE_WORK_DIR="${_ACTIVE_WORK_DIRS[0]}"
  ACTIVE_WORK_STAGE="${_ACTIVE_WORK_STAGES[0]}"
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
echo "PMAI_PROJECT_INITIALIZED: $PMAI_PROJECT_INITIALIZED"
if [ "$PMAI_PROJECT_INITIALIZED" = "0" ]; then
  echo "⚠️ 当前目录还没有 PMAI 初始化。"
  echo "下一步：先发 /pmai-init-project；它会自动判断全新项目 / 已有代码库。"
  echo "在完成初始化或接入前，其它 /pmai-* skill 不应继续写项目产物。"
fi
if [ "$ACTIVE_WORK_COUNT" -eq 1 ]; then
  echo "ACTIVE_WORK: $ACTIVE_WORK (当前进度 $ACTIVE_WORK_STAGE)"
elif [ "$ACTIVE_WORK_COUNT" -gt 1 ]; then
  echo "ACTIVE_WORKS ($ACTIVE_WORK_COUNT 个并行)："
  for _i in "${!_ACTIVE_WORK_IDS[@]}"; do
    echo "  - ${_ACTIVE_WORK_IDS[$_i]} (当前进度 ${_ACTIVE_WORK_STAGES[$_i]})  →  ${_ACTIVE_WORK_DIRS[$_i]}"
  done
  echo "提示：当前在主仓视角，多 active work 并行 — 操作具体工作请先 cd 进对应 worktree。"
fi
# 主窗口兜底收口：preamble 输出当前工作摘要。
if [ -n "$ACTIVE_WORK" ] || ls "$MAIN_REPO_ROOT"/.worktrees/build-* >/dev/null 2>&1; then
  python3 "$PMAI_HOME/scripts/status-view.py" --summary 2>/dev/null || true
fi

export MAIN_REPO_ROOT REPO_ROOT CURRENT_WORKTREE_ROOT BRANCH WORKTREE_TYPE
export PMAI_PROJECT_INITIALIZED
export ACTIVE_WORK ACTIVE_WORK_STAGE ACTIVE_WORK_DIR ACTIVE_WORK_COUNT
