#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVAL="$REPO_ROOT/scripts/skill-eval.py"
FAKE="$REPO_ROOT/tests/fixtures/fake-skill-eval.py"

test_schema_and_static_cases() {
  start_test "skill-eval: schema、touchfiles 与静态案例"
  if python3 "$EVAL" --mode validate >/tmp/skill-eval.$$ 2>&1 && \
     python3 "$EVAL" --mode static >>/tmp/skill-eval.$$ 2>&1; then
    pass_test
  else
    _fail "schema/static should pass"
    cat /tmp/skill-eval.$$ >&2
  fi
}

test_missing_runner_is_explicit() {
  start_test "skill-eval: runner 缺失时显式 skip，gate 模式显式 fail"
  if ! python3 "$EVAL" --mode session --case natural-language-finalize >/tmp/skill-eval-skip.$$ 2>&1; then
    _fail "default missing runner should skip without failing"
    return
  fi
  if ! grep -q "SKIP natural-language-finalize: session runner 未配置" /tmp/skill-eval-skip.$$; then
    _fail "missing runner skip should be visible"
    return
  fi
  if python3 "$EVAL" --mode session --case natural-language-finalize --require-runner >/tmp/skill-eval-required.$$ 2>&1; then
    _fail "required missing runner should fail"
    return
  fi
  if ! grep -q "FAIL natural-language-finalize: session runner 未配置" /tmp/skill-eval-required.$$; then
    _fail "required missing runner failure should be visible"
    return
  fi
  pass_test
}

test_runner_and_judge_protocol() {
  start_test "skill-eval: runner/judge 结果合同与落盘"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-eval.XXXXXX")
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE" \
      --judge-command "python3 $FAKE" \
      --require-runner --require-judge --results-dir "$T" >/tmp/skill-eval-run.$$ 2>&1 && \
      [ -f "$T/natural-language-finalize.json" ]; then
    pass_test
  else
    _fail "runner/judge protocol should pass and persist evidence"
    cat /tmp/skill-eval-run.$$ >&2
  fi
  rm -rf "$T"
}

test_schema_and_static_cases
test_missing_runner_is_explicit
test_runner_and_judge_protocol
report_results "skill-eval"
