#!/usr/bin/env bash
# cancel-req.sh — 废弃 req：enumerate 所有 task → commit cancelled 到 main → 清理 worktree/分支
# 用法: bash .claude/scripts/cancel-req.sh <req-dir>
# 不 merge req 分支到 main。但 cancelled 占位（meta+目录）会 commit 到 main。
#
# 顺序（任一步失败就 fail-fast）：
#   1. 从 source of truth（传入的 REQ_DIR）枚举所有 task 分支/worktree/dev 端口
#   2. 切回 main，检查 main 是否脏（有脏则拒绝，避免污染 cancel commit）
#   3. 在 main 上做路径级 staging + commit cancelled 占位
#   4. 清理枚举出来的 task worktree/分支 + 杀 dev server + 删 .runs/
#   5. 清理 req worktree/分支

set -euo pipefail

REQ_DIR="${1:?用法: cancel-req.sh <req-dir>}"

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

REQ_META="$REQ_DIR/.req-meta.json"
if [ ! -f "$REQ_META" ]; then
  echo "❌ req 元数据不存在: $REQ_META" >&2
  exit 1
fi

# 走 _lib.state.read_req_meta CLI（与 close-req.sh 统一）
REQ_META_JSON=$(python3 -m _lib.state read_req_meta "$REQ_DIR" 2>/dev/null || echo "{}")
REQ_BRANCH=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('branch',''))")
REQ_ID=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
REQ_BASENAME=$(basename "$REQ_DIR")

if [ -z "$REQ_BRANCH" ] || [ -z "$REQ_ID" ]; then
  echo "❌ 无法从 req 元数据读取 branch/id 字段。" >&2
  exit 1
fi

echo "⚠️ 即将废弃 req: $REQ_ID"

# --- Step 1: 从 source of truth 枚举所有 task（在删任何 worktree/分支之前）---
# task 信息以 REQ_DIR/tasks/ 为真相源：REQ_DIR 可能指向 req worktree 里的目录，
# 也可能是 main 上的目录。无论哪种，都要在它还存在时把信息先读出来。
declare -a TASK_BRANCHES=()
declare -a TASK_PORTS=()
declare -a TASK_STEMS=()

