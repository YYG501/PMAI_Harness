#!/usr/bin/env bash
# Lint test: ensure skills/quick-fix/SKILL.md retains the drift-scan sections.
# Plan-eng-review F9 fix: prevent future SKILL.md refactor from accidentally
# dropping the drift-scan steps that were added to fix example-consumer-app Gap 2.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO_ROOT/skills/quick-fix/SKILL.md"

PASS=0
FAIL=0

assert_grep() {
  local pattern="$1"
  local desc="$2"
  if grep -qF "$pattern" "$SKILL"; then
    echo "  ✅ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ❌ FAIL: missing '$pattern' — $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "▶ test-quick-fix-skill: 校验 SKILL.md 保留偏差扫描相关节"
echo "─────────────────────────────────────────"

assert_grep "步骤 3.5：偏差扫描" "Workflow 步骤 3.5 存在"
assert_grep "## Drift Scan Reference" "Drift Scan Reference 独立 section 存在"
assert_grep "改动相关内容提示" "Layer 2 提示清单标题存在"
assert_grep "合同概念分类" "Layer 3 概念分类标题存在"
assert_grep "决策性 vs 轻量" "决策性/轻量 criterion 存在"
assert_grep "偏差扫描" "偏差扫描 关键词存在"
assert_grep "三条 invariant" "三条 invariant 索引存在"
assert_grep "分层 lazy sync" "分层 lazy sync 术语存在"
assert_grep "后期修订记录" "历史档案后期修订记录规则存在"

echo "─────────────────────────────────────────"
echo "  Suite: quick-fix-skill-lint"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "─────────────────────────────────────────"

[ "$FAIL" -eq 0 ]
