#!/usr/bin/env bash
# Stable releases require the deterministic suite plus real session runner/judge evidence.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_COMMAND="${PMAI_SKILL_EVAL_RUNNER:-}"
JUDGE_COMMAND="${PMAI_SKILL_EVAL_JUDGE:-}"
SEMANTIC_JUDGE_COMMAND="${PMAI_SKILL_EVAL_SEMANTIC_JUDGE:-}"

missing=()
if [ -z "${RUNNER_COMMAND//[[:space:]]/}" ]; then
  missing+=(PMAI_SKILL_EVAL_RUNNER)
fi
if [ -z "${JUDGE_COMMAND//[[:space:]]/}" ]; then
  missing+=(PMAI_SKILL_EVAL_JUDGE)
fi
if [ -z "${SEMANTIC_JUDGE_COMMAND//[[:space:]]/}" ]; then
  missing+=(PMAI_SKILL_EVAL_SEMANTIC_JUDGE)
fi
if [ ${#missing[@]} -gt 0 ]; then
  printf 'Release gate blocked: missing %s\n' "${missing[*]}" >&2
  echo "Stable tags require a real runner, independent evidence judge and semantic judge; required cases may not be skipped." >&2
  exit 2
fi

export PMAI_REQUIRE_SESSION_EVALS=1
export PMAI_REQUIRE_SEMANTIC_JUDGE=1
selected_cases=$(python3 "$SCRIPT_DIR/../scripts/release-gate-preflight.py" --cases-only)
export PMAI_SESSION_EVAL_CASES="$selected_cases"
python3 "$SCRIPT_DIR/../scripts/release-gate-preflight.py"
export PMAI_SKIP_OPTIONAL_LARK_TESTS=1
exec bash "$SCRIPT_DIR/run-all.sh"
