#!/usr/bin/env bash
# init-project.sh — 创建新业务项目
# 必须从框架仓库根目录运行
# 跑 `--help` / `-h` 看完整用法 + 期望时间

set -euo pipefail

# ---------- --help / 零参数引导 ----------
_print_help() {
  cat <<HELP
用法:
  bash scripts/init-project.sh <project-name> <target-dir> <background> [<project-intent>] [--allow-existing]

参数:
  <project-name>      业务项目名（也是 git 仓的名字）
  <target-dir>        业务项目落地路径（默认不能已存在；加 --allow-existing 可复用已有目录）
  <background>        一句话项目背景（写进生成的 CLAUDE.md）
  <project-intent>    工程结构意图（默认 unknown）：
                        prototype  Next.js 单页原型 / Demo 仓
                        system     完整业务系统（多模块、有后端契约）
                        custom     PM 自由编辑骨架
                        unknown    探测兜底档（先 init，跑通后再分类）

可选 flag:
  --allow-existing    放过"目标目录已存在"检查。仅当 PM 在 /pmai-init-project skill 阶段 A
                      step 3b 明确选了「资料档接住」分流时由 skill 加入；脚本本身不判断目录
                      内容是否真是非 codebase（那是 skill 层的 step 3a 代码标志扫描的责任）。
                      命中后：mkdir 改 noop（用现有目录），git init 后 git add -A 会把现有文件
                      一起 add 进首 commit。

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
  本脚本是 /pmai-init-project skill 阶段 B 的骨架构建器（agent 用 Bash 调）。
  PM 主动入口走 /pmai-init-project（一气呵成 4 阶段：参数 → 骨架 → 方向讨论 → Next Up）。
  本脚本也保留作非交互参数化 CLI（measure-tthw / smoke / 批量自动化依赖）。
HELP
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  _print_help
  exit 0
fi

# 解析 --allow-existing flag（位置无关）：扫所有参数挑出 flag，剩下的当位置参数
ALLOW_EXISTING=0
declare -a _POSITIONAL=()
for _arg in "$@"; do
  if [ "$_arg" = "--allow-existing" ]; then
    ALLOW_EXISTING=1
  else
    _POSITIONAL+=("$_arg")
  fi
done
# set -- 重置位置参数；空数组 fallback 防 set -u
set -- "${_POSITIONAL[@]+"${_POSITIONAL[@]}"}"

if [ $# -lt 2 ]; then
  echo "❌ 缺少必填参数（至少需要 <project-name> 和 <target-dir>）" >&2
  echo "   正确形态：bash scripts/init-project.sh <项目名> <落地路径> <一句话背景> [intent] [--allow-existing]" >&2
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

# 框架源路径解析顺序：
#   1. PMAI_HOME 环境变量（pmai install 后用，或 /pmai-init-project skill 显式传）
#   2. ~/.pmai/（pmai install 默认位置）
#   3. cd "$(dirname "$0")/.."（fallback：本仓内直接 bash scripts/init-project.sh 时）
if [ -n "${PMAI_HOME:-}" ] && [ -f "$PMAI_HOME/templates/CLAUDE.md.tmpl" ]; then
  FRAMEWORK_DIR="$PMAI_HOME"
elif [ -f "$HOME/.pmai/templates/CLAUDE.md.tmpl" ]; then
  FRAMEWORK_DIR="$HOME/.pmai"
else
  FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fi

# --- 0. 位置 sanity check（DX I2）---
# FRAMEWORK_DIR 必须含 templates/CLAUDE.md.tmpl + skills/init-project + scripts/inject-structure-segment.py
MISSING=""
[ -f "$FRAMEWORK_DIR/templates/CLAUDE.md.tmpl" ] || MISSING="$MISSING templates/CLAUDE.md.tmpl"
[ -d "$FRAMEWORK_DIR/skills/init-project" ] || MISSING="$MISSING skills/init-project/"
[ -f "$FRAMEWORK_DIR/scripts/inject-structure-segment.py" ] || MISSING="$MISSING scripts/inject-structure-segment.py"
if [ -n "$MISSING" ]; then
  echo "❌ 框架源缺标志文件：$MISSING" >&2
  echo "   FRAMEWORK_DIR=$FRAMEWORK_DIR" >&2
  echo "" >&2
  echo "   修复方法（任一）：" >&2
  echo "     1. pmai install                       # 全局装框架到 ~/.pmai/" >&2
  echo "     2. PMAI_HOME=/path/to/framework bash scripts/init-project.sh ..." >&2
  echo "     3. cd /path/to/PM-AI-Workflow && bash scripts/init-project.sh ..." >&2
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
  if [ "$ALLOW_EXISTING" = "1" ]; then
    echo "📁 复用已存在目录: ${TARGET_DIR}（--allow-existing：资料档接住模式）"
  else
    echo "❌ 目标目录已存在: $TARGET_DIR" >&2
    echo "   修复：换一个不存在的路径，或加 --allow-existing 接住非 codebase 资料（由 /pmai-init-project skill 阶段 A step 3b 经 PM 拍板后调用）。" >&2
    exit 1
  fi
else
  mkdir -p "$TARGET_DIR"
  echo "📁 创建项目目录: $TARGET_DIR"
fi

# --- d. 复制模板 + 替换占位符 ---
for TMPL in "$FRAMEWORK_DIR/templates/"*.tmpl; do
  BASENAME=$(basename "$TMPL" .tmpl)
  # 确定目标位置
  case "$BASENAME" in
    CLAUDE.md)              DEST="$TARGET_DIR/CLAUDE.md" ;;
    PROJECT.md)             DEST="$TARGET_DIR/docs/PROJECT.md" ;;
    PRODUCT-STATE.md)       DEST="$TARGET_DIR/docs/PRODUCT-STATE.md" ;;   # 六步上下文脊柱：现状层 hub（下游 FORCE READ docs/PRODUCT-STATE.md）
    DESIGN.md)              DEST="$TARGET_DIR/docs/DESIGN.md" ;;          # 六步上下文脊柱：正向视觉约束（build 前 AI 必读 docs/DESIGN.md）
    PRODUCT-RULES.md)       DEST="$TARGET_DIR/docs/PRODUCT-RULES.md" ;;
    ROADMAP.md)             DEST="$TARGET_DIR/docs/ROADMAP.md" ;;
    modules-INDEX.md)       DEST="$TARGET_DIR/docs/modules/INDEX.md" ;;
    task.md|lark-publish.json)
      # task.md: runtime framework .tmpl，skill 内部按 $PMAI_HOME/templates/ 直接调用（task-spec / task-confirm 多 skill 共用）
      # lark-publish.json: 业务实例配置，下方 f3 段独立 cp（不走主 loop 占位符替换）
      # 注：req-prd / implementation-design / codebase-audit / task-plan / module 已迁
      #     skills/<skill>/templates/（req/task 周期产物 skill 自包含），不在本 loop。
      continue ;;
    settings.json)          DEST="$TARGET_DIR/.claude/settings.json" ;;
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

