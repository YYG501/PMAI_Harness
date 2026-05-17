#!/usr/bin/env bash
# cursor-agent adapter. See docs/归档/完成/设计-执行者可选.md §4.3
#
# WARNING: cursor-agent --force --trust has NO sandbox. Boundary protection
# falls back entirely to the caller's post-execution越界 check.

set -euo pipefail

: "${TASK_WORKTREE:?TASK_WORKTREE required}"
: "${PROMPT_FILE:?PROMPT_FILE required}"
: "${TASK_FILE:?TASK_FILE required (for I-AD1/I-AD2 gate)}"
: "${MAIN_REPO_ROOT:?MAIN_REPO_ROOT required (for I-AD1/I-AD2 gate)}"

# I-AD1: 启动前状态 gate
source "$(dirname "$0")/_gate.sh"
adapter_precheck

PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

EXEC_EXIT=0
cursor-agent -p --force --trust \
  --workspace "$TASK_WORKTREE" \
  --output-format text \
  ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
  "$PROMPT" || EXEC_EXIT=$?

# I-AD2: 退出后越界校验（cursor-agent 无 sandbox，这层是唯一边界防护）
adapter_postcheck "$EXEC_EXIT"
