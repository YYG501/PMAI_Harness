#!/usr/bin/env bash
# Kimi Code build adapter.
#
# WARNING: kimi --auto fully approves tool use. /pmai-build must run its
# post-execution changed-path review before accepting the result.

set -euo pipefail

source "$(dirname "$0")/_gate.sh"
adapter_precheck

BUILD_DIR_RESOLVED="$(adapter_build_dir)"
PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

AGENT_ARGS=()
[ -n "${EXECUTOR_AGENT:-}" ] && AGENT_ARGS=(--agent "$EXECUTOR_AGENT")

AUTO_ARGS=()
if [ -z "${EXECUTOR_AUTO+x}" ] || adapter_truthy "$EXECUTOR_AUTO"; then
  AUTO_ARGS=(--auto)
fi

EXEC_EXIT=0
(
  cd "$BUILD_DIR_RESOLVED"
  kimi \
    --prompt "$PROMPT" \
    --output-format text \
    ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
    ${AGENT_ARGS[@]+"${AGENT_ARGS[@]}"} \
    ${AUTO_ARGS[@]+"${AUTO_ARGS[@]}"}
) || EXEC_EXIT=$?

adapter_postcheck "$EXEC_EXIT"
