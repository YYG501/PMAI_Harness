#!/usr/bin/env bash
# cursor-agent adapter. See 设计-执行者可选.md §4.3
#
# WARNING: cursor-agent --force --trust has NO sandbox. Boundary protection
# falls back entirely to the caller's post-execution越界 check.

set -euo pipefail

: "${TASK_WORKTREE:?TASK_WORKTREE required}"
: "${PROMPT_FILE:?PROMPT_FILE required}"

PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

cursor-agent -p --force --trust \
  --workspace "$TASK_WORKTREE" \
  --output-format text \
  "${MODEL_ARGS[@]}" \
  "$PROMPT"
