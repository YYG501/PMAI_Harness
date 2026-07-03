#!/usr/bin/env bash
# codex build adapter.
#
# Inputs:
#   BUILD_DIR or TASK_WORKTREE, PROMPT_FILE, EXECUTOR_MODEL(optional)
#
# Contract:
#   - changes land in BUILD_DIR, unstaged
#   - adapter does not git add / commit / checkout

set -euo pipefail

source "$(dirname "$0")/_gate.sh"
adapter_precheck

BUILD_DIR_RESOLVED="$(adapter_build_dir)"
PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

SANDBOX="${EXECUTOR_SANDBOX:-workspace-write}"

EXEC_EXIT=0
(
  cd "$BUILD_DIR_RESOLVED"
  codex exec --sandbox "$SANDBOX" ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT"
) || EXEC_EXIT=$?

adapter_postcheck "$EXEC_EXIT"
