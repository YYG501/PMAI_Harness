#!/usr/bin/env bash
# test-docs-toplevel-guard.sh
#
# 验证 docs/ 顶层归档约定守卫（PM 选 B 方案 — pre-commit hook 强制拦截）：
#   T1: check-docs-toplevel.py 存在
#   T2: 白名单文件被允许（INDEX/CONTEXT）
#   T3: 错位文件被拦下（exit 1）
#   T4: docs/modules/ 下文件不影响（不算顶层）
#   T5: docs/archive/ 下文件不影响
#   T6: .docs-toplevel-allow 自定义白名单生效
#   T7: pre-commit.tmpl 含调用 check-docs-toplevel.py
#   T8: 非 .md 文件（如图片）不被拦
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-docs-toplevel.py"
HOOK_TMPL="$REPO_ROOT/templates/git-hooks/pre-commit.tmpl"

# -----------------------------------------------------------------
test_checker_exists() {
  start_test "T1: scripts/check-docs-toplevel.py 存在"
  if [ ! -f "$CHECKER" ]; then
    _fail "scripts/check-docs-toplevel.py 不存在"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_whitelist_passes() {
  start_test "T2: 白名单文件（INDEX/CONTEXT）被允许"
  local tmp; tmp=$(mktemp -d)
  for f in INDEX.md CONTEXT.md; do
    if ! python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/$f" >/dev/null 2>&1; then
      _fail "白名单 docs/$f 应被允许，实际被拦下"
      rm -rf "$tmp"; return
    fi
  done
  for f in PRODUCT.md PRODUCT-STATE.md DESIGN.md PRODUCT-RULES.md TODO.md; do
    if python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/$f" >/dev/null 2>&1; then
      _fail "主文件 docs/$f 不应被允许，应放仓库根目录"
      rm -rf "$tmp"; return
    fi
  done
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
test_misplaced_blocked() {
  start_test "T3: 错位文件被拦下 (exit 1)"
  local tmp; tmp=$(mktemp -d)
  local out
  if out=$(python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/product-principles.md" 2>&1); then
    _fail "docs/product-principles.md 应被拦下，实际过了"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q '项目级业务概览'; then
    _fail "拦下提示缺白名单引导，输出：$out"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q 'docs/archive/'; then
    _fail "拦下提示缺归位路径，输出：$out"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q 'docs/modules/<按内容命名>.md'; then
    _fail "拦下提示缺功能型规格文档归位路径，输出：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
test_modules_subdir_unaffected() {
  start_test "T4: docs/modules/ 下文件不算顶层，不被拦"
  local tmp; tmp=$(mktemp -d)
  if ! python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/modules/auth/login.md" >/dev/null 2>&1; then
    _fail "docs/modules/auth/login.md 不该被拦（不是顶层）"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
test_archive_subdir_unaffected() {
  start_test "T5: docs/archive/ 下文件不被拦"
  local tmp; tmp=$(mktemp -d)
  if ! python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/archive/PROTOTYPE_CLEANUP.md" >/dev/null 2>&1; then
    _fail "docs/archive/PROTOTYPE_CLEANUP.md 不该被拦"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
test_repo_allow_works() {
  start_test "T6: .docs-toplevel-allow 自定义白名单生效"
  local tmp; tmp=$(mktemp -d)
  cat > "$tmp/.docs-toplevel-allow" <<'EOF'
# 项目级业务概览（PM 自定义放行）
ops-platform-unification.md
product-strategy.md
EOF
  if ! python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/ops-platform-unification.md" >/dev/null 2>&1; then
    _fail "自定义白名单中的 docs/ops-platform-unification.md 应被允许"
    rm -rf "$tmp"; return
  fi
  # 同时验证不在白名单的还是被拦
  if python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/random-rfc.md" >/dev/null 2>&1; then
    _fail "不在白名单的 docs/random-rfc.md 应被拦"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
test_hook_tmpl_invokes_checker() {
  start_test "T7: pre-commit.tmpl 含调用 check-docs-toplevel.py"
  if ! grep -q 'check-docs-toplevel.py' "$HOOK_TMPL"; then
    _fail "templates/git-hooks/pre-commit.tmpl 缺 check-docs-toplevel.py 调用"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_non_md_files_unaffected() {
  start_test "T8: docs/ 顶层非 .md 文件（图片等）不被拦"
  local tmp; tmp=$(mktemp -d)
  if ! python3 "$CHECKER" --repo-root "$tmp" --from-paths "docs/logo.png" >/dev/null 2>&1; then
    _fail "docs/logo.png 不该被拦（非 .md 不在归档约定范围）"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------

test_checker_exists
test_whitelist_passes
test_misplaced_blocked
test_modules_subdir_unaffected
test_archive_subdir_unaffected
test_repo_allow_works
test_hook_tmpl_invokes_checker
test_non_md_files_unaffected

report_results "docs-toplevel-guard"
