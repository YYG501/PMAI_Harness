#!/usr/bin/env bash
# codex adapter. See 设计-执行者可选.md §4.2
#
# Inputs (env vars):
#   TASK_FILE, TASK_WORKTREE, PROMPT_FILE, EXECUTOR_MODEL, MAIN_REPO_ROOT
#
# Contract:
#   - changes land in TASK_WORKTREE, UNSTAGED (adapter does not git add/commit/checkout)
#   - stdout/stderr go to caller
#   - exit codes: 0=ok / 10=sandbox / 11=model / 12=network / other=unknown

set -euo pipefail

: "${TASK_WORKTREE:?TASK_WORKTREE required}"
: "${PROMPT_FILE:?PROMPT_FILE required}"
: "${TASK_FILE:?TASK_FILE required (for I-AD1/I-AD2 gate)}"
: "${MAIN_REPO_ROOT:?MAIN_REPO_ROOT required (for I-AD1/I-AD2 gate)}"

# I-AD1: 启动前状态 gate
source "$(dirname "$0")/_gate.sh"
adapter_precheck

cd "$TASK_WORKTREE"
PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

EXEC_EXIT=0
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  echo "codex.sh: CLAUDE_PLUGIN_ROOT not set; falling back to plain 'codex exec --sandbox workspace-write'" >&2
  codex exec --sandbox workspace-write ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT" || EXEC_EXIT=$?
else
  node "${CLAUDE_PLUGIN_ROOT}/scripts/codex-companion.mjs" task --write ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT" || EXEC_EXIT=$?
fi

# I-AD2: 退出后越界校验
adapter_postcheck "$EXEC_EXIT"
