#!/usr/bin/env bash
# Claude Code build adapter.
#
# WARNING: bypassPermissions has no sandbox. /pmai-build must run its
# post-execution changed-path review before accepting the result.

set -euo pipefail

source "$(dirname "$0")/_gate.sh"
adapter_precheck

BUILD_DIR_RESOLVED="$(adapter_build_dir)"
PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

EXEC_EXIT=0
(
  cd "$BUILD_DIR_RESOLVED"
  claude -p \
    --permission-mode bypassPermissions \
    --output-format text \
    --no-session-persistence \
    ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
    "$PROMPT"
) || EXEC_EXIT=$?

adapter_postcheck "$EXEC_EXIT"
