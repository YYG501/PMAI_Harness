#!/usr/bin/env bash
# Stable releases require the deterministic suite plus real session runner/judge evidence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_COMMAND="${PMAI_SKILL_EVAL_RUNNER:-}"
JUDGE_COMMAND="${PMAI_SKILL_EVAL_JUDGE:-}"

missing=()
if [ -z "${RUNNER_COMMAND//[[:space:]]/}" ]; then
  missing+=(PMAI_SKILL_EVAL_RUNNER)
fi
if [ -z "${JUDGE_COMMAND//[[:space:]]/}" ]; then
  missing+=(PMAI_SKILL_EVAL_JUDGE)
fi
if [ ${#missing[@]} -gt 0 ]; then
  printf 'Release gate blocked: missing %s\n' "${missing[*]}" >&2
  echo "Stable tags require a real session runner and independent judge; skipped session evals are not release evidence." >&2
  exit 2
fi

export PMAI_REQUIRE_SESSION_EVALS=1
exec bash "$SCRIPT_DIR/run-all.sh"
