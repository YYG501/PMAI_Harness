#!/usr/bin/env bash
# close-req.sh — Req 关闭：在 req 分支完成收尾 → merge 到 main → 删 worktree/branch
# 用法: bash scripts/close-req.sh <req-dir>
# 前置条件：
#   1. 在主仓 cwd（不在 req worktree 内）运行
#   2. 该 req 下所有 task 已关闭，stage = 7

set -euo pipefail

# 在任何 cd 之前记录调用方的 cwd
CALLER_CWD="$(pwd -P 2>/dev/null || echo "")"

REQ_DIR="${1:?用法: close-req.sh <req-dir>}"

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
  echo "❌ req 元数据不存在: $REQ_META" >&2
  exit 1
fi

# --- 读取 req 信息（走 _lib.state.read_req_meta CLI；单次读全部字段）---
REQ_META_JSON=$(python3 -m _lib.state read_req_meta "$REQ_DIR" 2>/dev/null || echo "{}")
REQ_BRANCH=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('branch',''))")
REQ_ID=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
REQ_STAGE=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stage',''))")

# --- 校验 stage ---
if [ "$REQ_STAGE" != "7" ]; then
  echo "❌ req 当前在 stage ${REQ_STAGE}，不是 stage 7。请先推进到 stage 7。" >&2
  exit 1
fi

# --- 校验所有 task 已关闭 ---
# 用 _lib.state.get_task_status 双兼容 v1/v2 格式
TASKS_DIR="$REQ_DIR/tasks"
if [ -d "$TASKS_DIR" ]; then
  OPEN_TASKS=""
  for TF in "$TASKS_DIR"/task-*.md; do
    [ -f "$TF" ] || continue
    case "$TF" in *.engineering.md) continue;; esac
    STATUS=$(python3 -m _lib.state get_status "$TF" 2>/dev/null || echo "")
    case "$STATUS" in
      待执行|执行中)
        OPEN_TASKS="${OPEN_TASKS}${TF}"$'\n'
        ;;
    esac
  done
  if [ -n "$OPEN_TASKS" ]; then
    echo "❌ 以下 task 尚未关闭：" >&2
    printf "%s" "$OPEN_TASKS" >&2
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
REQ_WORKTREE=$(resolve_worktree_path "$REQ_BRANCH" "$REPO_ROOT" || true)
if [ -z "$REQ_WORKTREE" ] || [ ! -d "$REQ_WORKTREE" ]; then
  echo "❌ req worktree 不存在（git worktree list 中找不到分支 ${REQ_BRANCH}）。请先恢复 req worktree。" >&2
  exit 1
fi

# --- 校验：调用方 cwd 不能在 req worktree 内 ---
# 原因：删 worktree 前 Claude Code 父进程 cwd 必须不在其内，否则 Stop hook posix_spawn ENOENT
REQ_WORKTREE_REAL="$(cd "$REQ_WORKTREE" 2>/dev/null && pwd -P || echo "$REQ_WORKTREE")"
if [ -n "$CALLER_CWD" ] && [ -n "$REQ_WORKTREE_REAL" ]; then
  if [ "$CALLER_CWD" = "$REQ_WORKTREE_REAL" ] || \
     printf '%s/' "$CALLER_CWD" | grep -qF "${REQ_WORKTREE_REAL}/"; then
    echo "❌ 当前 cwd 在 req worktree 内，不能直接删除。" >&2
    echo "   当前 cwd: $CALLER_CWD" >&2
    echo "   req worktree: $REQ_WORKTREE_REAL" >&2
    echo "" >&2
    echo "   请切到主仓窗口（cwd = $REPO_ROOT），再跑：" >&2
    echo "   bash scripts/close-req.sh $REQ_DIR" >&2
    exit 1
  fi
fi

REQ_BASENAME=$(basename "$REQ_DIR")
cd "$REQ_WORKTREE"
REL_ACTIVE="requirements/active/$REQ_BASENAME"
REL_CLOSED="requirements/closed/$REQ_BASENAME"

