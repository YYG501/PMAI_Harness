#!/usr/bin/env bash
# cancel-work.sh — 废弃当前工作（方案 A·清模块 .work-meta，不 merge main）
# 用法: bash $HOME/.pmai/scripts/cancel-work.sh <模块目录>  （= docs/modules/<模块>/）
#
# 新模型（lifecycle 迁移批 3，方案 A）：
#   废弃 = 在 main 上删模块 .work-meta.json（清掉「在做的工作」标记），不 merge work branch到 main。
#   模块三件套（spec/decisions/discussion）若已在 main 则留场（历史在 git log + decisions 里）。
#   worktree/分支推迟到 cleanup-pending 兜底清（防 dangling cwd）。
#
# 顺序（任一步失败就 fail-fast）：
#   1. 切回 main，检查 main 是否脏（脏则拒绝，避免污染 cancel commit）
#   2. 在 main 上删模块 .work-meta + 路径级 commit
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
MODULE_BASENAME=$(basename "$WORK_DIR")

if [ -z "$WORK_BRANCH" ] || [ -z "$WORK_ID" ]; then
  echo "❌ 无法从模块元数据读取 branch/id 字段。" >&2
  exit 1
fi

echo "⚠️ 即将放弃当前工作: $WORK_ID"

# --- Step 1: 切回 main（硬失败）---
cd "$REPO_ROOT"
CURRENT=$(git branch --show-current 2>/dev/null || true)
if [ "$CURRENT" != "main" ]; then
  if ! git checkout main 2>&1; then
    echo "❌ 无法切到 main 分支（可能有未提交改动）。请先处理再重试。" >&2
    exit 1
  fi
fi

# --- Step 1.5: main 污染防护：cancel 只允许自己产生 .work-meta 删除 ---
# 开始前要求 main 干净。模块内 discussion/spec 等改动同样不能被 cancel 顺带提交。
REL_MODULE="docs/modules/$MODULE_BASENAME"
REL_META="$REL_MODULE/.work-meta.json"
DIRTY=$(git status --porcelain --untracked-files=all 2>/dev/null || true)
if [ -n "$DIRTY" ]; then
  echo "❌ main 分支有未提交改动，拒绝 cancel；本操作只会提交 $REL_META 的删除：" >&2
  echo "$DIRTY" >&2
  echo "请先处理（commit 或 stash）这些改动，然后重新运行 /pmai-build-cancel。" >&2
  exit 1
fi

# --- Step 2: 在 main 上删模块 .work-meta（方案 A）+ 路径级 commit ---
MAIN_MODULE="$REPO_ROOT/$REL_MODULE"
MAIN_MODULE_META="$MAIN_MODULE/.work-meta.json"

# 删模块 .work-meta（若在 main 上）；不在 main（只在 worktree）则无需删——cancel 不 merge，
# work branch随 worktree 一起被清，主仓本就没这份工作状态。
if [ -f "$MAIN_MODULE_META" ]; then
  git rm -q -- "$REL_META"
fi

# commit：如果没有暂存改动（main 上本就没这份工作状态），跳过
if [ -n "$(git diff --cached --name-only -- "$REL_META")" ]; then
  if ! git commit -m "cancel: ${WORK_ID}（清模块 .work-meta）" -- "$REL_META" 2>&1; then
    if git restore --staged --worktree -- "$REL_META" 2>/dev/null; then
      echo "❌ commit cancelled 状态失败；已恢复 $REL_META，未进入清理流程。" >&2
    else
      echo "❌ commit cancelled 状态失败，且无法自动恢复 $REL_META；请从 HEAD 恢复后再重试。" >&2
    fi
    exit 1
  fi
  echo "✅ cancelled 状态已 commit 到 main（清模块 .work-meta）"
else
  echo "ℹ️ main 上无本模块工作状态需要清（当前工作仅存在于隔离 worktree），跳过 commit"
fi

# --- Step 3: 标记 worktree/分支为待清理 ---
# 不立即删 worktree/branch：PM 可能在某个 worktree 内调用 cancel-work，
# 立即删除会让 Claude Code 父进程 cwd 变成 dangling，触发 Stop hook 的
# posix_spawn ENOENT。改为写 pending，由 cleanup-pending-worktrees.sh 在主仓 cwd 兜底清理。
PENDING_FILE="$REPO_ROOT/.runs/pending-cleanup.json"
mkdir -p "$REPO_ROOT/.runs"

QUEUE_PENDING_PY=$(mktemp)
trap 'rm -f "$QUEUE_PENDING_PY"' EXIT
cat > "$QUEUE_PENDING_PY" <<'PY'
import json, os, sys, datetime
pending_file, kind, branch, worktree, ref = sys.argv[1:6]
entries = []
if os.path.exists(pending_file):
    with open(pending_file) as f:
        try:
            entries = json.load(f)
        except json.JSONDecodeError:
            entries = []
entries = [e for e in entries if e.get("branch") != branch]
entry = {
    "kind": kind,
    "branch": branch,
    "worktree": worktree,
    "queued_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}
if kind == "work":
    entry["work_dir"] = ref
entries.append(entry)
with open(pending_file, "w") as f:
    json.dump(entries, f, indent=2, ensure_ascii=False)
PY
WORK_WORKTREE=$(resolve_worktree_path "$WORK_BRANCH" "$REPO_ROOT" || true)
if [ -z "$WORK_WORKTREE" ]; then
  WORK_WORKTREE="$REPO_ROOT/.worktrees/$WORK_BRANCH"
fi
python3 "$QUEUE_PENDING_PY" "$PENDING_FILE" work "$WORK_BRANCH" "$WORK_WORKTREE" "$WORK_DIR"
echo "🕓 标记待清理当前工作: $WORK_BRANCH"

echo "✅ 当前工作已放弃: ${WORK_ID}（未 merge 到 main，模块 .work-meta 已清）"
echo ""
echo "📋 worktree 和 branch 待清理。请退出当前会话，回主仓 ($REPO_ROOT) 执行："
echo "   bash scripts/cleanup-pending-worktrees.sh"
