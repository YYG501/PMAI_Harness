#!/usr/bin/env bash
# manual adapter. See docs/归档/完成/设计-执行者可选.md §4.5
#
# Writes .pending-manual-<task>.json to $MAIN_REPO_ROOT/.runs/ (NOT relative path,
# so observability layers see it regardless of cwd), then exits 0.
# Caller (task-execute) must interpret exit 0 with manual executor as "skill ends
# here; PM will re-enter via /task-execute after completing worktree changes".

set -euo pipefail

: "${TASK_FILE:?TASK_FILE required}"
: "${TASK_WORKTREE:?TASK_WORKTREE required}"
: "${MAIN_REPO_ROOT:?MAIN_REPO_ROOT required}"

TASK_SHORT_ID=$(basename "$TASK_FILE" .md | sed -E 's/^(task-[0-9]+).*/\1/')
REQ_ID=$(basename "$(dirname "$(dirname "$TASK_FILE")")")
NOW=$(date -Iseconds)
BASELINE_SHA=$(git -C "$TASK_WORKTREE" rev-parse HEAD 2>/dev/null || echo "unknown")

mkdir -p "$MAIN_REPO_ROOT/.runs"
PENDING_FILE="$MAIN_REPO_ROOT/.runs/.pending-manual-${TASK_SHORT_ID}.json"

# JSON 字段 "task_id" 保留向后兼容；含义为 short_id（变量已重命名，字段名未动）
cat > "$PENDING_FILE" <<EOF
{
  "task_id": "$TASK_SHORT_ID",
  "task_file": "$TASK_FILE",
  "task_worktree": "$TASK_WORKTREE",
  "req_id": "$REQ_ID",
  "executor": "manual",
  "started_at": "$NOW",
  "baseline_sha": "$BASELINE_SHA",
  "snoozed_until": null
}
EOF

# execution_manual_waiting 事件由 task-transition.py --bound-to-execution-event
# manual-waiting 在 dispatch §3b 入口已原子写入（修复 B），manual.sh 不再 emit。

cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task-${TASK_SHORT_ID} 已设为 manual 执行

请在以下 worktree 完成实现：
  $TASK_WORKTREE
参考 task 文件：$TASK_FILE
  必读文档、执行范围、验收标准、写回职责都在文件里

完成后跑：
  /task-execute $TASK_SHORT_ID
会检测到 manual 标记 + 显式告知你"不会重跑执行器，直接进自审"。

如果决定放弃这个 task：
  python3 .claude/scripts/task-transition.py "$TASK_FILE" --cancel-manual
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

exit 0