# close-req 只允许归档当前 req 目录。req worktree 里如果漂着其他未提交改动，
# 直接 git add -A 会把无关代码/文档静默带进 main。
REQ_STATUS=$(git status --porcelain --untracked-files=all 2>/dev/null || true)
UNRELATED_DIRTY=""
if [ -n "$REQ_STATUS" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line:3}"
    case "$path" in
      *" -> "*) path="${path##* -> }" ;;
    esac
    case "$path" in
      "$REL_ACTIVE"/*) ;;
      *)
        UNRELATED_DIRTY="${UNRELATED_DIRTY}${line}"$'\n'
        ;;
    esac
  done <<< "$REQ_STATUS"
fi
if [ -n "$UNRELATED_DIRTY" ]; then
  echo "❌ req worktree 有当前 req 目录外的未提交改动，close-req 不会静默带入 main：" >&2
  printf "%s" "$UNRELATED_DIRTY" >&2
  echo "" >&2
  echo "请先提交、移走或清理这些改动后再运行 close-req。" >&2
  exit 1
fi

# 记录 pre-close HEAD：如果后面 merge 失败，把 req 分支 reset 回这个点，避免 req 卡在半关闭状态
PRE_CLOSE_HEAD=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$PRE_CLOSE_HEAD" ]; then
  echo "❌ 无法读取 req 分支 HEAD，中止。" >&2
  exit 1
fi

# 1a. 在 req worktree 中移动 requirements/active/<req> 到 requirements/closed/<req>
mkdir -p "$REQ_WORKTREE/requirements/closed"
if [ -d "$REQ_WORKTREE/$REL_ACTIVE" ]; then
  git mv "$REL_ACTIVE" "$REL_CLOSED" 2>&1 || {
    echo "❌ 在 req worktree 中移动目录失败。请人工检查。" >&2
    exit 1
  }
  echo "📦 在 req 分支上移动到 closed/: $REL_CLOSED"
fi

# 1b. 更新 meta 为 closed
NEW_META="$REQ_WORKTREE/$REL_CLOSED/.req-meta.json"
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

# 1b.5. 在 docs/prds/ 下建 PRD 收口 symlink（让 PM 一处查所有正常 close 的 req PRD）
# 若 closed/<req>/prd.md 不存在（极少见：req 未走完 stage 3 就 close）则 silent skip。
if ! create_prd_symlink "$REQ_WORKTREE" "$REQ_BASENAME" closed; then
  echo "❌ 创建 docs/prds/ symlink 失败。" >&2
  exit 1
fi

# 1c. commit 这些改动到 req 分支
git add -A -- "$REL_CLOSED"
[ -d "$REQ_WORKTREE/docs/prds" ] && git add -A -- "docs/prds"
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
  # 1b.5 建的 PRD symlink + 可能 mkdir 出的空 docs/prds/ 也清理（git reset 不删空目录）
  rmdir "$REQ_WORKTREE/docs/prds" 2>/dev/null || true
  echo "❌ merge ${REQ_BRANCH} → main 失败。req 分支已回滚到 ${PRE_CLOSE_HEAD}，请手动解决冲突后再运行 close-req。" >&2
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

# --- Step 3: 直接删 req worktree + branch ---
# 此时调用方 cwd 已校验不在 req worktree 内（上方 cwd check），可以安全删除
cd "$REPO_ROOT"

if [ -d "$REQ_WORKTREE" ]; then
  git worktree remove "$REQ_WORKTREE" 2>/dev/null || {
    rm -rf "$REQ_WORKTREE"
    git worktree prune 2>/dev/null || true
  }
  echo "🗑  worktree 已删除: $REQ_WORKTREE"
fi

if git show-ref --verify --quiet "refs/heads/$REQ_BRANCH" 2>/dev/null; then
  git branch -D "$REQ_BRANCH" 2>/dev/null && echo "🗑  branch 已删除: $REQ_BRANCH"
fi

# --- Step 4: 兜底清孤儿 worktree（按 task/req 记录定向；历史漏清 / 中断 close 留下的）---
cleanup_stale_worktrees "$REPO_ROOT"

echo ""
echo "✅ Req 已完全关闭: $REQ_ID"
echo "📍 当前位置: 主仓 main 分支"
echo ""
echo "运行 /new-req 开始下一个需求。"
