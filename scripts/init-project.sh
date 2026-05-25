#!/usr/bin/env bash
# init-project.sh — 创建新业务项目
# 必须从框架仓库根目录运行
# 跑 `--help` / `-h` 看完整用法 + 期望时间

set -euo pipefail

# ---------- --help / 零参数引导 ----------
_print_help() {
  cat <<HELP
用法:
  bash scripts/init-project.sh <project-name> <target-dir> <background> [<project-intent>]

参数:
  <project-name>      业务项目名（也是 git 仓的名字）
  <target-dir>        业务项目落地路径（不能已存在）
  <background>        一句话项目背景（写进生成的 CLAUDE.md）
  <project-intent>    工程结构意图（默认 unknown）：
                        prototype  Next.js 单页原型 / Demo 仓
                        system     完整业务系统（多模块、有后端契约）
                        custom     PM 自由编辑骨架
                        unknown    探测兜底档（先 init，跑通后再分类）

期望时间:
  init-project 自身 ~10 秒（拷贝 + git init + commit）。
  跑通后到落第一个 brief.md ~10-30 分钟（取决于 PM 思考速度）。
  完整 TTHW（init → 第一个 brief.md 落档）<= 30 分钟。

例子:
  bash scripts/init-project.sh \\
    ExampleConsumerApp \\
    ${CONSUMER_REPO_ROOT} \\
    "B 端 admin console 重构" \\
    prototype

说明:
  本脚本是 /init-project skill 阶段 B 的骨架构建器（agent 用 Bash 调）。
  PM 主动入口走 /init-project（一气呵成 4 阶段：参数 → 骨架 → 方向讨论 → Next Up）。
  本脚本也保留作非交互参数化 CLI（measure-tthw / smoke / 批量自动化依赖）。
HELP
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  _print_help
  exit 0
fi

if [ $# -lt 2 ]; then
  echo "❌ 缺少必填参数（至少需要 <project-name> 和 <target-dir>）" >&2
  echo "   正确形态：bash scripts/init-project.sh <项目名> <落地路径> <一句话背景> [intent]" >&2
  echo "" >&2
  _print_help >&2
  exit 2
fi

PROJECT_NAME="$1"
TARGET_DIR="$2"
BACKGROUND="${3:-}"
PROJECT_INTENT="${4:-unknown}"

case "$PROJECT_INTENT" in
  prototype|system|custom|unknown) ;;
  *)
    echo "❌ project-intent 非法: ${PROJECT_INTENT}（必须 ∈ prototype/system/custom/unknown）" >&2
    echo "   修复：参数 4 必须是 prototype / system / custom / unknown 之一；不传走默认 unknown。" >&2
    echo "        跑 'bash scripts/init-project.sh --help' 看完整说明。" >&2
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
  echo "   修复：换一个不存在的路径作 <target-dir>。init-project 不写入已存在目录，避免覆盖已有内容。" >&2
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
    PROJECT.md)             DEST="$TARGET_DIR/docs/PROJECT.md" ;;
    DESIGN.md)              DEST="$TARGET_DIR/docs/DESIGN.md" ;;
    PRODUCT-RULES.md)       DEST="$TARGET_DIR/docs/PRODUCT-RULES.md" ;;
    roadmap.md)             DEST="$TARGET_DIR/docs/roadmap.md" ;;
    modules-INDEX.md)       DEST="$TARGET_DIR/docs/modules/INDEX.md" ;;
    req-prd.md)             DEST="$TARGET_DIR/templates/req-prd.md.tmpl" ;;
    implementation-design.md) DEST="$TARGET_DIR/templates/implementation-design.md.tmpl" ;;
    codebase-audit.md)      DEST="$TARGET_DIR/templates/codebase-audit.md.tmpl" ;;
    task.md)                DEST="$TARGET_DIR/templates/task.md.tmpl" ;;
    task-plan.md)           DEST="$TARGET_DIR/templates/task-plan.md.tmpl" ;;
    module.md)              DEST="$TARGET_DIR/templates/module.md.tmpl" ;;
    settings.json)          DEST="$TARGET_DIR/.claude/settings.json" ;;
    lark-publish.json)      DEST="$TARGET_DIR/templates/lark-publish.json.tmpl" ;;
    gitignore)              DEST="$TARGET_DIR/.gitignore" ;;
    pm-workflow.config.yml) DEST="$TARGET_DIR/.pm-workflow/config.yml" ;;
    *)             continue ;;
  esac

  mkdir -p "$(dirname "$DEST")"
  # 占位符替换用 Python .replace()，不解释 replacement 元字符 —— sed 会把
  # background 里的 | 当分隔符报错、& 当「整段匹配」展开，静默污染生成文件。
  TMPL="$TMPL" DEST="$DEST" PN="$PROJECT_NAME" BG="$BACKGROUND" python3 - <<'PY'
import os
text = open(os.environ["TMPL"], encoding="utf-8").read()
text = text.replace("{{PROJECT_NAME}}", os.environ["PN"])
text = text.replace("{{PROJECT_BACKGROUND}}", os.environ["BG"])
open(os.environ["DEST"], "w", encoding="utf-8").write(text)
PY
done
echo "📋 模板已复制并替换占位符"

# --- d1.5. 复制工程结构约束源文件（非 .tmpl 后缀，runtime 被 stage 3 工程合同链路引用） ---
# 工程结构约束-{档位}.md 由 stage 3 工程合同链路引用
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
  # 跳过框架自用脚本（不该分发到消费仓）和 .ref 文件
  case "$BASENAME" in
    init-project.sh) continue ;;   # 只在框架仓运行
    measure-tthw.sh) continue ;;   # 框架自用 TTHW 测量工具，假定框架仓根 + 调 init-project.sh，进消费仓必失效
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
  # 递归复制：skill 目录可能含 references/ 等子目录（prd-writing / task-execute）
  # 不吞错误——skill 复制是关键步骤，失败应由 set -e 停下，而非静默漏拷
  cp -R "$SKILL_DIR". "$TARGET_DIR/.claude/skills/$SKILL_NAME/"
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
mkdir -p "$TARGET_DIR/.pm-workflow/tasks"   # task-verify 报告 / artifact 根目录
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

# --- k1. 复制 Claude Code hooks（项目根 hooks/，跟 .claude/settings.json 注册联动）---
if [ -d "$FRAMEWORK_DIR/hooks" ]; then
  mkdir -p "$TARGET_DIR/hooks"
  for HOOK_FILE in "$FRAMEWORK_DIR/hooks/"*.cjs "$FRAMEWORK_DIR/hooks/"*.js "$FRAMEWORK_DIR/hooks/"*.sh; do
    [ -f "$HOOK_FILE" ] || continue
    cp "$HOOK_FILE" "$TARGET_DIR/hooks/$(basename "$HOOK_FILE")"
    chmod +x "$TARGET_DIR/hooks/$(basename "$HOOK_FILE")" 2>/dev/null || true
  done
  echo "🪝 Claude Code hooks 已复制到 hooks/"
fi

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
echo "═══════════════════════════════════════"
# 注：本脚本作为 /init-project skill 阶段 B 调用时，下一步由 skill 阶段 C/D 接管；
# 非交互直接调用时（measure-tthw / smoke），下一步由调用方编排。
# 不在脚本里 echo 具体的下一步命令 —— 入口语义已迁移到 /init-project skill。
