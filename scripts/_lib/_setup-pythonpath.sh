#!/usr/bin/env bash
# 必须用 `source`（不是 `bash`）调用，否则 export 不会传到 caller。
# 设计要点：BASH_SOURCE[0] 指向本脚本路径（与 cwd 无关），所以从任何 cwd source 都能正确解析。
#
# 调用方约定：
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_lib/_setup-pythonpath.sh"
#   STATUS=$(python3 -m _lib.task_parser get_status "$task_file")

# scripts/ 目录 = _lib/_setup-pythonpath.sh 的祖父目录
_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$_SCRIPTS_DIR"
