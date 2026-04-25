#!/usr/bin/env bash
# Run all invariant test suites. Exit non-zero if any suite fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUITES=(
  test-check-branch.sh
  test-task-transition.sh
  test-task-spec.sh
  test-task-plan.sh
  test-doc-update.sh
  test-req-stage-gate.sh
  test-req-transition.sh
  test-close-task.sh
  test-close-req.sh
  test-cancel-req.sh
  test-status-view.sh
  quick-fix/test-happy-path.sh
  quick-fix/test-tsc-gate.sh
  quick-fix/test-concurrent-req.sh
  quick-fix/test-redline-enforcement.sh
  quick-fix/test-cleanup.sh
  quick-fix/test-sanitize.sh
  e2e/test-full-task-loop.sh
  e2e/test-doc-update-failure-recovery.sh
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
