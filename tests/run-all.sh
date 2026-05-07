#!/usr/bin/env bash
# Run all invariant test suites. Exit non-zero if any suite fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUITES=(
  test-check-branch.sh
  test-task-transition.sh
  test-fixture-v2.sh
  test-check-req-doc-drift.sh
  test-check-task-scope.sh
  test-structure-schema.sh
  test-detect-project-structure.sh
  test-inject-structure.sh
  test-depth-change-section.sh
  test-task-spec-prose-merge.sh
  test-business-deviation.sh
  test-task-spec.sh
  test-task-pm-feedback.sh
  test-task-plan.sh
  test-doc-update.sh
  test-req-stage-gate.sh
  test-req-transition.sh
  test-close-task.sh
  test-close-task-design-feedback.sh
  test-close-task-alignment.sh
  test-task-md-ownership.sh
  test-close-req.sh
  test-cleanup-pending.sh
  test-cancel-req.sh
  test-status-view.sh
  test-setup-deps.sh
  test-run-bg.sh
  test-pre-commit-hook.sh
  v4_T13_status_summary.sh
  v4_T14_taskexec_short_id.sh
  v4_T16_taskexec_double_scan.sh
  v4_T23_dependency_gate.sh
  quick-fix/test-happy-path.sh
  quick-fix/test-tsc-gate.sh
  quick-fix/test-concurrent-req.sh
  quick-fix/test-redline-enforcement.sh
  quick-fix/test-cleanup.sh
  quick-fix/test-sanitize.sh
  e2e/test-full-task-loop.sh
  e2e/test-doc-update-failure-recovery.sh
  e2e/test-skip-doc-update-recovery.sh
  e2e/test-pushback-loop.sh
  e2e/v4_T22_single_window_lifecycle.sh
)

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

for s in "${SUITES[@]}"; do
  echo ""
  echo "▶ Running $s"
  echo "─────────────────────────────────────────"
  if bash "$SCRIPT_DIR/$s"; then
    # Parse summary line from output
    out=$(bash "$SCRIPT_DIR/$s" 2>&1)
    p=$(echo "$out" | awk '/Passed:/ {print $2}' | tail -1)
    f=$(echo "$out" | awk '/Failed:/ {print $2}' | tail -1)
    TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
    TOTAL_FAIL=$((TOTAL_FAIL + ${f:-0}))
  else
    FAILED_SUITES+=("$s")
    out=$(bash "$SCRIPT_DIR/$s" 2>&1 || true)
    p=$(echo "$out" | awk '/Passed:/ {print $2}' | tail -1)
    f=$(echo "$out" | awk '/Failed:/ {print $2}' | tail -1)
    TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
    TOTAL_FAIL=$((TOTAL_FAIL + ${f:-0}))
  fi
done

echo ""
echo "═════════════════════════════════════════"
echo "  Total Passed: $TOTAL_PASS"
echo "  Total Failed: $TOTAL_FAIL"
echo "═════════════════════════════════════════"

if [ ${#FAILED_SUITES[@]} -gt 0 ]; then
  echo ""
  echo "Failing suites:"
  for s in "${FAILED_SUITES[@]}"; do echo "  - $s"; done
  exit 1
fi
exit 0
