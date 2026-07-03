#!/usr/bin/env bash
# cursor-agent build adapter.
#
# WARNING: cursor-agent --force --trust has no sandbox. /pmai-build must run its
# post-execution changed-path review before accepting the result.

set -euo pipefail

source "$(dirname "$0")/_gate.sh"
adapter_precheck

BUILD_DIR_RESOLVED="$(adapter_build_dir)"
PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

FORCE_ARGS=()
if [ -z "${EXECUTOR_FORCE+x}" ] || adapter_truthy "$EXECUTOR_FORCE"; then
  FORCE_ARGS=(--force)
fi

TRUST_ARGS=()
if [ -z "${EXECUTOR_TRUST_WORKSPACE+x}" ] || adapter_truthy "$EXECUTOR_TRUST_WORKSPACE"; then
  TRUST_ARGS=(--trust)
fi

EXEC_EXIT=0
cursor-agent -p \
  --workspace "$BUILD_DIR_RESOLVED" \
  --output-format text \
  ${FORCE_ARGS[@]+"${FORCE_ARGS[@]}"} \
  ${TRUST_ARGS[@]+"${TRUST_ARGS[@]}"} \
  ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
  "$PROMPT" || EXEC_EXIT=$?

adapter_postcheck "$EXEC_EXIT"
