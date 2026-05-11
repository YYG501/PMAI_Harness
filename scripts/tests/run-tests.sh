#!/usr/bin/env bash
# scripts/tests/run-tests.sh: 回归测试 check-prd-hierarchy.py
#
# 用法: bash scripts/tests/run-tests.sh
# 退出码: 0 = 全过,1 = 至少一个失败

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LINT="$REPO_ROOT/scripts/check-prd-hierarchy.py"
TESTS_DIR="$REPO_ROOT/scripts/tests"

FAILED=0

echo "━━━ 测试 1: violations.md 应该 fail (类 1 + 类 2 全部触发) ━━━"
OUT=$(python3 "$LINT" "$TESTS_DIR/violations.md" 2>&1)
EXIT=$?
if [ "$EXIT" != "1" ]; then
    echo "❌ FAIL: violations.md exit code = $EXIT, 期望 1"
    echo "$OUT" | tail -20
    FAILED=1
else
    # 检查 5 类 + §六 层级都被抓到
    HAS_HIER=$(echo "$OUT" | grep -c "§六.*层级违规" || true)
    HAS_VISUAL=$(echo "$OUT" | grep -c "\[视觉细节\]" || true)
    HAS_URL=$(echo "$OUT" | grep -c "\[URL/技术细节\]" || true)
    HAS_PUNCT=$(echo "$OUT" | grep -c "\[排版分隔符\]" || true)
    HAS_NEG=$(echo "$OUT" | grep -c "\[否定式\]" || true)
    HAS_JARGON=$(echo "$OUT" | grep -c "\[工程黑话\]" || true)

    if [ "$HAS_HIER" -lt 1 ] || [ "$HAS_VISUAL" -lt 1 ] || [ "$HAS_URL" -lt 1 ] || \
       [ "$HAS_PUNCT" -lt 1 ] || [ "$HAS_NEG" -lt 1 ] || [ "$HAS_JARGON" -lt 1 ]; then
        echo "❌ FAIL: violations.md 没有触发全部 6 类 (层级/视觉/URL/排版/否定/工程黑话)"
        echo "    层级=$HAS_HIER 视觉=$HAS_VISUAL URL=$HAS_URL 排版=$HAS_PUNCT 否定=$HAS_NEG 工程黑话=$HAS_JARGON"
        FAILED=1
    else
        echo "✓ PASS: 6 类违规全部触发"
    fi
fi

echo
echo "━━━ 测试 2: clean.md 应该 pass (0 违规) ━━━"
OUT=$(python3 "$LINT" "$TESTS_DIR/clean.md" 2>&1)
EXIT=$?
if [ "$EXIT" != "0" ]; then
    echo "❌ FAIL: clean.md exit code = $EXIT, 期望 0"
    echo "$OUT" | head -30
    FAILED=1
else
    echo "✓ PASS: clean.md 通过 lint"
fi

echo
echo "━━━ 测试 3: lint 报告含具体改写建议 (hint) ━━━"
OUT=$(python3 "$LINT" "$TESTS_DIR/violations.md" 2>&1)
HAS_HINT=$(echo "$OUT" | grep -c "→ " || true)
if [ "$HAS_HINT" -lt 5 ]; then
    echo "❌ FAIL: lint 输出 hint 行 < 5, 期望每条违规都有改写建议"
    FAILED=1
else
    echo "✓ PASS: lint 输出含 $HAS_HINT 条 hint"
fi

echo
echo "━━━ 测试 4: lint 链回路径指向 _shared/pm-view (Pass 1 决议) ━━━"
OUT=$(python3 "$LINT" "$TESTS_DIR/violations.md" 2>&1)
HAS_SHARED=$(echo "$OUT" | grep -c "_shared/pm-view/writing-rules.md" || true)
if [ "$HAS_SHARED" -lt 1 ]; then
    echo "❌ FAIL: lint 输出没指向 _shared/pm-view/writing-rules.md"
    FAILED=1
else
    echo "✓ PASS: lint 链回路径指向 _shared/pm-view"
fi

echo
if [ "$FAILED" = "1" ]; then
    echo "━━━ 测试失败 ━━━"
    exit 1
else
    echo "━━━ 全部测试通过 ━━━"
    exit 0
fi
