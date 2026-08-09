#!/usr/bin/env bash
# install-opencode-commands.sh — install OpenCode slash command routing files.

set -euo pipefail

SKILL_PREFIX="pmai-"
MODE=""
PROJECT_DIR=""
CHECK_MODE=0

usage() {
  cat <<'EOF'
Usage:
  bash scripts/install-opencode-commands.sh --global
  bash scripts/install-opencode-commands.sh --global --check
  bash scripts/install-opencode-commands.sh --project <repo-dir>
  bash scripts/install-opencode-commands.sh --project <repo-dir> --check

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
    --check)
      CHECK_MODE=1
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
source "$SCRIPT_DIR/_lib/skill-links.sh"
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
  local preamble_env=""

  if [ "$exposed_name" = "pmai-status" ]; then
    preamble_env="PMAI_PREAMBLE_READ_ONLY=1 "
  fi

  cat > "$dst" <<EOF
---
description: Run PMAI /${exposed_name} workflow
---

执行 PMAI /${exposed_name}。

输入：\$ARGUMENTS

必须按以下步骤执行：

1. 定位 PMAI_HOME：优先使用环境变量 \`PMAI_HOME\`；没有则使用 \`~/.pmai\`。
2. 如果当前项目根目录有 \`AGENTS.md\`，先遵守其中的 PMAI Host Mapping 和 Startup 规则。
3. 如果当前命令不是 \`/pmai-init-project\`、\`/pmai-doctor\` 或 \`/pmai-upgrade\`，先运行 \`bash -lc '${preamble_env}source "\${PMAI_HOME:-\$HOME/.pmai}/scripts/skill-preamble.sh"'\`。如果输出 \`PMAI_PROJECT_INITIALIZED: 0\`，停止当前 skill，只引导 PM 先发 \`/pmai-init-project\`。 \`/pmai-humanize\` 仅在处理粘贴文本或仓外文件、且不写 PMAI 项目产物时可继续；要读取或改写仓内文档时同样停止。
4. 完整读取 \`\$PMAI_HOME/skills/${skill_name}/SKILL.md\`。
5. 如果该 \`SKILL.md\` 引用 \`_shared/...\`、\`references/...\`、\`templates/...\` 或脚本，按文件路径继续读取必要内容。
6. 严格按 skill workflow 执行；不要只凭本 command 或记忆模拟。
7. 默认用中文和 PM 沟通。

OpenCode 不使用 Codex hooks；涉及保护时以 OpenCode permission、PMAI git hooks、build contract 和 changed-path review 为准。

如果 skill 文件不存在，先说明 PMAI 未安装或安装损坏，并建议运行 \`pmai doctor --check\`。
EOF
}

install_commands_to_dir() {
  local command_dir="$1"
  local skill_dir skill_name exposed_name count old

  mkdir -p "$command_dir" || return 1
  for old in "$command_dir"/${SKILL_PREFIX}*.md; do
    [ -e "$old" ] || [ -L "$old" ] || continue
    rm -f -- "$old" || return 1
  done

  count=0
  for skill_dir in "$PMAI_HOME"/skills/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    case "$skill_name" in
      _internal|_shared) continue ;;
    esac
    pmai_skill_is_host_exposed "$skill_name" || continue
    exposed_name=$(exposed_name_for_skill "$skill_name")
    write_opencode_command "$command_dir" "$skill_name" "$exposed_name" || return 1
    count=$((count + 1))
  done

  INSTALLED_COMMAND_COUNT="$count"
}

check_commands_in_dir() {
  local command_dir="$1"
  local rendered_dir expected actual expected_names actual_names

  rendered_dir="${TMPDIR:-/tmp}/pmai-opencode-check.$$.$RANDOM"
  while [ -e "$rendered_dir" ] || [ -L "$rendered_dir" ]; do
    rendered_dir="${TMPDIR:-/tmp}/pmai-opencode-check.$$.$RANDOM"
  done
  mkdir -m 700 "$rendered_dir" || return 2
  if ! install_commands_to_dir "$rendered_dir"; then
    rm -rf -- "$rendered_dir"
    return 2
  fi

  expected_names=$(
    for expected in "$rendered_dir"/${SKILL_PREFIX}*.md; do
      [ -e "$expected" ] || continue
      basename "$expected"
    done | sort
  )
  actual_names=$(
    for actual in "$command_dir"/${SKILL_PREFIX}*.md; do
      [ -e "$actual" ] || [ -L "$actual" ] || continue
      basename "$actual"
    done | sort
  )
  if [ "$expected_names" != "$actual_names" ]; then
    rm -rf -- "$rendered_dir"
    return 1
  fi
  for expected in "$rendered_dir"/${SKILL_PREFIX}*.md; do
    [ -e "$expected" ] || continue
    actual="$command_dir/$(basename "$expected")"
    if [ ! -f "$actual" ] || [ -L "$actual" ] || ! cmp -s "$expected" "$actual"; then
      rm -rf -- "$rendered_dir"
      return 1
    fi
  done
  rm -rf -- "$rendered_dir"
  return 0
}

check_project_opencode_json() {
  local json_path="$1/opencode.json"

  [ -f "$json_path" ] && [ ! -L "$json_path" ] || return 1
  JSON_PATH="$json_path" python3 - <<'PY'
import json
import os
import sys

try:
    with open(os.environ["JSON_PATH"], encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)
if not isinstance(data, dict):
    raise SystemExit(1)
instructions = data.get("instructions")
if isinstance(instructions, str):
    instructions = [instructions]
if not isinstance(instructions, list) or not all(
    item in instructions for item in ("AGENTS.md", "CLAUDE.md")
):
    raise SystemExit(1)
permission = data.get("permission")
if not isinstance(permission, dict) or "edit" not in permission or "bash" not in permission:
    raise SystemExit(1)
PY
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
    if [ "$CHECK_MODE" = "1" ]; then
      if check_commands_in_dir "$COMMAND_DIR"; then
        echo "OK: OpenCode commands match current PMAI render"
        exit 0
      fi
      echo "DRIFT: OpenCode commands differ from current PMAI render" >&2
      exit 1
    fi
    install_commands_to_dir "$COMMAND_DIR"
    echo "   installed $INSTALLED_COMMAND_COUNT OpenCode command entries → $COMMAND_DIR"
    ;;
  project)
    if [ "$CHECK_MODE" = "1" ]; then
      [ -d "$PROJECT_DIR" ] || {
        echo "DRIFT: OpenCode project root does not exist" >&2
        exit 1
      }
      PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd -P)"
      COMMAND_DIR="$PROJECT_DIR/.opencode/commands"
      if check_commands_in_dir "$COMMAND_DIR" \
        && check_project_opencode_json "$PROJECT_DIR"; then
        echo "OK: OpenCode project entries match current PMAI contract"
        exit 0
      fi
      echo "DRIFT: OpenCode project entries differ from current PMAI contract" >&2
      exit 1
    fi
    mkdir -p "$PROJECT_DIR"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    COMMAND_DIR="$PROJECT_DIR/.opencode/commands"
    install_commands_to_dir "$COMMAND_DIR"
    merge_project_opencode_json "$PROJECT_DIR"
    echo "   installed $INSTALLED_COMMAND_COUNT OpenCode project command entries → $COMMAND_DIR"
    echo "   merged OpenCode project config → $PROJECT_DIR/opencode.json"
    ;;
esac
