#!/usr/bin/env bash
# install-codex-hooks.sh — install / refresh project-level Codex hooks.
#
# Run from a consumer repo root:
#   bash $HOME/.pmai/scripts/install-codex-hooks.sh
#
# I-mini rule: the consumer stores only .codex/hooks.json host config; hook
# commands keep executing from ~/.pmai so framework code is not vendored.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "❌ 当前目录不在 git 仓内。请在项目根目录运行。" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PMAI_HOME="${PMAI_HOME:-}"
if [ -z "$PMAI_HOME" ]; then
  if [ -f "$SCRIPT_DIR/../templates/codex-hooks.json.tmpl" ]; then
    PMAI_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
  else
    PMAI_HOME="$HOME/.pmai"
  fi
fi

TMPL="$PMAI_HOME/templates/codex-hooks.json.tmpl"
if [ ! -f "$TMPL" ]; then
  echo "❌ 找不到 Codex hook 模板：$TMPL" >&2
  echo "   修复：先 pmai install / pmai upgrade，或设置 PMAI_HOME=/path/to/framework" >&2
  exit 1
fi

DEST_DIR="$REPO_ROOT/.codex"
DEST="$DEST_DIR/hooks.json"
mkdir -p "$DEST_DIR"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

PMAI_CODEX_HOOK_TEMPLATE="$TMPL" PMAI_CODEX_HOOK_DEST="$DEST" python3 - <<'PY' > "$TMP"
import json
import os
import sys
from pathlib import Path

template_path = Path(os.environ["PMAI_CODEX_HOOK_TEMPLATE"])
dest_path = Path(os.environ["PMAI_CODEX_HOOK_DEST"])

try:
    template = json.loads(template_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"invalid template {template_path}: {exc}", file=sys.stderr)
    sys.exit(1)

if dest_path.exists():
    try:
        current = json.loads(dest_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"invalid existing {dest_path}: {exc}", file=sys.stderr)
        sys.exit(1)
else:
    current = {}

if not isinstance(current, dict):
    current = {}
if not isinstance(current.get("hooks"), dict):
    current["hooks"] = {}

managed_tokens = (
    "check-branch.sh",
    "review-skill-guard.cjs",
    "active-build-guard.cjs",
)

def hook_commands(group):
    if not isinstance(group, dict):
        return []
    hooks = group.get("hooks")
    if not isinstance(hooks, list):
        return []
    commands = []
    for hook in hooks:
        if isinstance(hook, dict) and isinstance(hook.get("command"), str):
            commands.append(hook["command"])
    return commands

def is_pmai_managed(group):
    return any(
        token in command
        for command in hook_commands(group)
        for token in managed_tokens
    )

template_hooks = template.get("hooks")
if not isinstance(template_hooks, dict):
    print("template missing hooks object", file=sys.stderr)
    sys.exit(1)

current_hooks = current["hooks"]
for event_name, template_groups in template_hooks.items():
    if not isinstance(template_groups, list):
        continue
    existing_groups = current_hooks.get(event_name, [])
    if not isinstance(existing_groups, list):
        existing_groups = []
    existing_groups = [group for group in existing_groups if not is_pmai_managed(group)]
    current_hooks[event_name] = existing_groups + template_groups

json.dump(current, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY

if [ -f "$DEST" ] && cmp -s "$TMP" "$DEST"; then
  echo "✅ Codex hooks 已是最新版：$DEST"
  exit 0
fi

if [ -f "$DEST" ]; then
  BAK="$DEST.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$DEST" "$BAK"
  echo "📦 已备份原 Codex hooks 到：$BAK"
fi

mv "$TMP" "$DEST"
trap - EXIT
chmod 0644 "$DEST"
echo "✅ Codex hooks 已安装：$DEST"
echo "   职责：PreToolUse(Edit|Write) 分支护栏 + UserPromptSubmit review/audit 与 active build 续接上下文。"
echo "   Codex 首次看到新增 hook 时可能要求信任确认。"