# --- d1.5. 工程结构约束源文件（symlink 模式：通过 templates/ symlink 跟随）---
# 旧版 cp 工程结构约束-*.md / schema.json 到 consumer/templates/。
# 方案 A symlink 模式后，consumer/templates/ 整体 symlink → $FRAMEWORK_DIR/templates/，
# 这些文件随 framework 升级自动跟，不再单独拷。
# 注：工程结构约束.schema.json 由 detect-project-structure.py 读，路径同样走 templates/ symlink。

# --- d2. 注入工程结构约束段（4.5c）---
python3 "$FRAMEWORK_DIR/scripts/inject-structure-segment.py" \
  "$TARGET_DIR/CLAUDE.md" "$PROJECT_INTENT" \
  --framework-root "$FRAMEWORK_DIR" \
  || {
    echo "⚠️  工程结构约束注入失败（项目仍可用，PM 后续可手动跑 detect-project-structure.py）" >&2
  }

# --- e/f/f2/templates/hooks. I-mini 模式：消费仓 0 framework 资产 ---
# 旧版方案 A symlink 5 块到 framework（绝对路径硬编码，跨机器 dangling）。
# I-mini：消费仓内**不放任何** framework 资产（scripts/skills/agents/templates/hooks）。
# skill 内部所有调用走 $PMAI_HOME/scripts/... 全局绝对路径（skill-preamble.sh 解析 PMAI_HOME）。
# pre-commit hook 内部自己 fallback PMAI_HOME=$HOME/.pmai。
# 跨机器 clone 消费仓后只需在新机器跑 pmai install → 立即可用，0 setup。
mkdir -p "$TARGET_DIR/.claude"
# 注：.claude/settings.json 已在 d 段写入（占位符替换实体），hook 路径用 $HOME/.pmai/...

