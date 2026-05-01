#!/usr/bin/env bash
# sync-req-docs.sh — 从 req 分支同步需求与项目级文档到 task worktree
#
# 用法：
#   sync-req-docs.sh <worktree-dir> <req-branch> <task-file>
#
# 行为：
#   1. 项目级单文件（DESIGN.md / CLAUDE.md）从 req 分支拉到 worktree 根
#   2. requirements/active/<req-id>/ 整个目录递归同步
#   3. 用 `git show <branch>:<path> > <dest>` —— 不写 .git/index.lock
#      （多 worktree 并发 sync 互不干扰；同步文件在 worktree 里显示为
#      untracked / modified，由 check-task-scope.py 阻断 commit）
#   4. 同步成功后 append req_docs_synced 事件，记录文件数与摘要 hash
#
# Eng review 修正：原方案用 `git checkout <branch> -- <path>` 会写主 repo
# .git/index.lock，并发 task-execute 抢锁退化串行甚至失败。git show 完全
# 绕过 index——worktree 同步本来就不需要进 index。
set -euo pipefail

if [ $# -lt 3 ]; then
  echo "用法: sync-req-docs.sh <worktree-dir> <req-branch> <task-file>" >&2
  exit 2
fi

WORKTREE="$1"
REQ_BRANCH="$2"
TASK_FILE="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$WORKTREE" ]; then
  echo "错误：worktree 不存在: $WORKTREE" >&2
  exit 1
fi

# REQ_ID 从 REQ_BRANCH 推断（约定：req 分支名 = req 目录名）
REQ_ID="$REQ_BRANCH"

# 用换行分隔字符串积累同步路径（路径名约定无换行；避免 bash 3.x macOS
# 空数组 + set -u 触发 unbound 的坑）
SYNCED_FILES=""

# ─────────────────────────────────────
# 第一层：项目级单文件
# ─────────────────────────────────────
for p in DESIGN.md CLAUDE.md; do
  if git -C "$WORKTREE" cat-file -e "$REQ_BRANCH:$p" 2>/dev/null; then
    mkdir -p "$WORKTREE/$(dirname "$p")"
    git -C "$WORKTREE" show "$REQ_BRANCH:$p" > "$WORKTREE/$p"
    SYNCED_FILES+="$p"$'\n'
  fi
done

# ─────────────────────────────────────
# 第二层：requirements/active/<req-id>/ 递归
# ─────────────────────────────────────
REQ_PATH="requirements/active/$REQ_ID"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  mkdir -p "$WORKTREE/$(dirname "$f")"
  git -C "$WORKTREE" show "$REQ_BRANCH:$f" > "$WORKTREE/$f"
  SYNCED_FILES+="$f"$'\n'
done < <(git -C "$WORKTREE" ls-tree -r --name-only "$REQ_BRANCH" -- "$REQ_PATH" 2>/dev/null || true)

# ─────────────────────────────────────
# 审计事件：req_docs_synced
# ─────────────────────────────────────
# Trailing newline 让 wc -l 准确
FILE_COUNT=$(printf "%s" "$SYNCED_FILES" | grep -c '^' || echo 0)

# 摘要 hash：所有同步文件的 blob sha 串联后 sha256 取前 12 位
HASH_INPUT=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  blob_sha=$(git -C "$WORKTREE" rev-parse "$REQ_BRANCH:$f" 2>/dev/null || echo "MISSING")
  HASH_INPUT+="$blob_sha "
done <<< "$SYNCED_FILES"
SYNC_HASH=$(printf "%s" "$HASH_INPUT" | shasum -a 256 | cut -c1-12)

# Append 事件（仅当 task-file 有效）
# task-events.py 用 cwd 探测主仓 .git/common-dir → 必须在 worktree 内调用，
# 否则事件落到调用方 shell 的 cwd 主仓，跨主仓写错位置
if [ -f "$TASK_FILE" ]; then
  (
    cd "$WORKTREE"
    python3 "$SCRIPT_DIR/task-events.py" append "$TASK_FILE" \
      --type req_docs_synced \
      --payload "{\"file_count\": ${FILE_COUNT}, \"hash\": \"${SYNC_HASH}\", \"req_branch\": \"${REQ_BRANCH}\"}" \
      >/dev/null 2>&1
  ) || true
fi

echo "✅ sync-req-docs: ${FILE_COUNT} 个文件已同步（hash=${SYNC_HASH}）" >&2
