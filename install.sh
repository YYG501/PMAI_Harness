#!/usr/bin/env bash
# install.sh — PMAI 一行安装入口
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash
#
# 或带 flag 透传给 pmai install（如 --local <dir>）：
#   curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash -s -- --local /Users/me/myproj
#
# 做的事：
#   1. 检查依赖（git / bash / python3）
#   2. git clone PMAI 到临时目录（SSH 失败 fallback HTTPS）
#   3. 跑 bash bin/pmai install [透传 args]
#   4. 清临时目录（成功 / 失败都清）
#
# Env override:
#   PMAI_REMOTE=<git-url>    # 覆盖默认 SSH 远程（本脚本会自动 fallback HTTPS）

set -euo pipefail

# ─── 默认配置 ─────────────────────────────────────────────────
DEFAULT_SSH_REMOTE="git@github.com:YYG501/PMAI_Workflow.git"
DEFAULT_HTTPS_REMOTE="https://github.com/YYG501/PMAI_Workflow.git"
SSH_REMOTE="${PMAI_REMOTE:-$DEFAULT_SSH_REMOTE}"
HTTPS_REMOTE="$DEFAULT_HTTPS_REMOTE"
SRC=$(mktemp -d "/tmp/pmai-installer-XXXXXX")

cleanup() {
  rm -rf "$SRC" 2>/dev/null || true
}
trap cleanup EXIT

echo "════════════════════════════════════════════════════════════"
echo "  PMAI 一行安装"
echo "════════════════════════════════════════════════════════════"

# ─── 1. 依赖检查 ──────────────────────────────────────────────
echo "→ 检查依赖（git / bash / python3）..."
MISSING=()
for dep in git bash python3; do
  command -v "$dep" >/dev/null 2>&1 || MISSING+=("$dep")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ 缺依赖：${MISSING[*]}" >&2
  echo "   先装齐再跑：" >&2
  echo "     macOS: brew install git python3" >&2
  echo "     Linux: apt install git python3" >&2
  exit 1
fi
echo "   ✓ 依赖齐"

# ─── 2. clone repo（SSH 优先 → HTTPS fallback）────────────────
echo "→ Clone PMAI 到临时目录 $SRC ..."
CLONE_TARGET="$SRC/pmai-src"

if git clone "$SSH_REMOTE" "$CLONE_TARGET" 2>"$SRC/.ssh-err"; then
  echo "   ✓ SSH clone 成功"
  USED_REMOTE="$SSH_REMOTE"
else
  echo "   ⚠️  SSH 失败，回退 HTTPS..."
  if git clone "$HTTPS_REMOTE" "$CLONE_TARGET" 2>"$SRC/.https-err"; then
    echo "   ✓ HTTPS clone 成功"
    USED_REMOTE="$HTTPS_REMOTE"
    # 设 env 让 pmai install 内部 git clone 也走 HTTPS
    export PMAI_REMOTE="$HTTPS_REMOTE"
  else
    echo "❌ Clone PMAI 失败：SSH 和 HTTPS 都不通。" >&2
    echo "   SSH stderr：" >&2
    sed 's/^/     /' "$SRC/.ssh-err" >&2
    echo "   HTTPS stderr：" >&2
    sed 's/^/     /' "$SRC/.https-err" >&2
    echo "" >&2
    echo "   常见原因：" >&2
    echo "     1. 网络不通" >&2
    echo "     2. SSH key 未配（私有仓只能 SSH 拉 → 先在 GitHub 加 SSH key）" >&2
    echo "     3. private repo 但 HTTPS 也需要 token" >&2
    exit 1
  fi
fi

# ─── 3. 跑 pmai install ───────────────────────────────────────
echo ""
echo "→ Run: bash $CLONE_TARGET/bin/pmai install $*"
echo ""
bash "$CLONE_TARGET/bin/pmai" install "$@"

# ─── 4. 完成 ──────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ PMAI 一行安装完成"
echo "   Source remote: $USED_REMOTE"
echo "   Installer 临时目录已清（不影响 ~/.pmai/）"
echo "════════════════════════════════════════════════════════════"