# --- f3. 业务实例配置模板（I-mini 例外）：lark-publish.json.tmpl 拷进消费仓 ---
# PM 后续要 cp templates/lark-publish.json.tmpl → .claude/lark-publish.json 并填
# 真 token —— 必须留实体在消费仓（每个项目 token 不同，~/.pmai/ 全局副本装不下
# per-project token）。
mkdir -p "$TARGET_DIR/templates"
if [ -f "$FRAMEWORK_DIR/templates/lark-publish.json.tmpl" ]; then
  cp "$FRAMEWORK_DIR/templates/lark-publish.json.tmpl" \
     "$TARGET_DIR/templates/lark-publish.json.tmpl"
fi

echo "📦 I-mini 模式：消费仓 0 framework；skill / scripts / hooks 全走 \$PMAI_HOME，templates/ 只含业务实例配置"

# --- g. settings.json 已在模板复制时创建 ---

# --- h. 创建目录结构 ---
mkdir -p "$TARGET_DIR/docs/modules"
mkdir -p "$TARGET_DIR/docs/归档"   # 扁平：过程档案 / 一次性 review / 被取代旧文件全装这里，文件名说明为啥归档
touch "$TARGET_DIR/docs/归档/.gitkeep"
mkdir -p "$TARGET_DIR/requirements/active"
mkdir -p "$TARGET_DIR/requirements/closed"
mkdir -p "$TARGET_DIR/prototype"   # 单一主原型（单数）；SKILL C.5 用 create-next-app 在此起栈
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
import hashlib, sys
h = int(hashlib.md5(sys.argv[1].encode()).hexdigest(), 16)
print(3000 + (h % 7000))
" "$PROJECT_PATH" 2>/dev/null || echo "3000")
echo "$BASE_PORT" > .dev-port
echo "🔌 基础端口: $BASE_PORT"

# --- k1. Claude Code hooks（I-mini：消费仓不放，settings.json 用 $HOME/.pmai/hooks/...）---
# 旧版方案 A 把 hooks/ symlink 到 framework，settings.json 用 $CLAUDE_PROJECT_DIR/hooks/...
# I-mini：消费仓 0 hook 目录；settings.json 已改用 $HOME/.pmai/hooks/review-skill-guard.cjs

# --- k2. git-hooks 模板：消费仓不放，install-hooks.sh 直接从 framework 读 ---

# --- k3. 安装 pre-commit hook（拦截非法 task 状态字段直改）---
if bash "$FRAMEWORK_DIR/scripts/install-hooks.sh" 2>&1 | sed 's/^/   /'; then
  echo "🪝 git hooks 已安装"
else
  echo "⚠️  git hooks 安装失败（项目仍可用，PM 后续可手动跑 $HOME/.pmai/scripts/install-hooks.sh）" >&2
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
# 注：本脚本作为 /pmai-init-project skill 阶段 B 调用时，下一步由 skill 阶段 C/D 接管；
# 非交互直接调用时（measure-tthw / smoke），下一步由调用方编排。
# 不在脚本里 echo 具体的下一步命令 —— 入口语义已迁移到 /pmai-init-project skill。
