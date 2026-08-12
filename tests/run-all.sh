#!/usr/bin/env bash
# Run all invariant test suites. Exit non-zero if any suite fails.
# PMAI_SUITE_TIMEOUT_SECONDS overrides the default 300s per-suite timeout.
# PMAI_REQUIRE_SESSION_EVALS=1 makes missing eval runner/judge capabilities fatal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUITE_RUNNER="$SCRIPT_DIR/run-suite.py"
SUITE_TIMEOUT_SECONDS="${PMAI_SUITE_TIMEOUT_SECONDS:-300}"
CORE_SUITES=(
  test-check-branch.sh
  test-check-open-questions.sh
  test-atomic-file.sh
  test-measure-tthw.sh
  test-init-project.sh
  test-proposal-contract.sh
  test-proposal-skill.sh
  test-spec-profile-preset.sh
  test-project-definition.sh
  test-consumer-doctor.sh
  test-project-type.sh
  test-private-onboarding.sh
  test-generator-codex-entry.sh
  test-init-project-codex-compat.sh
  test-opencode-host-compat.sh
  test-kimi-host-compat.sh
  test-brownfield-detect.sh
  test-no-duplicate-questioning.sh
  test-shared-files-exist.sh
  test-project-design-system-contract.sh
  test-shared-currentness.sh
  test-loop-contract.sh
  test-term-detector.sh
  test-v2-currentness.sh
  test-design-shared-boundary.sh
  test-design-mockup-meta-routing.sh
  test-gstack-integration-contract.sh
  test-gstack-browser-diagnostics.sh
  test-whats-new.sh
  test-gstack-doc-return.sh
  test-meta-product-meta-thinking.sh
  test-meta-problem-framing.sh
  test-meta-v2-routes.sh
  test-doctor-skills.sh
  test-skill-link-ownership.sh
  test-feedback-skill.sh
  test-pm-facing-surface.sh
  test-skill-init-guard.sh
  test-writing-skill-routing.sh
  test-migrate-reqs-to-modules-compat.sh
  test-banner-label.sh
  test-narrative-mode.sh
  test-repo-kind.sh
  test-checks-diff.sh
  test-context-pack.sh
  test-legacy-recovery.sh
  test-personal-memory.sh
  test-acceptance-profile.sh
  test-browser-acceptance.sh
  test-build-timing.sh
  test-final-validation.sh
  test-finalize-candidate.sh
  test-finalize-work.sh
  test-build-maintenance-boundaries.sh
  test-prototype-boundary.sh
  test-doc-impact.sh
  test-build-contract.sh
  test-ready-contract.sh
  test-build-close-hard-gates.sh
  test-exec-adapters.sh
  test-mock-board.sh
  test-state-lib.sh
  test-attachments-helper.sh
  test-close-work.sh
  test-land-work-v2.sh
  test-skill-eval.sh
  test-run-suite.sh
  test-cleanup-pending.sh
  test-cancel-work.sh
  test-replan-work.sh
  test-status-view.sh
  test-active-build-context.sh
  test-active-build-guard.sh
  test-todo-guidance.sh
  test-docs-archive-convention.sh
  test-docs-toplevel-guard.sh
  test-setup-deps.sh
  test-run-bg.sh
  test-pre-commit-hook.sh
  test-mixed-delivery-guard.sh
  test-prd-hierarchy-lint.sh
  test-quick-fix-skill.sh
  quick-fix/test-happy-path.sh
  quick-fix/test-tsc-gate.sh
  quick-fix/test-build-mode.sh
  quick-fix/test-concurrent-work.sh
  quick-fix/test-redline-enforcement.sh
  quick-fix/test-cleanup.sh
  quick-fix/test-sanitize.sh
)
OPTIONAL_LARK_SUITES=(
  test-lark-adapter.sh
  test-lark-cli-lint.sh
  test-lark-entry-routing.sh
  test-lark-review.sh
  test-publish-to-lark-e2e.sh
  test-publish-to-lark-rowspan-merge.sh
)
SUITES=("${CORE_SUITES[@]}")
if [ "${PMAI_SKIP_OPTIONAL_LARK_TESTS:-0}" != "1" ]; then
  SUITES+=("${OPTIONAL_LARK_SUITES[@]}")
