#!/usr/bin/env bash
# OpenCode build adapter.
#
# WARNING: opencode --auto may approve tool use. /pmai-build must run its
# post-execution changed-path review before accepting the result.

set -euo pipefail

source "$(dirname "$0")/_gate.sh"
adapter_precheck

BUILD_DIR_RESOLVED="$(adapter_build_dir)"
PROMPT="$(cat "$PROMPT_FILE")"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

VARIANT_ARGS=()
VARIANT="${EXECUTOR_VARIANT:-${EXECUTOR_THINKING:-}}"
[ -n "$VARIANT" ] && VARIANT_ARGS=(--variant "$VARIANT")

AGENT_ARGS=()
[ -n "${EXECUTOR_AGENT:-}" ] && AGENT_ARGS=(--agent "$EXECUTOR_AGENT")

AUTO_ARGS=()
adapter_truthy "${EXECUTOR_AUTO:-}" && AUTO_ARGS=(--auto)

EXEC_EXIT=0
opencode run \
  --dir "$BUILD_DIR_RESOLVED" \
  ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
  ${VARIANT_ARGS[@]+"${VARIANT_ARGS[@]}"} \
  ${AGENT_ARGS[@]+"${AGENT_ARGS[@]}"} \
  ${AUTO_ARGS[@]+"${AUTO_ARGS[@]}"} \
  "$PROMPT" || EXEC_EXIT=$?

adapter_postcheck "$EXEC_EXIT"
