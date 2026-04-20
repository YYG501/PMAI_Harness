#!/usr/bin/env bash
# close-req.sh — Req 关闭：在 req 分支完成收尾 → merge 到 main → 清理
# 用法: bash .claude/scripts/close-req.sh <req-dir>
# 前置条件：该 req 下所有 task 必须已关闭

set -euo pipefail

REQ_DIR="${1:?用法: close-req.sh <req-dir>}"

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

# --- 读取 req 信息 ---
REQ_BRANCH=$(python3 -c "import json; print(json.load(open('$REQ_META'))['branch'])" 2>/dev/null)
REQ_ID=$(python3 -c "import json; print(json.load(open('$REQ_META'))['id'])" 2>/dev/null)
REQ_STAGE=$(python3 -c "import json; print(json.load(open('$REQ_META'))['stage'])" 2>/dev/null)

# --- 校验 stage ---
if [ "$REQ_STAGE" != "7" ]; then
  echo "❌ req 当前在 stage $REQ_STAGE，不是 stage 7。请先推进到 stage 7。" >&2
  exit 1
fi

# --- 校验所有 task 已关闭 ---
TASKS_DIR="$REQ_DIR/tasks"
if [ -d "$TASKS_DIR" ]; then
  OPEN_TASKS=$(find "$TASKS_DIR" -maxdepth 1 -name "task-*.md" -exec grep -l '^\*\*状态：\*\* \(待确认\|执行中\|待验收\)' {} \; 2>/dev/null || true)
  if [ -n "$OPEN_TASKS" ]; then
    echo "❌ 以下 task 尚未关闭：" >&2
    echo "$OPEN_TASKS" >&2
    exit 1
  fi
fi

# --- 检查分支是否存在 ---
# 规则：req 分支必须存在且 merge 成功才能归档。避免静默丢失整个 req
if ! git show-ref --verify --quiet "refs/heads/$REQ_BRANCH" 2>/dev/null; then
  echo "❌ req 分支 $REQ_BRANCH 不存在。不能归档未合并的 req（会丢失文档和代码）。" >&2
  echo "   如果你想废弃这个 req 而不合并，使用 /cancel-req 而不是 /close-req。" >&2
  exit 1
fi

# --- Step 1: 在 req worktree 中先完成"归档到 closed/ + meta 改 closed"并 commit ---
# 这样 merge 到 main 时会一次性带过去，不需要 merge 后再改动文件
REQ_WORKTREE="$REPO_ROOT/.worktrees/$REQ_BRANCH"
if [ ! -d "$REQ_WORKTREE" ]; then
  echo "❌ req worktree 不存在: $REQ_WORKTREE。请先恢复 req worktree。" >&2
  exit 1
fi

REQ_BASENAME=$(basename "$REQ_DIR")
cd "$REQ_WORKTREE"

# 记录 pre-close HEAD：如果后面 merge 失败，把 req 分支 reset 回这个点，避免 req 卡在半关闭状态
PRE_CLOSE_HEAD=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$PRE_CLOSE_HEAD" ]; then
  echo "❌ 无法读取 req 分支 HEAD，中止。" >&2
  exit 1
fi

# 1a. 在 req worktree 中移动 requirements/active/<req> 到 requirements/closed/<req>
mkdir -p "$REQ_WORKTREE/requirements/closed"
if [ -d "$REQ_WORKTREE/requirements/active/$REQ_BASENAME" ]; then
  git mv "requirements/active/$REQ_BASENAME" "requirements/closed/$REQ_BASENAME" 2>&1 || {
    echo "❌ 在 req worktree 中移动目录失败。请人工检查。" >&2
    exit 1
  }
  echo "📦 在 req 分支上移动到 closed/: requirements/closed/$REQ_BASENAME"
fi

# 1b. 更新 meta 为 closed
NEW_META="$REQ_WORKTREE/requirements/closed/$REQ_BASENAME/.req-meta.json"
if [ -f "$NEW_META" ]; then
  python3 -c "
import json
with open('$NEW_META', 'r') as f:
    meta = json.load(f)
