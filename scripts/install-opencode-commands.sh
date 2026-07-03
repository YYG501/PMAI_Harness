#!/usr/bin/env bash
# install-opencode-commands.sh — install OpenCode slash command routing files.

set -euo pipefail

SKILL_PREFIX="pmai-"
MODE=""
PROJECT_DIR=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/install-opencode-commands.sh --global
  bash scripts/install-opencode-commands.sh --project <repo-dir>

Env override:
  PMAI_HOME=<path>              # Override default ~/.pmai/
  OPENCODE_CONFIG_DIR=<path>    # Override default ~/.config/opencode

Notes:
  - Command files are thin routing files. They point OpenCode to PMAI_HOME skills.
  - Project mode writes .opencode/commands/pmai-*.md and merges opencode.json.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --global)
      MODE="global"
      shift
      ;;
    --project)
      shift
      PROJECT_DIR="${1:-}"
      [ -z "$PROJECT_DIR" ] && { echo "❌ --project needs <repo-dir>" >&2; exit 2; }
      MODE="project"
      shift
      ;;
    *)
      echo "❌ unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$MODE" ]; then
  echo "❌ missing mode: --global or --project <repo-dir>" >&2
  usage >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF_FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -n "${PMAI_HOME:-}" ] && [ -d "$PMAI_HOME/skills" ]; then
  FRAMEWORK_DIR="$PMAI_HOME"
elif [ -d "$SELF_FRAMEWORK_DIR/skills" ]; then
  FRAMEWORK_DIR="$SELF_FRAMEWORK_DIR"
elif [ -d "$HOME/.pmai/skills" ]; then
  FRAMEWORK_DIR="$HOME/.pmai"
else
  echo "❌ 找不到 PMAI skills。请先运行 pmai install，或设置 PMAI_HOME。" >&2
  exit 1
fi
export PMAI_HOME="$FRAMEWORK_DIR"

exposed_name_for_skill() {
  case "$1" in
    pmai-*) echo "$1" ;;
    *) echo "${SKILL_PREFIX}$1" ;;
  esac
}

write_opencode_command() {
  local command_dir="$1"
  local skill_name="$2"
  local exposed_name="$3"
  local dst="$command_dir/${exposed_name}.md"

  cat > "$dst" <<EOF
---
description: Run PMAI /${exposed_name} workflow
---

执行 PMAI /${exposed_name}。

输入：\$ARGUMENTS

必须按以下步骤执行：

1. 定位 PMAI_HOME：优先使用环境变量 \`PMAI_HOME\`；没有则使用 \`~/.pmai\`。
2. 如果当前项目根目录有 \`AGENTS.md\`，先遵守其中的 PMAI Host Mapping 和 Startup 规则。
3. 完整读取 \`\$PMAI_HOME/skills/${skill_name}/SKILL.md\`。
4. 如果该 \`SKILL.md\` 引用 \`_shared/...\`、\`references/...\`、\`templates/...\` 或脚本，按文件路径继续读取必要内容。
5. 严格按 skill workflow 执行；不要只凭本 command 或记忆模拟。
6. 默认用中文和 PM 沟通。

OpenCode 不使用 Codex hooks；涉及保护时以 OpenCode permission、PMAI git hooks、build contract 和 changed-path review 为准。

如果 skill 文件不存在，先说明 PMAI 未安装或安装损坏，并建议运行 \`pmai doctor\`。
EOF
}

install_commands_to_dir() {
  local command_dir="$1"
  local skill_dir skill_name exposed_name count old

  mkdir -p "$command_dir"
  for old in "$command_dir"/${SKILL_PREFIX}*.md; do
    [ -e "$old" ] && rm -f "$old" || true
  done

  count=0
  for skill_dir in "$PMAI_HOME"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    case "$skill_name" in
      _internal|_shared) continue ;;
    esac
    exposed_name=$(exposed_name_for_skill "$skill_name")
    write_opencode_command "$command_dir" "$skill_name" "$exposed_name"
    count=$((count + 1))
  done

  echo "$count"
}

merge_project_opencode_json() {
  local project_dir="$1"
  local json_path="$project_dir/opencode.json"

  JSON_PATH="$json_path" python3 - <<'PY'
import json
import os
import sys

path = os.environ["JSON_PATH"]
data = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        print(f"invalid opencode.json: {exc}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(data, dict):
        print("invalid opencode.json: root must be an object", file=sys.stderr)
        sys.exit(1)

data.setdefault("$schema", "https://opencode.ai/config.json")

instructions = data.get("instructions", [])
if isinstance(instructions, str):
    instructions = [instructions]
elif not isinstance(instructions, list):
    instructions = []
for item in ("AGENTS.md", "CLAUDE.md"):
    if item not in instructions:
        instructions.append(item)
data["instructions"] = instructions

permission = data.get("permission", {})
if not isinstance(permission, dict):
    permission = {}
permission.setdefault("edit", "ask")
permission.setdefault("bash", "ask")
data["permission"] = permission

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

case "$MODE" in
  global)
    OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
    COMMAND_DIR="$OPENCODE_CONFIG_DIR/commands"
    count=$(install_commands_to_dir "$COMMAND_DIR")
    echo "   installed $count OpenCode command entries → $COMMAND_DIR"
    ;;
  project)
    mkdir -p "$PROJECT_DIR"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    COMMAND_DIR="$PROJECT_DIR/.opencode/commands"
    count=$(install_commands_to_dir "$COMMAND_DIR")
    merge_project_opencode_json "$PROJECT_DIR"
    echo "   installed $count OpenCode project command entries → $COMMAND_DIR"
    echo "   merged OpenCode project config → $PROJECT_DIR/opencode.json"
    ;;
esac
