#!/usr/bin/env bash
# cancel-work.sh — 废弃当前工作（方案 A·清模块 .work-meta，不 merge 主线）
# 用法: bash "${PMAI_HOME:-$HOME/.pmai}/scripts/cancel-work.sh" <模块目录>  （= docs/modules/<模块>/）
#
# 新模型（lifecycle 迁移批 3，方案 A）：
#   废弃 = 在主线上删模块 .work-meta.json（清掉「在做的工作」标记），不 merge work branch 到主线。
#   模块三件套（spec/decisions/discussion）若已在主线则留场（历史在 git log + decisions 里）。
#   worktree/分支推迟到 cleanup-pending 兜底清（防 dangling cwd）。
#
# 顺序（任一步失败就 fail-fast）：
#   1. 切回 main/master，检查主线是否脏（脏则拒绝，避免污染 cancel commit）
#   2. 在主线上删模块 .work-meta + 路径级 commit
#   3. 标记 worktree/分支待清理

set -euo pipefail

WORK_DIR="${1:?用法: cancel-work.sh <模块目录>}"

# --- Setup PYTHONPATH for _lib.state ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib/_setup-pythonpath.sh"
source "$SCRIPT_DIR/_lib/worktree.sh"

# --- 找到主仓根目录 ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

WORK_META="$WORK_DIR/.work-meta.json"
if [ ! -f "$WORK_META" ]; then
  echo "❌ 模块工作状态文件不存在: $WORK_META" >&2
  exit 1
fi

