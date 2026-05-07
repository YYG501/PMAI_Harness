#!/usr/bin/env bash
# init-project.sh — 创建新业务项目
# 用法: bash scripts/init-project.sh <project-name> <target-dir> <background> [<project-intent>]
#   project-intent: prototype | system | custom | unknown（默认 unknown）
# 必须从框架仓库根目录运行

set -euo pipefail

PROJECT_NAME="${1:?用法: init-project.sh <project-name> <target-dir> <background> [<project-intent>]}"
TARGET_DIR="${2:?用法: init-project.sh <project-name> <target-dir> <background> [<project-intent>]}"
BACKGROUND="${3:-}"
PROJECT_INTENT="${4:-unknown}"

case "$PROJECT_INTENT" in
  prototype|system|custom|unknown) ;;
  *)
    echo "❌ project-intent 非法: $PROJECT_INTENT（必须 ∈ prototype/system/custom/unknown）" >&2
    exit 2
    ;;
esac

FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# --- 0. 位置 sanity check（DX I2）---
# 该脚本只能在框架仓内运行；在业务仓里跑会拷错路径
# 判定：FRAMEWORK_DIR 必须含 templates/CLAUDE.md.tmpl + skills/init-project + scripts/inject-structure-segment.py
MISSING=""
[ -f "$FRAMEWORK_DIR/templates/CLAUDE.md.tmpl" ] || MISSING="$MISSING templates/CLAUDE.md.tmpl"
[ -d "$FRAMEWORK_DIR/skills/init-project" ] || MISSING="$MISSING skills/init-project/"
[ -f "$FRAMEWORK_DIR/scripts/inject-structure-segment.py" ] || MISSING="$MISSING scripts/inject-structure-segment.py"
if [ -n "$MISSING" ]; then
  echo "❌ 该脚本必须在框架仓（PM-AI-Workflow）根目录运行。" >&2
  echo "   检测到缺失的标志文件：$MISSING" >&2
  echo "   推断当前 FRAMEWORK_DIR=$FRAMEWORK_DIR 不是框架仓。" >&2
  echo "" >&2
  echo "   解决方法：" >&2
  echo "     cd /path/to/PM-AI-Workflow" >&2
  echo "     bash scripts/init-project.sh <project-name> <target-dir> <background> [<intent>]" >&2
  exit 2
fi

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
    CLAUDE.md)              DEST="$TARGET_DIR/CLAUDE.md" ;;
    CONTEXT.md)             DEST="$TARGET_DIR/docs/CONTEXT.md" ;;
    DESIGN.md)              DEST="$TARGET_DIR/docs/DESIGN.md" ;;
    project-prd.md)         DEST="$TARGET_DIR/docs/prd.md" ;;
    req-prd.md)             DEST="$TARGET_DIR/templates/req-prd.md.tmpl" ;;
    task.md)                DEST="$TARGET_DIR/templates/task.md.tmpl" ;;
    task.engineering.md)    DEST="$TARGET_DIR/templates/task.engineering.md.tmpl" ;;
    task-plan.md)           DEST="$TARGET_DIR/templates/task-plan.md.tmpl" ;;
    solution.md)            DEST="$TARGET_DIR/templates/solution.md.tmpl" ;;
    solution.engineering.md) DEST="$TARGET_DIR/templates/solution.engineering.md.tmpl" ;;
    module.md)              DEST="$TARGET_DIR/templates/module.md.tmpl" ;;
    settings.json)          DEST="$TARGET_DIR/.claude/settings.json" ;;
    lark-publish.json)      DEST="$TARGET_DIR/templates/lark-publish.json.tmpl" ;;
    gitignore)              DEST="$TARGET_DIR/.gitignore" ;;
    *)             continue ;;
  esac

  mkdir -p "$(dirname "$DEST")"
  sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{PROJECT_BACKGROUND}}|$BACKGROUND|g" \
      "$TMPL" > "$DEST"
done
echo "📋 模板已复制并替换占位符"

# --- d1.5. 复制工程结构约束源文件（非 .tmpl 后缀，runtime 被 req-solution 引用） ---
# req-solution/SKILL.md 步骤 9 引用 $REPO_ROOT/templates/工程结构约束-{档位}.md
# detect-project-structure.py 引用 templates/工程结构约束.schema.json
for STRUCT_FILE in "$FRAMEWORK_DIR/templates/"工程结构约束-*.md "$FRAMEWORK_DIR/templates/"工程结构约束.schema.json; do
  [ -f "$STRUCT_FILE" ] || continue
  cp "$STRUCT_FILE" "$TARGET_DIR/templates/$(basename "$STRUCT_FILE")"
done

# --- d2. 注入工程结构约束段（4.5c）---
python3 "$FRAMEWORK_DIR/scripts/inject-structure-segment.py" \
  "$TARGET_DIR/CLAUDE.md" "$PROJECT_INTENT" \
  --framework-root "$FRAMEWORK_DIR" \
  || {
    echo "⚠️  工程结构约束注入失败（项目仍可用，PM 后续可手动跑 detect-project-structure.py）" >&2
  }

# --- e. 复制脚本 ---
mkdir -p "$TARGET_DIR/.claude/scripts"
for SCRIPT in "$FRAMEWORK_DIR/scripts/"*; do
  BASENAME=$(basename "$SCRIPT")
  # 跳过 init-project.sh 和 .ref 文件
  case "$BASENAME" in
    init-project.sh) continue ;;
    *.ref)           continue ;;
  esac
  cp -Rp "$SCRIPT" "$TARGET_DIR/.claude/scripts/$BASENAME"
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

# --- k2. 复制 git-hooks 模板 ---
mkdir -p "$TARGET_DIR/templates/git-hooks"
for HOOK_TMPL in "$FRAMEWORK_DIR/templates/git-hooks/"*.tmpl; do
  [ -f "$HOOK_TMPL" ] || continue
  cp "$HOOK_TMPL" "$TARGET_DIR/templates/git-hooks/$(basename "$HOOK_TMPL")"
done

# --- k3. 安装 pre-commit hook（拦截非法 task 状态字段直改）---
if bash "$FRAMEWORK_DIR/scripts/install-hooks.sh" 2>&1 | sed 's/^/   /'; then
  echo "🪝 git hooks 已安装"
else
  echo "⚠️  git hooks 安装失败（项目仍可用，PM 后续可手动跑 .claude/scripts/install-hooks.sh）" >&2
fi

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