fi

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()
RESULT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pmai-run-all.XXXXXX")
trap 'rm -rf "$RESULT_DIR"' EXIT

if ! [[ "$SUITE_TIMEOUT_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] || \
   ! python3 - "$SUITE_TIMEOUT_SECONDS" <<'PY'
import sys
raise SystemExit(0 if float(sys.argv[1]) > 0 else 1)
PY
then
  echo "Invalid PMAI_SUITE_TIMEOUT_SECONDS: $SUITE_TIMEOUT_SECONDS" >&2
  exit 2
fi

for s in "${SUITES[@]}"; do
  echo ""
  echo "▶ Running $s"
  echo "─────────────────────────────────────────"
  result_file="$RESULT_DIR/${s//\//__}.json"
  python3 "$SUITE_RUNNER" --timeout "$SUITE_TIMEOUT_SECONDS" \
    --result-file "$result_file" -- bash "$SCRIPT_DIR/$s"
  rc=$?
  if [ -f "$result_file" ]; then
    if counts=$(python3 - "$result_file" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if not isinstance(result.get("passed"), int) or not isinstance(result.get("failed"), int):
    raise SystemExit("suite result counts must be integers")
print(result["passed"], result["failed"])
PY
    ); then
      read -r p f <<< "$counts"
    else
      p=0
      f=1
      rc=1
      echo "RUNNER ERROR: suite 结果文件损坏: $s" >&2
    fi
  else
    p=0
    f=1
    rc=1
    echo "RUNNER ERROR: suite 未生成结果文件: $s" >&2
  fi
  TOTAL_PASS=$((TOTAL_PASS + p))
  TOTAL_FAIL=$((TOTAL_FAIL + f))
  if [ "$rc" -ne 0 ]; then
    FAILED_SUITES+=("$s")
  fi
done

echo ""
echo "▶ Running deterministic + session skill evals"
echo "─────────────────────────────────────────"
EVAL_ARGS=(--mode all)
if [ "${PMAI_REQUIRE_SESSION_EVALS:-0}" = "1" ]; then
  EVAL_ARGS+=(--require-runner --require-judge)
fi
EVAL_OUTPUT=$(python3 "$REPO_ROOT/scripts/skill-eval.py" "${EVAL_ARGS[@]}" 2>&1)
EVAL_RC=$?
printf "%s\n" "$EVAL_OUTPUT"
if EVAL_COUNTS=$(printf "%s\n" "$EVAL_OUTPUT" | python3 \
  "$SCRIPT_DIR/parse-skill-eval-summary.py" --exit-code "$EVAL_RC"); then
  read -r _ EVAL_FAILED _ _ <<< "$EVAL_COUNTS"
  if [ "$EVAL_FAILED" -gt 0 ]; then
    TOTAL_FAIL=$((TOTAL_FAIL + EVAL_FAILED))
    FAILED_SUITES+=("skill-eval:all")
  fi
else
  echo "RUNNER ERROR: skill eval 摘要与退出状态不可信" >&2
  TOTAL_FAIL=$((TOTAL_FAIL + 1))
  FAILED_SUITES+=("skill-eval:all")
fi

echo ""
echo "═════════════════════════════════════════"
echo "  Total Passed: $TOTAL_PASS"
echo "  Total Failed: $TOTAL_FAIL"
echo "═════════════════════════════════════════"

if [ "$TOTAL_FAIL" -gt 0 ] || [ ${#FAILED_SUITES[@]} -gt 0 ]; then
  echo ""
  echo "Failing suites:"
  for s in "${FAILED_SUITES[@]}"; do echo "  - $s"; done
  exit 1
fi
exit 0
