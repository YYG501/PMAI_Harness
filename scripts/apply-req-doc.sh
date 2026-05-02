#!/usr/bin/env bash
# apply-req-doc.sh — 把 req 分支上某个文件的内容应用到 task worktree
#
# 用法：
#   apply-req-doc.sh <worktree-dir> <req-branch> <relative-path> [<task-file-for-audit>]
#
# 行为：
#   1. `git show <req-branch>:<path> > <worktree>/<path>`（绕 .git/index.lock）
#   2. 如果 worktree 上原本有这个文件 → 记 before_hash；否则 before_hash="MISSING"
#   3. 应用后取 after_hash（必然 = req_hash）
#   4. 如果传了 task-file，append req_doc_applied 事件含 path / before_hash / after_hash / req_branch
#   5. 故意单文件 — 跟 sync-req-docs 静默批量覆盖区分；PM 一次决定一个
#
# 4.5f 与 check-req-doc-drift.sh 配套：drift 列出候选 → PM 看 diff → 选 apply 单个
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "用法: apply-req-doc.sh <worktree-dir> <req-branch> <relative-path> [<task-file>]" >&2
  exit 2
fi

WORKTREE="$1"
REQ_BRANCH="$2"
REL_PATH="$3"
TASK_FILE="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$WORKTREE" ]; then
  echo "错误：worktree 不存在: $WORKTREE" >&2
  exit 1
fi

# 校验 req 分支上确实有这个文件
if ! git -C "$WORKTREE" cat-file -e "${REQ_BRANCH}:${REL_PATH}" 2>/dev/null; then
  echo "错误：${REQ_BRANCH}:${REL_PATH} 不存在" >&2
  exit 1
fi

# 记 before（worktree 当前 hash 或 MISSING）
if [ -f "$WORKTREE/$REL_PATH" ]; then
  BEFORE_HASH=$(git -C "$WORKTREE" hash-object "$REL_PATH" 2>/dev/null || echo "MISSING")
else
  BEFORE_HASH="MISSING"
fi

# 应用
mkdir -p "$WORKTREE/$(dirname "$REL_PATH")"
git -C "$WORKTREE" show "${REQ_BRANCH}:${REL_PATH}" > "$WORKTREE/$REL_PATH"

# after = req 分支 hash（git show 完一致）
AFTER_HASH=$(git -C "$WORKTREE" rev-parse "${REQ_BRANCH}:${REL_PATH}")

# Audit event
if [ -n "$TASK_FILE" ] && [ -f "$TASK_FILE" ]; then
  (
    cd "$WORKTREE"
    python3 "$SCRIPT_DIR/task-events.py" append "$TASK_FILE" \
      --type req_doc_applied \
      --payload "{\"path\": \"${REL_PATH}\", \"before_hash\": \"${BEFORE_HASH}\", \"after_hash\": \"${AFTER_HASH}\", \"req_branch\": \"${REQ_BRANCH}\"}" \
      >/dev/null 2>&1
  ) || true
fi

echo "✅ apply-req-doc: ${REL_PATH} ← ${REQ_BRANCH}（${BEFORE_HASH:0:8} → ${AFTER_HASH:0:8}）" >&2
