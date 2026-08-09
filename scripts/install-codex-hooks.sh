#!/usr/bin/env bash
# Backward-compatible Codex-only wrapper. New callers should use
# install-project-hooks.sh to check or refresh Claude Code and Codex together.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for arg in "$@"; do
  case "$arg" in
    --host|--host=*)
      echo "❌ install-codex-hooks.sh 是 Codex-only 包装器，不接受 --host 参数。" >&2
      exit 2
      ;;
  esac
done

exec bash "$SCRIPT_DIR/install-project-hooks.sh" "$@" --host codex
