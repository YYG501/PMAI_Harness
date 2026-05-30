#!/usr/bin/env bash
# gemini adapter. 照 cursor-agent.sh（无 sandbox 的 agent CLI）。
#
# WARNING: gemini --yolo 自动批准所有动作、NO sandbox。越界保护完全靠 caller 的
# 退出后越界检查（adapter_postcheck）。
#
# Inputs (env vars):
#   TASK_FILE, TASK_WORKTREE, PROMPT_FILE, EXECUTOR_MODEL, MAIN_REPO_ROOT
#
# Contract:
#   - changes land in TASK_WORKTREE, UNSTAGED (adapter does not git add/commit/checkout)
#   - stdout/stderr go to caller
#   - exit codes: 0=ok / other=unknown（gemini CLI 不细分，分类交 classify-failure）
#
# 注：gemini CLI 调用形态按已装版本可能需微调（-p/--prompt、-y/--yolo、-m/--model）。

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
gemini --yolo \
  ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
  --prompt "$PROMPT" || EXEC_EXIT=$?

# I-AD2: 退出后越界校验（gemini --yolo 无 sandbox，这层是唯一边界防护）
adapter_postcheck "$EXEC_EXIT"
