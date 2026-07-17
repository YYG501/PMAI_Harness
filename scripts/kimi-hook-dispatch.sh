#!/usr/bin/env bash
# Route Kimi Code's global hooks to the correct PMAI project hook set.
# The Kimi config is user-level, so this dispatcher must be a no-op outside a
# PMAI generator/consumer repository.

set -uo pipefail

MODE="${1:-}"
case "$MODE" in
  write|bash|prompt) ;;
  *) exit 0 ;;
esac

PMAI_HOME="${PMAI_HOME:-$HOME/.pmai}"
INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

HOOK_CWD=$(python3 - "$INPUT_FILE" <<'PY' 2>/dev/null
import json
import os
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        payload = json.load(handle)
    print(payload.get("cwd") or os.getcwd())
except Exception:
    print(os.getcwd())
PY
)

REPO_ROOT=$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || exit 0
cd "$HOOK_CWD" 2>/dev/null || exit 0

IS_GENERATOR=0
IS_CONSUMER=0
if [ -f "$REPO_ROOT/RUNTIME.md" ] && [ -f "$REPO_ROOT/skills/init-project/SKILL.md" ] && [ -f "$REPO_ROOT/CLAUDE.md" ]; then
  IS_GENERATOR=1
elif [ -f "$REPO_ROOT/AGENTS.md" ] && [ -f "$REPO_ROOT/PRODUCT-STATE.md" ] && \
  grep -q "PMAI" "$REPO_ROOT/AGENTS.md" 2>/dev/null; then
  IS_CONSUMER=1
else
  exit 0
fi

run_node_hook() {
  local script="$1"
  [ -f "$script" ] || return 0
  node "$script" < "$INPUT_FILE"
  local status=$?
  [ "$status" = "2" ] && exit 2
  return 0
}

case "$MODE" in
  write)
    [ "$IS_CONSUMER" = "1" ] || exit 0
    [ -f "$PMAI_HOME/scripts/check-branch.sh" ] || exit 0
    python3 - "$INPUT_FILE" <<'PY' | bash "$PMAI_HOME/scripts/check-branch.sh"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
tool_input = payload.get("tool_input")
if isinstance(tool_input, dict) and not tool_input.get("file_path") and tool_input.get("path"):
    tool_input["file_path"] = tool_input["path"]
json.dump(payload, sys.stdout, ensure_ascii=False)
PY
    exit ${PIPESTATUS[1]}
    ;;
  bash)
    [ "$IS_GENERATOR" = "1" ] || exit 0
    run_node_hook "$REPO_ROOT/hooks/check-doc-currency.cjs"
    run_node_hook "$REPO_ROOT/hooks/check-sync-asset-jargon.cjs"
    run_node_hook "$REPO_ROOT/hooks/check-stage-number-jargon.cjs"
    ;;
  prompt)
    if [ "$IS_GENERATOR" = "1" ]; then
      run_node_hook "$REPO_ROOT/hooks/review-skill-guard.cjs"
    else
      run_node_hook "$PMAI_HOME/hooks/review-skill-guard.cjs"
    fi
    ;;
esac

exit 0