meta['status'] = 'closed'
with open('$NEW_META', 'w') as f:
    json.dump(meta, f, indent=2, ensure_ascii=False)
" || {
    echo "❌ 更新 .req-meta.json 失败。" >&2
    exit 1
  }
fi

# 1c. commit 这些改动到 req 分支
git add -A
if ! git commit -m "close: archive $REQ_ID to closed/" 2>&1; then
  echo "❌ 提交归档改动到 req 分支失败（可能是 git 身份未配置或 hook 拒绝）。" >&2
  exit 1
fi
echo "✅ 归档改动已 commit 到 $REQ_BRANCH"

# --- Step 2: 切到主仓 main 执行 merge ---
cd "$REPO_ROOT"

CURRENT=$(git branch --show-current 2>/dev/null || true)
if [ "$CURRENT" != "main" ]; then
  git checkout main 2>/dev/null || {
    echo "❌ 无法切到 main 分支（可能有未提交改动）。请先处理。" >&2
    exit 1
  }
  echo "🔙 已切到 main 分支"
fi

if ! git merge "$REQ_BRANCH" --no-edit -m "close: $REQ_ID" 2>&1; then
  # merge 失败：先 abort merge，再把 req 分支 reset 回 pre-close，避免 req 卡在半关闭状态
  git merge --abort 2>/dev/null || true
  if ! git -C "$REQ_WORKTREE" reset --hard "$PRE_CLOSE_HEAD" 2>&1; then
    echo "❌ merge 失败，且回滚 req 分支失败。需要人工修复: cd $REQ_WORKTREE && git reset --hard $PRE_CLOSE_HEAD" >&2
    exit 1
  fi
  # 清理 reset 后残留的空目录（git reset --hard 不会删空目录）
  # closed/<req> 是 close-req 刚创建的，pre-close HEAD 里不存在。可以安全 rm -rf
  rm -rf "$REQ_WORKTREE/requirements/closed/$REQ_BASENAME"
  rmdir "$REQ_WORKTREE/requirements/closed" 2>/dev/null || true
  echo "❌ merge $REQ_BRANCH → main 失败。req 分支已回滚到 $PRE_CLOSE_HEAD，请手动解决冲突后再运行 close-req。" >&2
  exit 1
fi

# 验证 merge 生效
REQ_HEAD=$(git rev-parse "$REQ_BRANCH" 2>/dev/null)
if ! git merge-base --is-ancestor "$REQ_HEAD" HEAD 2>/dev/null; then
  # merge 声称成功但未落地：回滚 main 和 req 分支
  git reset --hard "HEAD@{1}" 2>/dev/null || true
  git -C "$REQ_WORKTREE" reset --hard "$PRE_CLOSE_HEAD" 2>/dev/null || true
  echo "❌ merge 声称成功但 $REQ_BRANCH 的提交未进入 main。数据完整性校验失败，已回滚。" >&2
  exit 1
fi

echo "🔀 已合并 $REQ_BRANCH → main（已验证提交落地）"

# --- Step 3: 清理 worktree（必须先于删分支，git 不允许删除 checkout 中的分支） ---
if [ -d "$REQ_WORKTREE" ]; then
  if ! git worktree remove "$REQ_WORKTREE" 2>/dev/null; then
    echo "⚠️ worktree remove 失败，回退到 rm -rf + worktree prune" >&2
    rm -rf "$REQ_WORKTREE"
    git worktree prune 2>/dev/null || true
  fi
  echo "🧹 已清理 worktree: $REQ_WORKTREE"
fi

# --- Step 4: 删除 req 分支（worktree 已清理，可以删分支） ---
if ! git branch -d "$REQ_BRANCH" 2>/dev/null; then
  if ! git branch -D "$REQ_BRANCH" 2>&1; then
    echo "❌ 无法删除分支 $REQ_BRANCH。请人工检查。" >&2
    exit 1
  fi
fi
echo "🗑️ 已删除分支: $REQ_BRANCH"

echo "✅ Req 已关闭: $REQ_ID"
echo "📍 当前位置: 主仓 main 分支"
