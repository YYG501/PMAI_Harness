#!/usr/bin/env bash
# close-task.sh — Task 关闭：文档偏差检查 → 归档 → merge → 清理
# 用法: bash .claude/scripts/close-task.sh <task-file>
# 前置条件：task 状态必须为「已完成」

set -euo pipefail

TASK_FILE="${1:?用法: close-task.sh <task-file>}"

# --- 找到真正的主仓根目录（不是 worktree） ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

EVENTS_SCRIPT="$REPO_ROOT/.claude/scripts/task-events.py"

if [ ! -f "$TASK_FILE" ]; then
  echo "❌ task 文件不存在: $TASK_FILE" >&2
  exit 1
fi

# --- 提取 task 元信息字段（兼容旧段落格式 + 新任务卡表格格式） ---
extract_task_field() {
  local file="$1"
  local field="$2"
  local val
  # 旧格式：**字段：** 值
  val=$(grep -m1 "^\*\*${field}：\*\*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}：\*\* +//; s/[ 	]+$//" || true)
  if [ -n "$val" ]; then
    echo "$val"
    return 0
  fi
  # 新格式：| **字段** | 值 |
  val=$(grep -m1 "^|[ 	]*\*\*${field}\*\*[ 	]*|" "$file" 2>/dev/null \
    | sed -E "s/^\|[ 	]*\*\*${field}\*\*[ 	]*\|[ 	]*//; s/[ 	]*\|[ 	]*$//; s/[ 	]+$//" || true)
  echo "$val"
}

# --- 工程合同成对存在（PR 2 拆两文件约定，兼容旧格式 task） ---
ENG_FILE="${TASK_FILE%.md}.engineering.md"
if [ -f "$ENG_FILE" ]; then
  HAS_ENG=true
else
  HAS_ENG=false
  echo "⚠️  工程合同缺失（旧格式 task，按单文件兼容模式继续）：$ENG_FILE" >&2
fi

# --- 校验状态 ---
STATUS=$(extract_task_field "$TASK_FILE" "状态")
if [ "$STATUS" != "已完成" ]; then
  echo "❌ task 状态为「${STATUS}」，不是「已完成」。只有 PM 确认通过后才能关闭。" >&2
  exit 1
fi

# --- 检查文档偏差是否已处理（跨两文件 / 兼容旧格式） ---
collect_diff_section() {
  local file="$1"
  local heading="$2"
  sed -n "/^${heading}/,/^## /{/^${heading}/d;/^## /d;p;}" "$file" \
    | grep -v '^$' \
    | grep -v '^>' \
    | grep -v '^<!--' \
    | grep -v '^|.*文档位置.*文档原文.*实际实现' \
    | grep -v '^|.*---' \
    | grep -v '^---' \
    | grep -v '无偏差' \
    | head -20 || true
}

DOC_DIFF=""
if [ "$HAS_ENG" = "true" ]; then
  # 新格式：偏差主要在工程合同 §10；PM 走查偏差也可能在主文件 📁 历史档案
  DOC_DIFF=$(collect_diff_section "$ENG_FILE" "## 10\\. 文档偏差")
  if [ -z "$DOC_DIFF" ]; then
    # 兼容性 fallback：主文件 ## 文档偏差（旧格式 section 残留）
    DOC_DIFF=$(collect_diff_section "$TASK_FILE" "## 文档偏差")
  fi
else
  # 旧格式：偏差在主文件 ## 文档偏差
  DOC_DIFF=$(collect_diff_section "$TASK_FILE" "## 文档偏差")
fi

if [ -n "$DOC_DIFF" ]; then
  echo "⚠️ 检测到未处理的文档偏差。请先运行 /doc-update 处理偏差后再关闭 task。" >&2
  echo "" >&2
  echo "文档偏差内容：" >&2
  echo "$DOC_DIFF" >&2
  exit 1
fi

# --- 提取分支名 ---
BRANCH=$(extract_task_field "$TASK_FILE" "分支" | sed 's/[ 	].*//')
if [ -z "$BRANCH" ]; then
  echo "⚠️ task 文件中未找到分支名，跳过分支操作。" >&2
fi

TASK_STEM=$(basename "$TASK_FILE" .md)
TASK_TITLE=$(head -1 "$TASK_FILE" | sed 's/^# //')

