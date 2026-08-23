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
  echo "Stable tags require a real session runner and independent judge; selected session cases may not be skipped." >&2
  exit 2
fi

export PMAI_REQUIRE_SESSION_EVALS=1
export PMAI_SESSION_EVAL_CASES="${PMAI_SESSION_EVAL_CASES:-natural-language-finalize}"
export PMAI_SKIP_OPTIONAL_LARK_TESTS=1
exec bash "$SCRIPT_DIR/run-all.sh"