# 走 _lib.state.read_work_meta CLI（与 close-work.sh 统一）
WORK_META_JSON=$(python3 -m _lib.state read_work_meta "$WORK_DIR" 2>/dev/null || echo "{}")
WORK_BRANCH=$(printf '%s' "$WORK_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('branch',''))")
WORK_ID=$(printf '%s' "$WORK_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
BUILD_MODE=$(printf '%s' "$WORK_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('build',{}).get('mode',''))")
MODULE_BASENAME=$(basename "$WORK_DIR")

if [ -z "$WORK_BRANCH" ] || [ -z "$WORK_ID" ]; then
  echo "❌ 无法从模块元数据读取 branch/id 字段。" >&2
  exit 1
fi

if [ "$BUILD_MODE" = "main" ]; then
  echo "❌ 当前工作使用 main 模式，/pmai-build-cancel 不适用；已停止且未改动主线。" >&2
  echo "请回 /pmai-proposal（产品方向）或 /pmai-design（模块行为）；对应流程会通过 replan-work.py 安全冻结旧范围并前向处理。" >&2
  exit 1
fi

echo "⚠️ 即将放弃当前工作: $WORK_ID"

# --- Step 1: 切回实际主线 main/master（硬失败）---
cd "$REPO_ROOT"
CURRENT=$(git branch --show-current 2>/dev/null || true)
if [ "$CURRENT" = "main" ] || [ "$CURRENT" = "master" ]; then
  INTEGRATION_BRANCH="$CURRENT"
elif git show-ref --verify --quiet refs/heads/main; then
  INTEGRATION_BRANCH="main"
elif git show-ref --verify --quiet refs/heads/master; then
  INTEGRATION_BRANCH="master"
else
  echo "❌ 主仓缺少 main/master，无法确认取消操作的落地主线。" >&2
  exit 1
fi
if [ "$CURRENT" != "$INTEGRATION_BRANCH" ]; then
  if ! git checkout "$INTEGRATION_BRANCH" 2>&1; then
    echo "❌ 无法切到 ${INTEGRATION_BRANCH} 分支（可能有未提交改动）。请先处理再重试。" >&2
    exit 1
  fi
fi
INTEGRATION_REF="refs/heads/$INTEGRATION_BRANCH"

# --- Step 1.5: 主线污染防护：cancel 只允许自己产生 .work-meta 删除 ---
# 开始前要求主线干净。模块内 discussion/spec 等改动同样不能被 cancel 顺带提交。
REL_MODULE="docs/modules/$MODULE_BASENAME"
REL_META="$REL_MODULE/.work-meta.json"
DIRTY=$(git status --porcelain --untracked-files=all 2>/dev/null || true)
if [ -n "$DIRTY" ]; then
  echo "❌ ${INTEGRATION_BRANCH} 分支有未提交改动，拒绝 cancel；本操作只会提交 ${REL_META} 的删除：" >&2
  echo "$DIRTY" >&2
  echo "请先处理（commit 或 stash）这些改动，然后重新运行 /pmai-build-cancel。" >&2
  exit 1
fi

# --- Step 2: 在主线上删模块 .work-meta（方案 A）+ 路径级 commit ---
MAIN_MODULE="$REPO_ROOT/$REL_MODULE"
MAIN_MODULE_META="$MAIN_MODULE/.work-meta.json"
PENDING_FILE="$REPO_ROOT/.runs/pending-cleanup.json"
mkdir -p "$REPO_ROOT/.runs"
WORK_WORKTREE=$(resolve_worktree_path "$WORK_BRANCH" "$REPO_ROOT" || true)
if [ -z "$WORK_WORKTREE" ]; then
  WORK_WORKTREE="$REPO_ROOT/.worktrees/$WORK_BRANCH"
fi

# 先持久化清理意图，再提交取消状态。进程若在 commit 后、activate 前中断，
# 主仓 cleanup 会依据所绑定主线上 .work-meta 已消失自动激活这条记录。
CLEANUP_TRANSACTION_ID=$(python3 "$SCRIPT_DIR/_lib/pending_cleanup.py" prepare \
  --file "$PENDING_FILE" \
  --kind work \
  --branch "$WORK_BRANCH" \
  --worktree "$WORK_WORKTREE" \
  --work-dir "$WORK_DIR" \
  --integration-ref "$INTEGRATION_REF" \
  --activation main_meta_absent \
  --module-meta "$REL_META")

# 删模块 .work-meta（若在主线上）；不在主线（只在 worktree）则无需删——cancel 不 merge，
# work branch随 worktree 一起被清，主仓本就没这份工作状态。
if [ -f "$MAIN_MODULE_META" ]; then
  git rm -q -- "$REL_META"
fi

# commit：如果没有暂存改动（主线上本就没这份工作状态），跳过
if [ -n "$(git diff --cached --name-only -- "$REL_META")" ]; then
  if ! git commit -m "cancel: ${WORK_ID}（清模块 .work-meta）" -- "$REL_META" 2>&1; then
    if git restore --staged --worktree -- "$REL_META" 2>/dev/null; then
      echo "❌ commit cancelled 状态失败；已恢复 ${REL_META}，未进入清理流程。" >&2
    else
      echo "❌ commit cancelled 状态失败，且无法自动恢复 ${REL_META}；请从 HEAD 恢复后再重试。" >&2
    fi
    if ! python3 "$SCRIPT_DIR/_lib/pending_cleanup.py" remove \
      --file "$PENDING_FILE" --branch "$WORK_BRANCH" \
      --transaction-id "$CLEANUP_TRANSACTION_ID"; then
      echo "⚠️ 取消状态未提交，prepared 清理记录也未能撤销；记录不会自动激活，请人工检查队列。" >&2
    fi
    exit 1
  fi
  echo "✅ cancelled 状态已 commit 到 ${INTEGRATION_BRANCH}（清模块 .work-meta）"
else
  echo "ℹ️ 主线上无本模块工作状态需要清（当前工作仅存在于隔离 worktree），跳过 commit"
fi

# --- Step 3: 激活 worktree/分支待清理记录 ---
# 不立即删 worktree/branch：PM 可能在某个 worktree 内调用 cancel-work，
# 立即删除会让 Claude Code 父进程 cwd 变成 dangling，触发 Stop hook 的
# posix_spawn ENOENT。改为写 pending，由 cleanup-pending-worktrees.sh 在主仓 cwd 兜底清理。
if ! python3 "$SCRIPT_DIR/_lib/pending_cleanup.py" activate \
  --file "$PENDING_FILE" --branch "$WORK_BRANCH" \
  --transaction-id "$CLEANUP_TRANSACTION_ID"; then
  echo "⚠️ 取消状态已提交；清理记录仍处于 prepared，主仓 cleanup 将按 Git 状态自动恢复。" >&2
fi
echo "🕓 标记待清理当前工作: $WORK_BRANCH"

echo "✅ 当前工作已放弃: ${WORK_ID}（未 merge 到主线，模块 .work-meta 已清）"
echo ""
echo "🕓 相关工作环境已进入后台清理队列，无需手工操作。"
