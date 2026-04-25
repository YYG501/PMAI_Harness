#!/usr/bin/env bash
# skill-preamble.sh — 统一 preamble，所有 skill 的 preamble 调用它
# 用法: source .claude/scripts/skill-preamble.sh
# 输出环境变量:
#   MAIN_REPO_ROOT       - 主仓根目录（共享元数据：.runs/、.worktrees/）
#   REPO_ROOT            - 当前 worktree 根目录（业务数据：requirements/、docs/、prototypes/）
#                          向后兼容：如果在 main 分支，REPO_ROOT == MAIN_REPO_ROOT
#   BRANCH               - 当前分支
#   WORKTREE_TYPE        - main / req / task
#   ACTIVE_REQ           - 活跃 req ID（基于当前 worktree 的 requirements/active/）
#   ACTIVE_REQ_STAGE     - 活跃 req 当前 stage
#   ACTIVE_REQ_DIR       - 活跃 req 目录绝对路径
#   ACTIVE_TASK          - 活跃 task stem
#   ACTIVE_TASK_STATUS   - 活跃 task 状态

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
  WORKTREE_TYPE="task"
fi

# --- 4. 读取活跃 req（优先当前 worktree，fallback 主仓） ---
ACTIVE_REQ=""
ACTIVE_REQ_STAGE=""
ACTIVE_REQ_DIR=""

_find_active_req_in() {
  local root="$1"
  local active_dir="$root/requirements/active"
  [ -d "$active_dir" ] || return 1
  for req_dir in "$active_dir"/req-*/; do
    [ -d "$req_dir" ] || continue
    local meta="$req_dir/.req-meta.json"
    [ -f "$meta" ] || continue
    local status
    status=$(python3 -c "import json; print(json.load(open('$meta')).get('status',''))" 2>/dev/null || echo "")
    if [ "$status" = "active" ]; then
      ACTIVE_REQ=$(python3 -c "import json; print(json.load(open('$meta'))['id'])" 2>/dev/null || echo "")
      ACTIVE_REQ_STAGE=$(python3 -c "import json; print(json.load(open('$meta'))['stage'])" 2>/dev/null || echo "")
      ACTIVE_REQ_DIR="${req_dir%/}"
      return 0
    fi
  done
  return 1
}

# req/task worktree 里的 requirements/ 是当前 req 的真相源
# main 分支上的 requirements/ 只包含已 merge 的 req
if [ "$WORKTREE_TYPE" != "main" ]; then
  _find_active_req_in "$CURRENT_WORKTREE_ROOT" || _find_active_req_in "$MAIN_REPO_ROOT"
else
  # v4 A1 修订: main 分支扫主仓 + .worktrees/req-* (Codex C3)
  _find_active_req_in "$MAIN_REPO_ROOT" || {
    for _req_wt in "$MAIN_REPO_ROOT"/.worktrees/req-*; do
      [ -d "$_req_wt" ] || continue
      _find_active_req_in "$_req_wt" && break
    done
  }
fi

# --- 5. 读取活跃 task ---
ACTIVE_TASK=""
ACTIVE_TASK_STATUS=""

if [ -n "$ACTIVE_REQ_DIR" ]; then
  _tasks_dir="$ACTIVE_REQ_DIR/tasks"
  if [ -d "$_tasks_dir" ]; then
    for _tf in "$_tasks_dir"/task-*.md; do
      [ -f "$_tf" ] || continue
      _st=$(grep -m1 '^\*\*状态：\*\*' "$_tf" 2>/dev/null | sed 's/\*\*状态：\*\* //' || true)
      if [ "$_st" = "执行中" ] || [ "$_st" = "待验收" ]; then
        ACTIVE_TASK=$(basename "$_tf" .md)
        ACTIVE_TASK_STATUS="$_st"
        break
      fi
    done
    # 如果没有执行中/待验收的，找待确认的
    if [ -z "$ACTIVE_TASK" ]; then
      for _tf in "$_tasks_dir"/task-*.md; do
        [ -f "$_tf" ] || continue
        _st=$(grep -m1 '^\*\*状态：\*\*' "$_tf" 2>/dev/null | sed 's/\*\*状态：\*\* //' || true)
        if [ "$_st" = "待确认" ]; then
          ACTIVE_TASK=$(basename "$_tf" .md)
          ACTIVE_TASK_STATUS="$_st"
          break
        fi
      done
    fi
  fi
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

    echo "⚠️ 检测到上次 /$_skill_name 执行中断。运行 /task-status 查看当前状态。"
    rm -f "$_pf"
  done