# --- 确定 req 目录和 req 分支 ---
REQ_DIR=$(echo "$TASK_FILE" | sed 's|/tasks/.*||')
REQ_META="$REQ_DIR/.req-meta.json"
REQ_BRANCH=""
if [ -f "$REQ_META" ]; then
  REQ_BRANCH=$(python3 -c "import json; print(json.load(open('$REQ_META'))['branch'])" 2>/dev/null || true)
fi

# --- 1. 归档推迟到 merge 后，在 req worktree 中做并 commit ---
# （归档必须 commit 到 req 分支，否则在 close-req 清理 worktree 时会丢失）

RUNS_FILE="$REPO_ROOT/.runs/$TASK_STEM.json"
EVENTS_FILE="$REPO_ROOT/.runs/events/$TASK_STEM.jsonl"

# --- 2. 合并 task 分支到 req 分支 ---
# 规则：merge 必须成功才清理。任何前置条件缺失都 exit 1，防止未合并就删除分支（数据丢失）
MERGE_OK=false

if [ -z "$BRANCH" ]; then
  echo "❌ task 文件中未找到分支名，无法安全清理。请检查 task 文件的「分支」字段。" >&2
  exit 1
fi

if ! git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
  echo "❌ task 分支 $BRANCH 不存在。可能已被手动删除。人工检查后再处理。" >&2
  exit 1
fi

if [ -z "$REQ_BRANCH" ]; then
  echo "❌ req 元数据缺失 branch 字段 ($REQ_META)。人工检查后再处理。" >&2
  exit 1
fi

REQ_WORKTREE="$REPO_ROOT/.worktrees/$REQ_BRANCH"
if [ ! -d "$REQ_WORKTREE" ]; then
  echo "❌ req worktree 不存在: ${REQ_WORKTREE}。需要先恢复 req worktree 才能关闭 task。" >&2
  echo "   建议：bash $REPO_ROOT/.claude/scripts/create-req-worktree.sh $REQ_BRANCH" >&2
  exit 1
fi

