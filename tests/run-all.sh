#!/usr/bin/env bash
# Run all invariant test suites. Exit non-zero if any suite fails.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUITES=(
  test-check-branch.sh
    test-check-open-questions.sh
  test-lark-adapter.sh
  test-lark-cli-lint.sh
  test-lark-sync-skill.sh
  test-publish-to-lark-e2e.sh
  test-measure-tthw.sh
  test-init-project.sh
  test-project-definition.sh
  test-project-type.sh
  test-project-sections-root.sh
  test-private-onboarding.sh
  test-generator-codex-entry.sh
  test-init-project-codex-compat.sh
  test-opencode-host-compat.sh
  test-brownfield-detect.sh
  test-no-duplicate-questioning.sh
  test-shared-files-exist.sh
  test-shared-currentness.sh
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
  test-skill-init-guard.sh
  test-writing-skill-routing.sh
  test-migrate-reqs-to-modules-compat.sh
  test-banner-label.sh
  test-narrative-mode.sh
          test-checks-diff.sh
  test-context-pack.sh
  test-personal-memory.sh
  test-acceptance-profile.sh
  test-prototype-boundary.sh
  test-doc-impact.sh
  test-build-contract.sh
  test-build-close-hard-gates.sh
  test-exec-adapters.sh
  test-mock-board.sh
    test-state-lib.sh
  test-attachments-helper.sh
  test-close-work.sh
  test-land-work-v2.sh
  test-skill-eval.sh
  test-cleanup-pending.sh
  test-cancel-work.sh
  test-status-view.sh
  test-todo-guidance.sh
  test-docs-archive-convention.sh
  test-docs-toplevel-guard.sh
  test-setup-deps.sh
  test-run-bg.sh
  test-pre-commit-hook.sh
  test-mixed-delivery-guard.sh
  test-prd-hierarchy-lint.sh
  test-publish-to-lark-rowspan-merge.sh
  test-quick-fix-skill.sh
  quick-fix/test-happy-path.sh
  quick-fix/test-tsc-gate.sh
  quick-fix/test-build-mode.sh
  quick-fix/test-concurrent-work.sh
  quick-fix/test-redline-enforcement.sh
  quick-fix/test-cleanup.sh
  quick-fix/test-sanitize.sh
)

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=()

for s in "${SUITES[@]}"; do
  echo ""
  echo "▶ Running $s"
  echo "─────────────────────────────────────────"
  out=$(bash "$SCRIPT_DIR/$s" 2>&1)
  rc=$?
  printf "%s\n" "$out"
  p=$(echo "$out" | awk '/Passed:/ {print $2}' | tail -1)
  f=$(echo "$out" | awk '/Failed:/ {print $2}' | tail -1)
  TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${f:-0}))
  if [ "$rc" -ne 0 ]; then
    FAILED_SUITES+=("$s")
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
