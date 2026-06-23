#!/usr/bin/env bash
# cancel-req.sh — 废弃 req（方案 A·清模块 .req-meta，不 merge main）
# 用法: bash $HOME/.pmai/scripts/cancel-req.sh <模块目录>  （= docs/modules/<模块>/）
#
# 新模型（lifecycle 迁移批 3，方案 A）：
#   废弃 = 在 main 上删模块 .req-meta.json（清掉「在做的工作」标记），不 merge req 分支到 main。
#   模块三件套（spec/decisions/discussion）若已在 main 则留场（历史在 git log + decisions 里）。
#   req worktree/分支推迟到 cleanup-pending 兜底清（防 dangling cwd）。
#
# 顺序（任一步失败就 fail-fast）：
#   1. 切回 main，检查 main 是否脏（脏则拒绝，避免污染 cancel commit）
#   2. 在 main 上删模块 .req-meta + 路径级 commit
#   3. 标记 req worktree/分支待清理

set -euo pipefail

REQ_DIR="${1:?用法: cancel-req.sh <模块目录>}"

# --- Setup PYTHONPATH for _lib.state ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib/_setup-pythonpath.sh"
source "$SCRIPT_DIR/_lib/worktree.sh"
source "$SCRIPT_DIR/_lib/symlink-prd.sh"

# --- 找到主仓根目录 ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

REQ_META="$REQ_DIR/.req-meta.json"
if [ ! -f "$REQ_META" ]; then
  echo "❌ 模块工作状态文件不存在: $REQ_META" >&2
  exit 1
fi

# 走 _lib.state.read_req_meta CLI（与 close-req.sh 统一）
REQ_META_JSON=$(python3 -m _lib.state read_req_meta "$REQ_DIR" 2>/dev/null || echo "{}")
REQ_BRANCH=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('branch',''))")
REQ_ID=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
MODULE_BASENAME=$(basename "$REQ_DIR")

if [ -z "$REQ_BRANCH" ] || [ -z "$REQ_ID" ]; then
  echo "❌ 无法从模块元数据读取 branch/id 字段。" >&2
  exit 1
fi

echo "⚠️ 即将废弃 req: $REQ_ID"

# --- Step 1: 切回 main（硬失败）---
cd "$REPO_ROOT"
CURRENT=$(git branch --show-current 2>/dev/null || true)
if [ "$CURRENT" != "main" ]; then
  if ! git checkout main 2>&1; then
    echo "❌ 无法切到 main 分支（可能有未提交改动）。请先处理再重试。" >&2
    exit 1
  fi
fi

# --- Step 1.5: main 污染防护：如果 main 有任何在本模块路径之外的脏文件，拒绝 ---
# 只允许 docs/modules/<模块> 下的改动参与 cancel commit
REL_MODULE="docs/modules/$MODULE_BASENAME"
DIRTY=$(git status --porcelain 2>/dev/null || true)
if [ -n "$DIRTY" ]; then
  BAD=$(printf '%s\n' "$DIRTY" | awk -v prefix="$REL_MODULE/" '
    { path = substr($0, 4); if (index(path, prefix) != 1) print $0 }
  ')
  if [ -n "$BAD" ]; then
    echo "❌ main 分支有与本 req 无关的未提交改动，拒绝 cancel 以防污染 cancel commit：" >&2
    echo "$BAD" >&2
    echo "请先处理（commit、stash 或 reset）这些改动，然后重新运行 /pmai-cancel-req。" >&2
    exit 1
  fi
fi

# --- Step 2: 在 main 上删模块 .req-meta（方案 A）+ PRD 收口 symlink + 路径级 commit ---
MAIN_MODULE="$REPO_ROOT/$REL_MODULE"
MAIN_MODULE_META="$MAIN_MODULE/.req-meta.json"

# 在 docs/prds/废弃/ 下建 PRD 收口 symlink（仅当模块真的写过 prd.md；stage 1/2 cancel 时 silent skip）
if ! create_prd_symlink "$REPO_ROOT" "$MODULE_BASENAME" cancelled; then
  echo "❌ 创建 docs/prds/废弃/ symlink 失败。" >&2
  exit 1
fi

# 删模块 .req-meta（若在 main 上）；不在 main（只在 req worktree）则无需删——cancel 不 merge，
# req 分支随 worktree 一起被清，主仓本就没这份工作状态。
if [ -f "$MAIN_MODULE_META" ]; then
  git rm -q -- "$REL_MODULE/.req-meta.json" 2>/dev/null || rm -f "$MAIN_MODULE_META"
fi
git add -A -- "$REL_MODULE" 2>/dev/null || true
[ -d "$REPO_ROOT/docs/prds/废弃" ] && git add "docs/prds/废弃/$MODULE_BASENAME.md" 2>/dev/null || true

# commit：如果没有暂存改动（main 上本就没这份工作状态），跳过
if [ -n "$(git diff --cached --name-only)" ]; then
  if ! git commit -m "cancel: ${REQ_ID}（清模块 .req-meta）" 2>&1; then
    echo "❌ commit cancelled 状态失败。中止以防数据丢失。" >&2
    exit 1
  fi
  echo "✅ cancelled 状态已 commit 到 main（清模块 .req-meta）"
else
  echo "ℹ️ main 上无本模块工作状态需要清（req 仅存在于 req worktree），跳过 commit"
fi

# --- Step 3: 标记 req worktree/分支为待清理 ---
# 不立即删 worktree/branch：PM 可能在某个 req worktree 内调用 cancel-req，
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
if kind == "req":
    entry["req_dir"] = ref
entries.append(entry)
with open(pending_file, "w") as f:
    json.dump(entries, f, indent=2, ensure_ascii=False)
PY
REQ_WORKTREE=$(resolve_worktree_path "$REQ_BRANCH" "$REPO_ROOT" || true)
if [ -z "$REQ_WORKTREE" ]; then
  REQ_WORKTREE="$REPO_ROOT/.worktrees/$REQ_BRANCH"
fi
python3 "$QUEUE_PENDING_PY" "$PENDING_FILE" req "$REQ_BRANCH" "$REQ_WORKTREE" "$REQ_DIR"
echo "🕓 标记待清理 req: $REQ_BRANCH"

echo "✅ Req 已废弃: ${REQ_ID}（未 merge 到 main，模块 .req-meta 已清）"
echo ""
echo "📋 worktree 和 branch 待清理。请退出当前会话，回主仓 ($REPO_ROOT) 执行："
echo "   bash scripts/cleanup-pending-worktrees.sh"
