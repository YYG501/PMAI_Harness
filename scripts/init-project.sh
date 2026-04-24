#!/usr/bin/env bash
# init-project.sh — 创建新业务项目
# 用法: bash scripts/init-project.sh <project-name> <target-dir> <background>
# 必须从框架仓库根目录运行

set -euo pipefail

PROJECT_NAME="${1:?用法: init-project.sh <project-name> <target-dir> <background>}"
TARGET_DIR="${2:?用法: init-project.sh <project-name> <target-dir> <background>}"
BACKGROUND="${3:-}"

FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- a. 检测 gstack ---
if ! command -v gstack &>/dev/null; then
  # 检查 gstack skill 目录
  if [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "❌ gstack 未安装。请先安装 gstack：" >&2
    echo "   参考：https://github.com/garrytan/gstack" >&2
    exit 1
  fi
fi
echo "✅ gstack 已检测到"

# --- b. 检测 gstack 版本（警告但不阻塞）---
GSTACK_VERSION=""
if [ -f "$HOME/.claude/skills/gstack/VERSION" ]; then
  GSTACK_VERSION=$(cat "$HOME/.claude/skills/gstack/VERSION" 2>/dev/null || echo "unknown")
  echo "📦 gstack 版本: $GSTACK_VERSION"
fi

# --- c. 创建项目目录 ---
if [ -d "$TARGET_DIR" ]; then
  echo "❌ 目标目录已存在: $TARGET_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"
echo "📁 创建项目目录: $TARGET_DIR"

# --- d. 复制模板 + 替换占位符 ---
for TMPL in "$FRAMEWORK_DIR/templates/"*.tmpl; do
  BASENAME=$(basename "$TMPL" .tmpl)
  # 确定目标位置
  case "$BASENAME" in
    CLAUDE.md)     DEST="$TARGET_DIR/CLAUDE.md" ;;
    CONTEXT.md)    DEST="$TARGET_DIR/docs/CONTEXT.md" ;;
    DESIGN.md)     DEST="$TARGET_DIR/docs/DESIGN.md" ;;
    prd.md)        DEST="$TARGET_DIR/docs/prd.md" ;;
    task.md)       DEST="$TARGET_DIR/templates/task.md.tmpl" ;;
    settings.json) DEST="$TARGET_DIR/.claude/settings.json" ;;
    gitignore)     DEST="$TARGET_DIR/.gitignore" ;;
    *)             continue ;;
  esac

  mkdir -p "$(dirname "$DEST")"
  sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{PROJECT_BACKGROUND}}|$BACKGROUND|g" \
      "$TMPL" > "$DEST"
done
echo "📋 模板已复制并替换占位符"

# --- e. 复制脚本 ---
mkdir -p "$TARGET_DIR/.claude/scripts"
for SCRIPT in "$FRAMEWORK_DIR/scripts/"*; do
  BASENAME=$(basename "$SCRIPT")
  # 跳过 init-project.sh 和 .ref 文件
  case "$BASENAME" in
    init-project.sh) continue ;;
    *.ref)           continue ;;
  esac
  cp "$SCRIPT" "$TARGET_DIR/.claude/scripts/$BASENAME"
done
chmod +x "$TARGET_DIR/.claude/scripts/"*.sh 2>/dev/null || true
echo "🔧 脚本已复制到 .claude/scripts/"

# --- f. 复制 skills ---
mkdir -p "$TARGET_DIR/.claude/skills"
for SKILL_DIR in "$FRAMEWORK_DIR/skills/"*/; do
  SKILL_NAME=$(basename "$SKILL_DIR")
  # 跳过 init-project（只在框架仓库中使用）
  [ "$SKILL_NAME" = "init-project" ] && continue
  mkdir -p "$TARGET_DIR/.claude/skills/$SKILL_NAME"
  cp "$SKILL_DIR"* "$TARGET_DIR/.claude/skills/$SKILL_NAME/" 2>/dev/null || true
done
echo "🛠️ Skills 已复制到 .claude/skills/"

# --- f2. 复制 agents ---
if [ -d "$FRAMEWORK_DIR/agents" ]; then
  mkdir -p "$TARGET_DIR/.claude/agents"
  for AGENT_FILE in "$FRAMEWORK_DIR/agents/"*.md; do
    [ -f "$AGENT_FILE" ] || continue
    cp "$AGENT_FILE" "$TARGET_DIR/.claude/agents/$(basename "$AGENT_FILE")"
  done
  echo "🤖 Agents 已复制到 .claude/agents/"
fi

# --- g. settings.json 已在模板复制时创建 ---

# --- h. 创建目录结构 ---
mkdir -p "$TARGET_DIR/docs/modules"
mkdir -p "$TARGET_DIR/requirements/active"
mkdir -p "$TARGET_DIR/requirements/closed"
mkdir -p "$TARGET_DIR/prototypes"
mkdir -p "$TARGET_DIR/.runs/events"
mkdir -p "$TARGET_DIR/.worktrees"
echo "📂 目录结构已创建"

# --- i. .gitignore 已在模板复制时创建 ---

# --- j. git init ---
cd "$TARGET_DIR"
git init -b main >/dev/null 2>&1
echo "🔀 Git 仓库已初始化（main 分支）"

# --- k. 推导基础端口 ---
PROJECT_PATH=$(pwd)
BASE_PORT=$(python3 -c "
import hashlib
h = int(hashlib.md5('$PROJECT_PATH'.encode()).hexdigest(), 16)
print(3000 + (h % 7000))
" 2>/dev/null || echo "3000")
echo "$BASE_PORT" > .dev-port
echo "🔌 基础端口: $BASE_PORT"

# --- l. 初始 commit ---
git add -A
git commit -m "init: $PROJECT_NAME" >/dev/null 2>&1
echo "📝 初始 commit 完成"

echo ""
echo "═══════════════════════════════════════"
echo "✅ 项目初始化完成: $PROJECT_NAME"
echo "📁 位置: $TARGET_DIR"
echo ""
echo "下一步："
echo "  cd $TARGET_DIR"
echo "  运行 /new-req 开始第一个需求"
echo "═══════════════════════════════════════"