SRC_TASKS_DIR="$REQ_DIR/tasks"
if [ -d "$SRC_TASKS_DIR" ]; then
  for TASK_FILE in "$SRC_TASKS_DIR"/task-*.md; do
    [ -f "$TASK_FILE" ] || continue
    case "$TASK_FILE" in *.engineering.md) continue;; esac
    # 用 _lib.state 双兼容 v1/v2 取分支 + 端口（从 dev_server / 开发服务器 字段）
    TASK_BRANCH=$(python3 -m _lib.state get_branch "$TASK_FILE" 2>/dev/null || echo "")
    [ -z "$TASK_BRANCH" ] && continue
    TASK_STEM=$(basename "$TASK_FILE" .md)
    PORT=$(python3 -m _lib.state get_meta "$TASK_FILE" 2>/dev/null | python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
v = d.get('dev_server') or ''
m = re.search(r'\d+', v)
print(m.group() if m else '0')
" 2>/dev/null || echo "0")
    TASK_BRANCHES+=("$TASK_BRANCH")
    TASK_STEMS+=("$TASK_STEM")
    TASK_PORTS+=("${PORT:-0}")
  done
fi

# --- Step 2: 切回 main（硬失败）---
cd "$REPO_ROOT"
CURRENT=$(git branch --show-current 2>/dev/null || true)
if [ "$CURRENT" != "main" ]; then
  if ! git checkout main 2>&1; then
    echo "❌ 无法切到 main 分支（可能有未提交改动）。请先处理再重试。" >&2
    exit 1
  fi
fi

# --- Step 2.5: main 污染防护：如果 main 有任何在 req 路径之外的脏文件，拒绝 ---
# 只允许 requirements/active/<req> 或 requirements/closed/<req> 下的改动参与 cancel commit
DIRTY=$(git status --porcelain 2>/dev/null || true)
if [ -n "$DIRTY" ]; then
  # 过滤：任何不属于 requirements/active/<req> 或 requirements/closed/<req> 的改动都是污染
  BAD=$(echo "$DIRTY" | awk -v prefix1="requirements/active/$REQ_BASENAME" -v prefix2="requirements/closed/$REQ_BASENAME" '
    {
      path = substr($0, 4)
      if (path !~ "^"prefix1 && path !~ "^"prefix2) print $0
    }
  ')
  if [ -n "$BAD" ]; then
    echo "❌ main 分支有与本 req 无关的未提交改动，拒绝 cancel 以防污染 cancel commit：" >&2
    echo "$BAD" >&2
    echo "请先处理（commit、stash 或 reset）这些改动，然后重新运行 /cancel-req。" >&2
    exit 1
  fi
fi

# --- Step 3: 在 main 上：移动 req 目录到 closed/ + 更新 meta + 路径级 commit ---
CLOSED_DIR="$REPO_ROOT/requirements/closed"
mkdir -p "$CLOSED_DIR"

MAIN_ACTIVE="$REPO_ROOT/requirements/active/$REQ_BASENAME"
MAIN_CLOSED="$CLOSED_DIR/$REQ_BASENAME"

if [ -d "$MAIN_ACTIVE" ]; then
  if ! git mv "requirements/active/$REQ_BASENAME" "requirements/closed/$REQ_BASENAME" 2>&1; then
    echo "❌ 在 main 上移动 req 目录失败。" >&2
    exit 1
  fi
elif [ ! -d "$MAIN_CLOSED" ]; then
  # main 上既没有 active 也没有 closed——创建 closed 占位目录 + 最小 meta
  mkdir -p "$MAIN_CLOSED"
  python3 -c "
import json
meta = {
  'id': '$REQ_ID',
  'branch': '$REQ_BRANCH',
  'status': 'cancelled',
  'note': 'cancelled before any merge to main'
}
with open('$MAIN_CLOSED/.req-meta.json', 'w') as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
" || {
    echo "❌ 写入 cancelled 占位 meta 失败。" >&2
    exit 1
  }
fi

# 更新 meta.status = cancelled
MAIN_META="$MAIN_CLOSED/.req-meta.json"
if [ -f "$MAIN_META" ]; then
  if ! python3 -c "
import json
with open('$MAIN_META', 'r') as f:
    meta = json.load(f)
meta['status'] = 'cancelled'
with open('$MAIN_META', 'w') as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
"; then
    echo "❌ 更新 cancelled meta 失败。" >&2
    exit 1
  fi
fi

# 路径级 staging：只 add req 相关的两个路径（active/<req> 已经被 git mv 追踪，closed/<req> 是新内容）
git add "requirements/active/$REQ_BASENAME" 2>/dev/null || true
git add "requirements/closed/$REQ_BASENAME" 2>/dev/null || true

# commit：如果没有暂存改动（占位且 meta 未变），跳过
if [ -n "$(git diff --cached --name-only)" ]; then
  if ! git commit -m "cancel: $REQ_ID" 2>&1; then
    echo "❌ commit cancelled 状态失败。中止以防数据丢失。" >&2
    exit 1
  fi
  echo "✅ cancelled 状态已 commit 到 main"
else
  echo "ℹ️ 没有新改动需要 commit（可能已经处于 cancelled 状态）"
fi

# --- Step 4: 标记 task worktree/分支为待清理 + 杀 dev server + 删 .runs/ 原件 ---
# 不立即删 worktree/branch：PM 可能在某个 task/req worktree 内调用 cancel-req，
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
if kind == "task":
    entry["task_file"] = ref
elif kind == "req":
    entry["req_dir"] = ref
entries.append(entry)
with open(pending_file, "w") as f:
    json.dump(entries, f, indent=2, ensure_ascii=False)
PY

for i in "${!TASK_BRANCHES[@]}"; do
  TASK_BRANCH="${TASK_BRANCHES[$i]}"
  TASK_STEM="${TASK_STEMS[$i]}"
  PORT="${TASK_PORTS[$i]}"

  # 杀 dev server（不影响 cwd，立即做）
  if [ "$PORT" != "0" ] && [ "$PORT" -gt 0 ] 2>/dev/null; then
    lsof -ti :"$PORT" 2>/dev/null | xargs kill 2>/dev/null || true
  fi

  TASK_WT=$(resolve_worktree_path "$TASK_BRANCH" "$REPO_ROOT" || true)
  if [ -z "$TASK_WT" ]; then
    # 没找到对应 worktree（可能已被手动删除）。pending-cleanup 会按 branch 处理。
    TASK_WT="$REPO_ROOT/.worktrees/$TASK_BRANCH"
  fi
  python3 "$QUEUE_PENDING_PY" "$PENDING_FILE" task "$TASK_BRANCH" "$TASK_WT" "$TASK_STEM"
  echo "🕓 标记待清理 task: $TASK_BRANCH"

  # .runs/ 原件可以立即删（不在 worktree 内）
  rm -f "$REPO_ROOT/.runs/$TASK_STEM.json" 2>/dev/null
  rm -f "$REPO_ROOT/.runs/events/$TASK_STEM.jsonl" 2>/dev/null
done

# --- Step 5: 标记 req worktree/分支为待清理 ---
REQ_WORKTREE=$(resolve_worktree_path "$REQ_BRANCH" "$REPO_ROOT" || true)
if [ -z "$REQ_WORKTREE" ]; then
  REQ_WORKTREE="$REPO_ROOT/.worktrees/$REQ_BRANCH"
fi
python3 "$QUEUE_PENDING_PY" "$PENDING_FILE" req "$REQ_BRANCH" "$REQ_WORKTREE" "$REQ_DIR"
echo "🕓 标记待清理 req: $REQ_BRANCH"

echo "✅ Req 已废弃: ${REQ_ID}（未 merge 到 main，cancelled 状态已记录）"
echo ""
echo "📋 worktree 和 branch 待清理。请退出当前会话，回主仓 ($REPO_ROOT) 执行："
echo "   bash scripts/cleanup-pending-worktrees.sh"
