#!/usr/bin/env bash
# install-hooks.sh — 给已 init 的项目（或本仓自身）补装 pre-commit hook。
# 用法（在项目根运行）：
#   bash $HOME/.pmai/scripts/install-hooks.sh [--check]
# 或在框架仓里：
#   bash scripts/install-hooks.sh
#
# 行为：
#   1. 找出 hook 模板（优先 $HOME/.pmai/scripts/../../templates/git-hooks/，
#      回退到框架仓 templates/git-hooks/）
#   2. 复制到 .git/hooks/pre-commit
#   3. chmod +x
#   4. 已存在 hook 时 .bak 备份再覆盖
#
# 不破坏 --no-verify 救火路径（git 内置）。

set -euo pipefail

MODE="install"
case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  --help|-h)
    echo "Usage: install-hooks.sh [--check]"
    echo "  --check  Read-only comparison; exit 0 when current, 1 when stale or missing."
    exit 0
    ;;
  *) echo "❌ unknown flag: $1" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo "❌ 参数过多" >&2; exit 2; }

# 识别 git common dir（worktree 安全）
GIT_COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null)"
if [ -z "$GIT_COMMON_DIR" ]; then
  echo "❌ 当前目录不在 git 仓内。请在项目根目录运行。" >&2
  exit 2
fi
# 转绝对路径
case "$GIT_COMMON_DIR" in
  /*) ;;
  *) GIT_COMMON_DIR="$(cd "$GIT_COMMON_DIR" && pwd)" ;;
esac

HOOKS_DIR="$GIT_COMMON_DIR/hooks"
if [ "$MODE" = "install" ]; then
  mkdir -p "$HOOKS_DIR"
fi

# 找模板：3 candidate 兼容老 / 新 / I-mini 跨机器场景
#   1. $SCRIPT_DIR/../../templates/git-hooks/  （老消费仓自带副本：$HOME/.pmai/scripts/install-hooks.sh）
#   2. $SCRIPT_DIR/../templates/git-hooks/     （框架本仓 scripts/install-hooks.sh）
#   3. ${PMAI_HOME:-$HOME/.pmai}/templates/git-hooks/  （I-mini 新消费仓：消费仓 0 framework 时）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPL=""
for CANDIDATE in \
  "$SCRIPT_DIR/../../templates/git-hooks/pre-commit.tmpl" \
  "$SCRIPT_DIR/../templates/git-hooks/pre-commit.tmpl" \
  "${PMAI_HOME:-$HOME/.pmai}/templates/git-hooks/pre-commit.tmpl"
do
  if [ -f "$CANDIDATE" ]; then
    TMPL="$CANDIDATE"
    break
  fi
done

if [ -z "$TMPL" ]; then
  echo "❌ 找不到 pre-commit 模板：尝试过 $SCRIPT_DIR/../../templates/git-hooks/、$SCRIPT_DIR/../templates/git-hooks/ 与 \$PMAI_HOME/templates/git-hooks/" >&2
  exit 1
fi

DEST="$HOOKS_DIR/pre-commit"

if [ "$MODE" = "check" ]; then
  if [ -f "$DEST" ] && [ ! -L "$DEST" ] && [ -x "$DEST" ] && cmp -s "$TMPL" "$DEST"; then
    echo "OK: PMAI pre-commit hook matches current template"
    exit 0
  fi
  echo "DRIFT: PMAI pre-commit hook is missing, stale, non-executable, or a symlink" >&2
  exit 1
fi

if [ -f "$DEST" ]; then
  # 已是同模板内容则跳过
  if cmp -s "$TMPL" "$DEST"; then
    echo "✅ pre-commit hook 已是最新版（无需重装）：$DEST"
    exit 0
  fi
  BAK="$DEST.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$DEST" "$BAK"
  echo "📦 已备份原 hook 到：$BAK"
fi

cp "$TMPL" "$DEST"
chmod +x "$DEST"
echo "✅ pre-commit hook 已安装：$DEST"
echo "   职责：检查 docs/ 顶层归档约定，并对 attachments/ 大文件给出 warning。"
echo "   救火绕过：git commit --no-verify"