fi

# --- 6b. Manual 任务等待汇总（非阻塞，汇总式，支持 snooze + 年龄降级） ---
if [ -d "$_PENDING_DIR" ]; then
  _manual_aggregate=$(python3 - "$_PENDING_DIR" <<'PY' 2>/dev/null || echo ""
import glob
import json
import os
import sys
from datetime import datetime, timezone

pending_dir = sys.argv[1]
now = datetime.now(timezone.utc)
total = 0
old = 0
for f in glob.glob(os.path.join(pending_dir, ".pending-manual-*.json")):
    try:
        data = json.load(open(f))
    except Exception:
        continue
    snoozed = data.get("snoozed_until")
    if snoozed:
        try:
            snooze_dt = datetime.fromisoformat(snoozed)
            if snooze_dt.tzinfo is None:
                snooze_dt = snooze_dt.replace(tzinfo=timezone.utc)
            if snooze_dt > now:
                continue
        except Exception:
            pass
    total += 1
    started = data.get("started_at", "")
    if started:
        try:
            s = datetime.fromisoformat(started)
            if s.tzinfo is None:
                s = s.replace(tzinfo=timezone.utc)
            age_days = (now - s).days
            if age_days > 7:
                old += 1
        except Exception:
            pass
print(f"{total}\t{old}")
PY
  )
  _manual_total=$(echo "$_manual_aggregate" | awk '{print $1}')
  _manual_old=$(echo "$_manual_aggregate" | awk '{print $2}')
  if [ -n "$_manual_total" ] && [ "$_manual_total" != "0" ] 2>/dev/null; then
    if [ "${_manual_old:-0}" != "0" ] 2>/dev/null && [ "${_manual_old:-0}" -gt 0 ] 2>/dev/null; then
      echo "⚠️  有 $_manual_total 个 manual task 等待中（$_manual_old 个超过 7 天）。运行 /task-status 查看详情。"
    else
      echo "ℹ️  有 $_manual_total 个 manual task 等待中。运行 /task-status 查看详情。"
    fi
  fi
fi

# --- 6c. quick-fix 残留 worktree 提醒（非阻塞） ---
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
    echo "可运行 /quick-fix --cleanup 清理。"
  fi
fi

# --- 7. 输出环境信息 ---
echo "MAIN_REPO_ROOT: $MAIN_REPO_ROOT"
echo "REPO_ROOT: $REPO_ROOT"
echo "BRANCH: $BRANCH"
echo "WORKTREE_TYPE: $WORKTREE_TYPE"
[ -n "$ACTIVE_REQ" ] && echo "ACTIVE_REQ: $ACTIVE_REQ (stage $ACTIVE_REQ_STAGE)"
[ -n "$ACTIVE_TASK" ] && echo "ACTIVE_TASK: $ACTIVE_TASK ($ACTIVE_TASK_STATUS)"

# v4 A1 修订: 主窗口兜底收口 — preamble 输出 task 概览摘要 (Codex C2)
# 单窗口 lifecycle 下作为兜底 (主路径在新窗口完成验收 + close)
if [ -n "$ACTIVE_REQ" ] || ls "$MAIN_REPO_ROOT"/.worktrees/req-* >/dev/null 2>&1; then
  python3 "$MAIN_REPO_ROOT/.claude/scripts/status-view.py" --summary 2>/dev/null || true
fi

export MAIN_REPO_ROOT REPO_ROOT CURRENT_WORKTREE_ROOT BRANCH WORKTREE_TYPE
export ACTIVE_REQ ACTIVE_REQ_STAGE ACTIVE_REQ_DIR ACTIVE_TASK ACTIVE_TASK_STATUS