# --- v4.5 cwd 校验：close-task 必须在 req worktree 内跑（不能在 task worktree 或主仓） ---
# 改造背景：v4 让 close-task 跑在 task worktree → 不能删自己脚下 → 要 pending-cleanup 中转。
# v4.5 改回 req worktree 跑 → 直接删 task worktree + branch，一步关完。
CALLER_PWD="$(pwd -P 2>/dev/null || echo "")"
REQ_WT_REAL="$(cd "$REQ_WORKTREE" && pwd -P)"
if [ "$CALLER_PWD" != "$REQ_WT_REAL" ] && [[ "$CALLER_PWD" != "$REQ_WT_REAL"/* ]]; then
  echo "❌ /close-task 必须在 req worktree cwd 内运行（v4.5）。" >&2
  echo "   当前 cwd: $CALLER_PWD" >&2
  echo "   期望:     $REQ_WT_REAL" >&2
  echo "   请关闭当前 task 窗口，切到 req 窗口（cwd = ${REQ_WT_REAL}）后重新运行 /close-task。" >&2
  exit 1
fi

# --- 检查 task worktree 是否 clean（防止 worktree remove --force 静默丢失未提交改动） ---
TASK_WORKTREE="$REPO_ROOT/.worktrees/$BRANCH"
if [ -d "$TASK_WORKTREE" ]; then
  UNCOMMITTED=$(git -C "$TASK_WORKTREE" status --porcelain 2>/dev/null || true)
  if [ -n "$UNCOMMITTED" ]; then
    echo "❌ task worktree 有未提交改动，不能关闭（worktree remove --force 会丢失数据）：" >&2
    echo "$UNCOMMITTED" >&2
    echo "" >&2
    echo "请先在 task worktree 中提交：" >&2
    echo "  cd $TASK_WORKTREE" >&2
    echo "  git add -A && git commit -m \"wip: <描述>\"" >&2
    echo "然后重新运行 /close-task。" >&2
    exit 1
  fi

  # 检查 task 分支是否有未推到 req 分支的提交（确保 merge 能带走所有提交）
  UNMERGED_COMMITS=$(git -C "$TASK_WORKTREE" log "$REQ_BRANCH..$BRANCH" --oneline 2>/dev/null || true)
  if [ -z "$UNMERGED_COMMITS" ]; then
    # task 分支和 req 分支完全一致，没有新提交。允许继续（可能是空 task 或已手动 merge）
    :
  fi
fi

# --- 检查 req worktree 是否 clean（有未提交改动会导致 merge 被 git 拒绝） ---
REQ_UNCOMMITTED=$(git -C "$REQ_WORKTREE" status --porcelain 2>/dev/null || true)
if [ -n "$REQ_UNCOMMITTED" ]; then
  echo "❌ req worktree ($REQ_BRANCH) 有未提交改动，git 会拒绝 merge：" >&2
  echo "$REQ_UNCOMMITTED" >&2
  echo "" >&2
  echo "请先在 req worktree 中提交：" >&2
  echo "  cd $REQ_WORKTREE" >&2
  echo "  git add -A && git commit -m \"chore: <描述>\"" >&2
  echo "然后重新运行 /close-task。" >&2
  exit 1
fi

# --- I-CT7 / I-CT8: 事件流与 commit 时间戳审计（merge 前强拦） ---
AUDIT_SCRIPT="$REPO_ROOT/.claude/scripts/audit-task-events.py"
if [ -f "$AUDIT_SCRIPT" ]; then
  if ! python3 "$AUDIT_SCRIPT" \
      --task-file "$TASK_FILE" \
      --task-branch "$BRANCH" \
      --req-branch "$REQ_BRANCH"; then
    # audit-task-events.py 已打印违规详情，直接退出
    exit 1
  fi
else
  echo "⚠️ 找不到事件流审计脚本 ${AUDIT_SCRIPT}，跳过 I-CT7/I-CT8 校验。" >&2
fi

# --- v4.5：防 task md modify/delete 冲突 ---
# req 分支在 task-confirm 时删了 task md（task 分支独家所有），但 task 分支还在改它。
# merge 时 git 报 modify/delete 冲突。先把 task md 从 task 分支 checkout 出来 + add，
# 让 req 分支"先认回"它，merge 时 task 分支再 merge 进来就无冲突。
cd "$REQ_WORKTREE"
TASK_FILE_REL=$(echo "$TASK_FILE" | sed -E "s|^.*\.worktrees/[^/]+/||")
ENG_FILE_REL=$(echo "$ENG_FILE" | sed -E "s|^.*\.worktrees/[^/]+/||")
# 仅当 req 分支当前不存在该路径时才"认回"（v4.5 fork 时已删；旧格式未删时跳过）
RECLAIMED=()
if ! git ls-files --error-unmatch "$TASK_FILE_REL" >/dev/null 2>&1; then
  if git show "$BRANCH:$TASK_FILE_REL" >/dev/null 2>&1; then
    git checkout "$BRANCH" -- "$TASK_FILE_REL" 2>/dev/null && RECLAIMED+=("$TASK_FILE_REL")
  fi
fi
if [ "$HAS_ENG" = "true" ] && ! git ls-files --error-unmatch "$ENG_FILE_REL" >/dev/null 2>&1; then
  if git show "$BRANCH:$ENG_FILE_REL" >/dev/null 2>&1; then
    git checkout "$BRANCH" -- "$ENG_FILE_REL" 2>/dev/null && RECLAIMED+=("$ENG_FILE_REL")
  fi
fi
if [ ${#RECLAIMED[@]} -gt 0 ]; then
  git add "${RECLAIMED[@]}"
  git commit -q -m "close-prep: reclaim task md from $BRANCH (v4.5 merge prep)"
fi

# 执行 merge
if ! git merge "$BRANCH" --no-edit -m "close: $TASK_TITLE" 2>&1; then
  echo "❌ merge $BRANCH → $REQ_BRANCH 失败。请手动解决冲突后再运行 close-task。" >&2
  exit 1
fi

# 验证 merge 生效：req 分支的 HEAD 必须包含 task 分支的所有提交
TASK_HEAD=$(git -C "$REPO_ROOT" rev-parse "$BRANCH" 2>/dev/null)
if ! git merge-base --is-ancestor "$TASK_HEAD" HEAD 2>/dev/null; then
  echo "❌ merge 声称成功但 ${BRANCH} 的提交未进入 ${REQ_BRANCH}。数据完整性校验失败。" >&2
  exit 1
fi

MERGE_OK=true
echo "🔀 已合并 ${BRANCH} → ${REQ_BRANCH}（已验证提交落地）"

# --- 2.5. 在 req worktree 中归档 .runs/ 并 commit 到 req 分支 ---
# 必须 commit，否则 close-req 清理 worktree 时归档文件会丢失
# 归档路径：req worktree 里的 requirements/active/<req>/tasks/_archived/<task>/
REQ_BASENAME=$(basename "$REQ_DIR")
ARCHIVE_DIR_IN_WORKTREE="$REQ_WORKTREE/requirements/active/$REQ_BASENAME/tasks/_archived/$TASK_STEM"
mkdir -p "$ARCHIVE_DIR_IN_WORKTREE"

ARCHIVED_FILES=()
if [ -f "$RUNS_FILE" ]; then
  cp "$RUNS_FILE" "$ARCHIVE_DIR_IN_WORKTREE/"
  ARCHIVED_FILES+=("$ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.json")
  echo "📦 归档 runtime: $ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.json"
fi
if [ -f "$EVENTS_FILE" ]; then
  cp "$EVENTS_FILE" "$ARCHIVE_DIR_IN_WORKTREE/"
  ARCHIVED_FILES+=("$ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.jsonl")
  echo "📦 归档事件流: $ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.jsonl"
fi

if [ ${#ARCHIVED_FILES[@]} -gt 0 ]; then
  # 在 req worktree 里 commit 归档文件
  cd "$REQ_WORKTREE"
  git add "requirements/active/$REQ_BASENAME/tasks/_archived/$TASK_STEM/" 2>/dev/null
  if ! git commit -m "archive: runtime for $TASK_STEM" 2>&1; then
    echo "❌ 归档文件提交失败。为防止数据丢失，保留 .runs/ 原件，请手动检查。" >&2
    exit 1
  fi
  echo "✅ 归档已 commit 到 $REQ_BRANCH"
fi

# --- 3. 直接删 task worktree + branch（v4.5：cwd 在 req worktree，不删自己脚下） ---
if [ "$MERGE_OK" = "true" ]; then
  if [ -d "$TASK_WORKTREE" ]; then
    if git -C "$REPO_ROOT" worktree remove "$TASK_WORKTREE" 2>/dev/null; then
      echo "🧹 已删 task worktree: $TASK_WORKTREE"
    else
      # 回退：rm -rf + worktree prune
      rm -rf "$TASK_WORKTREE"
      git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
      echo "🧹 已强制清理 task worktree: $TASK_WORKTREE"
    fi
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    if git -C "$REPO_ROOT" branch -D "$BRANCH" >/dev/null 2>&1; then
      echo "🧹 已删 task branch: $BRANCH"
    else
      echo "❌ 删 task branch $BRANCH 失败。请人工检查。" >&2
      exit 1
    fi
  fi
fi

# --- 5. 杀 dev server（兼容字段名 "开发服务器" / "dev server"） ---
DEV_SERVER=$(extract_task_field "$TASK_FILE" "开发服务器")
if [ -z "$DEV_SERVER" ]; then
  DEV_SERVER=$(extract_task_field "$TASK_FILE" "dev server")
fi
PORT=$(echo "$DEV_SERVER" | grep -oE '[0-9]+' | tail -1 || true)
if [ -n "$PORT" ] && [ "$PORT" -gt 0 ] 2>/dev/null; then
  PIDS=$(lsof -ti :"$PORT" 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "$PIDS" | xargs kill 2>/dev/null || true
    echo "🔌 已停止端口 $PORT 上的 dev server"
  fi
fi

# --- 6. 清理 .runs/ 原件 ---
[ -f "$RUNS_FILE" ] && rm -f "$RUNS_FILE"
[ -f "$EVENTS_FILE" ] && rm -f "$EVENTS_FILE"

# --- 7. 追加关闭事件 ---
if [ -f "$EVENTS_SCRIPT" ]; then
  python3 "$EVENTS_SCRIPT" append "$TASK_FILE" --type task_closed 2>/dev/null || true
fi

echo "✅ Task 已关闭: $TASK_TITLE"
