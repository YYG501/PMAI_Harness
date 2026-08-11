#!/usr/bin/env bash
# Route Kimi Code's global hooks to the correct PMAI project hook set.
# The Kimi config is user-level, so this dispatcher must be a no-op outside a
# PMAI generator/consumer repository. Hook code is always loaded from the
# framework checkout that owns this dispatcher; repository markers never grant
# permission to execute repository-local JavaScript.

set -uo pipefail

MODE="${1:-}"
case "$MODE" in
  write|bash|prompt-review|prompt-build) ;;
  *) exit 0 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TRUSTED_PMAI_HOME="$(cd "$SCRIPT_DIR/.." && pwd -P)"

block_for_hook_failure() {
  echo "❌ Kimi PMAI hook 阻断：$1" >&2
  exit 2
}

canonical_git_root() {
  local candidate="${1:-}"
  local root
  [ -n "$candidate" ] || return 0
  root=$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null || true)
  [ -n "$root" ] || return 0
  (cd "$root" 2>/dev/null && pwd -P) || true
}

repo_kind() {
  local root="${1:-}"
  [ -n "$root" ] || { echo "uninitialized"; return 0; }
  python3 "$TRUSTED_PMAI_HOME/scripts/repo-kind.py" --repo-root "$root" 2>/dev/null
}

# Identity classification remains centralized in repo-kind.py. This fallback
# only decides whether resolver failure is safe to ignore: a repository with a
# strong PMAI marker must fail closed when Python or the resolver is unavailable.
has_possible_pmai_marker() {
  local root="${1:-}"
  local marker legacy_count=0
  [ -n "$root" ] && [ -d "$root" ] || return 1

  for marker in \
    .pm-workflow/config.yml .opencode/commands/pmai-build.md docs/CONTEXT.md; do
    [ -f "$root/$marker" ] && return 0
  done
  if [ -f "$root/RUNTIME.md" ] \
    && [ -f "$root/CLAUDE.md" ] \
    && [ -f "$root/skills/init-project/SKILL.md" ]; then
    return 0
  fi
  for marker in AGENTS.md CLAUDE.md .codex/hooks.json opencode.json; do
    if [ -f "$root/$marker" ] \
      && grep -Eq 'PMAI|/pmai-|\$pmai-|/skill:pmai-' "$root/$marker" 2>/dev/null; then
      return 0
    fi
  done
  for marker in \
    PRODUCT.md PRODUCT-STATE.md docs/PRODUCT.md docs/PRODUCT-STATE.md; do
    [ -f "$root/$marker" ] && legacy_count=$((legacy_count + 1))
  done
  [ "$legacy_count" -ge 2 ]
}

node_payload_cwd() {
  local input_file="$1"
  local fallback_cwd="$2"
  "$NODE_BIN" -e '
const fs = require("fs");
const [inputFile, fallbackCwd] = process.argv.slice(1);
let payload;
try {
  payload = JSON.parse(fs.readFileSync(inputFile, "utf8"));
} catch {
  process.stdout.write(fallbackCwd);
  process.exit(20);
}
if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
  process.stdout.write(fallbackCwd);
  process.exit(21);
}
const cwd = payload.cwd;
if (cwd === undefined || cwd === null || cwd === "") {
  process.stdout.write(fallbackCwd);
} else if (typeof cwd !== "string" || !cwd.trim()) {
  process.stdout.write(fallbackCwd);
  process.exit(22);
} else {
  process.stdout.write(cwd);
}
' "$input_file" "$fallback_cwd"
}

read_input_with_node() {
  local input_file="$1"
  local timeout_ms="$2"
  local clock_file="$3"
  local total_budget_ms="$4"
  "$NODE_BIN" -e '
const fs = require("fs");
const [outputPath, timeoutText, clockPath, budgetText] = process.argv.slice(1);
const parsedBudget = Number.parseInt(budgetText, 10);
const totalBudgetMs = Math.min(Number.isFinite(parsedBudget) ? Math.max(parsedBudget, 1) : 7000, 7000);
const parsedTimeout = Number.parseInt(timeoutText, 10);
const timeoutMs = Math.min(
  Number.isFinite(parsedTimeout) ? Math.max(parsedTimeout, 1) : 1500,
  2000,
  Math.max(totalBudgetMs - 100, 1),
);
if (!fs.existsSync(clockPath) || fs.statSync(clockPath).size === 0) {
  fs.writeFileSync(clockPath, `node-monotonic:${process.hrtime.bigint()}`, "ascii");
}
let total = fs.existsSync(outputPath) ? fs.statSync(outputPath).size : 0;
const output = fs.openSync(outputPath, "a");
let settled = false;
const finish = code => {
  if (settled) return;
  settled = true;
  clearTimeout(timer);
  process.stdin.removeAllListeners();
  process.stdin.pause();
  fs.closeSync(output);
  process.exit(code);
};
const timer = setTimeout(() => finish(124), timeoutMs);
if (total > 4 * 1024 * 1024) finish(125);
process.stdin.on("data", chunk => {
  if (settled) return;
  total += chunk.length;
  if (total > 4 * 1024 * 1024) {
    finish(125);
    return;
  }
  fs.writeSync(output, chunk);
});
process.stdin.on("error", () => finish(126));
process.stdin.on("end", () => finish(0));
process.stdin.resume();
' "$input_file" "$timeout_ms" "$clock_file" "$total_budget_ms"
}

nearest_pmai_marker_root() {
  local candidate="${1:-}"
  local current parent kind
  [ -n "$candidate" ] || return 0
  current=$(cd "$candidate" 2>/dev/null && pwd -P) || return 0
  while :; do
    kind=$(repo_kind "$current")
    case "$kind" in
      generator|consumer)
        printf '%s\n' "$current"
        return 0
        ;;
    esac
    # Bash may preserve an exactly double-slash root. Stop both root spellings
    # before appending /.., otherwise / and // can alternate forever.
    case "$current" in
      /|//) return 0 ;;
    esac
    parent=$(cd "$current/.." 2>/dev/null && pwd -P) || return 0
    [ "$parent" != "$current" ] || return 0
    current="$parent"
  done
}

emit_prompt_build_unavailable() {
  python3 - "$1" <<'PY'
import json
import sys

reason = sys.argv[1]
context = (
    "ACTIVE BUILD 续接护栏不可用（active-build-guard hook 注入）\n\n"
    "当前项目的只读 build 上下文无法安全取得，不能把异常当成“没有 active build”。"
    "先运行 /pmai-status 检查当前工作；在上下文恢复前，禁止继续无范围约束的通用 QA 或修改。\n\n"
    f"原因：{reason}"
)
json.dump(
    {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": context,
        }
    },
    sys.stdout,
    ensure_ascii=False,
)
PY
}

PROCESS_CWD=$(pwd -P 2>/dev/null || true)
PROCESS_REPO_ROOT=$(canonical_git_root "$PROCESS_CWD")
if [ -z "$PROCESS_REPO_ROOT" ]; then
  PROCESS_MARKER_ROOT=$(nearest_pmai_marker_root "$PROCESS_CWD")
  if [ -n "$PROCESS_MARKER_ROOT" ]; then
    block_for_hook_failure \
      "当前目录命中 PMAI 仓标记，但 Git 不可用或仓库定位失败：$PROCESS_MARKER_ROOT"
  fi
fi
if command -v python3 >/dev/null 2>&1; then
  if ! PROCESS_REPO_KIND=$(repo_kind "$PROCESS_REPO_ROOT"); then
    if has_possible_pmai_marker "$PROCESS_REPO_ROOT"; then
      block_for_hook_failure \
        "PMAI hook 需要 python3 和可信仓库身份解析器，但当前无法可靠运行。"
    fi
    PROCESS_REPO_KIND="uninitialized"
  fi
else
  if has_possible_pmai_marker "$PROCESS_REPO_ROOT"; then
    block_for_hook_failure "PMAI hook 需要 python3，但当前宿主无法运行 python3。"
  fi
  PROCESS_REPO_KIND="uninitialized"
fi

# Kimi runs managed hooks with the session cwd and emits that same cwd in the
# payload. The process cwd is therefore the routing boundary available before
# stdin is complete. Global hooks must not parse or cap ordinary-repo payloads.
case "$PROCESS_REPO_KIND" in
  generator|consumer) ;;
  *) exit 0 ;;
esac

PYTHON3_READY=0
if command -v python3 >/dev/null 2>&1; then
  PYTHON3_READY=1
fi
NODE_BIN=$(command -v node 2>/dev/null || true)
if [ "$PYTHON3_READY" != "1" ]; then
  case "$PROCESS_REPO_KIND" in
    generator|consumer)
      block_for_hook_failure "PMAI hook 需要 python3，但当前宿主无法运行 python3。"
      ;;
  esac
  if [ -z "$NODE_BIN" ]; then
    block_for_hook_failure \
      "python3 不可用，且可信 Node fallback 不可用，无法分类 hook 输入目录。"
  fi
fi

INPUT_FILE=$(mktemp)
BUDGET_CLOCK_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE" "$BUDGET_CLOCK_FILE"' EXIT
INPUT_READ_STATUS=0
INPUT_READER="python"
if [ "$PYTHON3_READY" = "1" ]; then
  python3 -c '
import os
import select
import sys
import time

output_path = sys.argv[1]
clock_path = sys.argv[3]


def shared_clock():
    clock_gettime_ns = getattr(time, "clock_gettime_ns", None)
    clock_monotonic = getattr(time, "CLOCK_MONOTONIC", None)
    if callable(clock_gettime_ns) and clock_monotonic is not None:
        return "monotonic", clock_gettime_ns(clock_monotonic)
    return "wall", time.time_ns()


clock_kind, started_ns = shared_clock()
with open(clock_path, "w", encoding="ascii") as clock:
    clock.write(f"{clock_kind}:{started_ns}")
try:
    timeout_ms = int(sys.argv[2])
except ValueError:
    timeout_ms = 1500
try:
    total_budget_ms = int(sys.argv[4])
except ValueError:
    total_budget_ms = 7000
total_budget_ms = min(max(total_budget_ms, 1), 7000)
timeout_ms = min(max(timeout_ms, 1), 2000, max(total_budget_ms - 100, 1))
deadline = time.monotonic() + timeout_ms / 1000
total = 0
with open(output_path, "wb") as output:
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise SystemExit(124)
        ready, _, _ = select.select([sys.stdin.buffer], [], [], remaining)
        if not ready:
            raise SystemExit(124)
        chunk = os.read(sys.stdin.buffer.fileno(), 65536)
        if not chunk:
            break
        total += len(chunk)
        if total > 4 * 1024 * 1024:
            raise SystemExit(125)
        output.write(chunk)
' "$INPUT_FILE" \
    "${PMAI_KIMI_STDIN_TIMEOUT_MS:-${PMAI_ACTIVE_BUILD_STDIN_TIMEOUT_MS:-1500}}" \
    "$BUDGET_CLOCK_FILE" \
    "${PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS:-7000}"
  INPUT_READ_STATUS=$?
else
  INPUT_READER="node"
  read_input_with_node "$INPUT_FILE" \
    "${PMAI_KIMI_STDIN_TIMEOUT_MS:-${PMAI_ACTIVE_BUILD_STDIN_TIMEOUT_MS:-1500}}" \
    "$BUDGET_CLOCK_FILE" \
    "${PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS:-7000}"
  INPUT_READ_STATUS=$?
fi

# command -v 只能证明入口存在。Python 启动后若在读取阶段异常，继续用同一份
# 有界缓存交给可信 Node reader；无法恢复的半包会在后续 JSON 分类时失败关闭。
case "$INPUT_READ_STATUS" in
  0|124|125) ;;
  *)
    if [ "$INPUT_READER" = "python" ] && [ -n "$NODE_BIN" ]; then
      PYTHON3_READY=0
      INPUT_READER="node"
      read_input_with_node "$INPUT_FILE" \
        "${PMAI_KIMI_STDIN_TIMEOUT_MS:-${PMAI_ACTIVE_BUILD_STDIN_TIMEOUT_MS:-1500}}" \
        "$BUDGET_CLOCK_FILE" \
        "${PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS:-7000}"
      INPUT_READ_STATUS=$?
    fi
    ;;
esac

case "$INPUT_READ_STATUS" in
  0) ;;
  124)
    if [ "$MODE" = "prompt-build" ]; then
      if ! PROMPT_BUILD_OUTPUT=$(emit_prompt_build_unavailable \
        "宿主 hook 输入在读取期限内未结束。"); then
        block_for_hook_failure "无法生成 prompt-build 的失败关闭上下文。"
      fi
      printf '%s' "$PROMPT_BUILD_OUTPUT"
      exit 0
    fi
    block_for_hook_failure "hook 输入在读取期限内未结束。"
    ;;
  125) block_for_hook_failure "hook 输入超过 4 MiB 上限。" ;;
  *)
    if [ "$INPUT_READER" = "node" ]; then
      block_for_hook_failure \
        "可信 Node fallback 无法可靠读取 hook 输入（退出状态 ${INPUT_READ_STATUS}）。"
    fi
    block_for_hook_failure \
      "PMAI hook 需要 python3，但当前宿主无法可靠运行 python3（输入读取退出状态 ${INPUT_READ_STATUS}）。"
    ;;
esac

HOOK_CWD="$PROCESS_CWD"
INPUT_VALID=1
INPUT_ERROR=""
PAYLOAD_PARSER="python"
INPUT_STATUS=99
if [ "$PYTHON3_READY" = "1" ]; then
  HOOK_CWD=$(python3 - "$INPUT_FILE" "$PROCESS_CWD" <<'PY' 2>/dev/null
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception:
    print(sys.argv[2])
    raise SystemExit(20)

if not isinstance(payload, dict):
    print(sys.argv[2])
    raise SystemExit(21)

cwd = payload.get("cwd")
if cwd is None or cwd == "":
    print(sys.argv[2])
elif not isinstance(cwd, str) or not cwd.strip():
    print(sys.argv[2])
    raise SystemExit(22)
else:
    print(cwd)
PY
  )
  INPUT_STATUS=$?
fi

case "$INPUT_STATUS" in
  0|20|21|22) ;;
  *)
    PYTHON3_READY=0
    PAYLOAD_PARSER="node"
    HOOK_CWD="$PROCESS_CWD"
    if [ -n "$NODE_BIN" ]; then
      HOOK_CWD=$(node_payload_cwd "$INPUT_FILE" "$PROCESS_CWD" 2>/dev/null)
      INPUT_STATUS=$?
    fi
    ;;
esac

case "$INPUT_STATUS" in
  0)
    [ -n "$HOOK_CWD" ] || HOOK_CWD="$PROCESS_CWD"
    ;;
  20)
    INPUT_VALID=0
    INPUT_ERROR="hook 输入不是合法 JSON。"
    ;;
  21)
    INPUT_VALID=0
    INPUT_ERROR="hook 输入必须是 JSON 对象。"
    ;;
  22)
    INPUT_VALID=0
    INPUT_ERROR="hook 输入的 cwd 必须是有效字符串路径。"
    ;;
  *)
    INPUT_VALID=0
    INPUT_ERROR="python3 不可用，且可信 Node fallback 无法分类 hook 输入目录。"
    ;;
esac

if [ "$PAYLOAD_PARSER" = "node" ] && [ "$INPUT_VALID" != "1" ]; then
  block_for_hook_failure "$INPUT_ERROR"
fi

REPO_ROOT=$(canonical_git_root "$HOOK_CWD")
if [ -z "$REPO_ROOT" ]; then
  HOOK_MARKER_ROOT=$(nearest_pmai_marker_root "$HOOK_CWD")
  if [ -n "$HOOK_MARKER_ROOT" ]; then
    block_for_hook_failure \
      "hook 输入目录命中 PMAI 仓标记，但 Git 不可用或仓库定位失败：$HOOK_MARKER_ROOT"
  fi
fi
if [ -z "$REPO_ROOT" ] && [ "$HOOK_CWD" != "$PROCESS_CWD" ]; then
  INPUT_VALID=0
  INPUT_ERROR="hook 输入的 cwd 无法定位 Git 仓库：$HOOK_CWD"
  HOOK_CWD="$PROCESS_CWD"
  REPO_ROOT="$PROCESS_REPO_ROOT"
fi
if [ "$PAYLOAD_PARSER" = "node" ] && [ "$INPUT_VALID" != "1" ]; then
  block_for_hook_failure "$INPUT_ERROR"
fi
[ -n "$REPO_ROOT" ] || exit 0
REPO_KIND=$(repo_kind "$REPO_ROOT")
if [ -n "$PROCESS_REPO_ROOT" ] && [ "$REPO_ROOT" != "$PROCESS_REPO_ROOT" ]; then
  case "$REPO_KIND:$PROCESS_REPO_KIND" in
    *generator*|*consumer*)
      block_for_hook_failure \
        "hook 输入 cwd 与进程 cwd 指向不同 Git 仓库，且至少一侧是 PMAI 仓。"
      ;;
  esac
fi

IS_GENERATOR=0
IS_CONSUMER=0
case "$REPO_KIND" in
  generator) IS_GENERATOR=1 ;;
  consumer) IS_CONSUMER=1 ;;
  *) exit 0 ;;
esac

if ! cd "$HOOK_CWD" 2>/dev/null; then
  block_for_hook_failure "hook 输入的 cwd 在仓库识别后不可访问：$HOOK_CWD"
fi
HOOK_CWD=$(pwd -P 2>/dev/null || true)
[ -n "$HOOK_CWD" ] || block_for_hook_failure "无法规范化 hook 输入的 cwd。"

if [ "$PYTHON3_READY" != "1" ]; then
  block_for_hook_failure "PMAI hook 需要 python3，但当前宿主无法运行 python3。"
fi
if [ "$INPUT_VALID" != "1" ]; then
  block_for_hook_failure "$INPUT_ERROR"
fi

run_node_hook() {
  local script="$1"
  local label="${2:-$(basename "$script")}"
  if [ ! -f "$script" ]; then
    block_for_hook_failure "$label 的可信 hook 文件缺失：$script"
  fi
  if ! command -v node >/dev/null 2>&1; then
    block_for_hook_failure "$label 需要 node，但当前宿主无法解析 node 命令。"
  fi
  node "$script" < "$INPUT_FILE"
  local status=$?
  if [ "$status" != "0" ]; then
    block_for_hook_failure "$label 执行失败（退出状态 ${status}）。"
  fi
  return 0
}

remaining_prompt_build_budget() {
  python3 - "$BUDGET_CLOCK_FILE" "${PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS:-7000}" <<'PY'
import math
import sys
import time

try:
    with open(sys.argv[1], encoding="ascii") as handle:
        clock_kind, started_text = handle.read().strip().split(":", 1)
        started_ns = int(started_text)
    configured_ms = int(sys.argv[2])
except (OSError, TypeError, ValueError):
    raise SystemExit(1)

if clock_kind == "monotonic":
    clock_gettime_ns = getattr(time, "clock_gettime_ns", None)
    clock_monotonic = getattr(time, "CLOCK_MONOTONIC", None)
    if not callable(clock_gettime_ns) or clock_monotonic is None:
        raise SystemExit(1)
    current_ns = clock_gettime_ns(clock_monotonic)
elif clock_kind == "wall":
    current_ns = time.time_ns()
else:
    raise SystemExit(1)

elapsed_ns = current_ns - started_ns
if elapsed_ns < 0:
    raise SystemExit(1)
total_ms = min(max(configured_ms, 1), 7000)
elapsed_ms = math.ceil(elapsed_ns / 1_000_000)
print(max(0, total_ms - elapsed_ms - 100))
PY
}

case "$MODE" in
  write)
    [ "$IS_CONSUMER" = "1" ] || exit 0
    CHECK_BRANCH="$TRUSTED_PMAI_HOME/scripts/check-branch.sh"
    if [ ! -f "$CHECK_BRANCH" ]; then
      block_for_hook_failure "write 的可信 hook 文件缺失：$CHECK_BRANCH"
    fi

    MAPPED_INPUT_FILE=$(mktemp)
    trap 'rm -f "$INPUT_FILE" "$BUDGET_CLOCK_FILE" "$MAPPED_INPUT_FILE"' EXIT
    if ! python3 - "$INPUT_FILE" "$HOOK_CWD" > "$MAPPED_INPUT_FILE" <<'PY'
import json
import sys
from pathlib import Path

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
tool_input = payload.get("tool_input")
if not isinstance(tool_input, dict):
    raise ValueError("tool_input must be an object")
base = Path(sys.argv[2]).resolve(strict=True)

def path_field(name):
    value = tool_input.get(name)
    if value is None or value == "":
        return None
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string")
    return value

def canonical(value):
    candidate = Path(value)
    if not candidate.is_absolute():
        candidate = base / candidate
    return candidate.resolve(strict=False)

file_path = path_field("file_path")
path = path_field("path")
canonical_file_path = canonical(file_path) if file_path is not None else None
canonical_path = canonical(path) if path is not None else None
if file_path is not None and path is not None:
    if canonical_file_path != canonical_path:
        raise ValueError("file_path and path resolve to different targets")
elif file_path is None:
    if canonical_path is None:
        raise ValueError("write input requires file_path or path")
    canonical_file_path = canonical_path
tool_input["file_path"] = str(canonical_file_path)
tool_input.pop("path", None)
json.dump(payload, sys.stdout, ensure_ascii=False)
PY
    then
      block_for_hook_failure "write 输入映射失败。"
    fi

    bash "$CHECK_BRANCH" < "$MAPPED_INPUT_FILE"
    CHECK_STATUS=$?
    if [ "$CHECK_STATUS" != "0" ]; then
      block_for_hook_failure "write 检查失败（退出状态 ${CHECK_STATUS}）。"
    fi
    ;;
  bash)
    [ "$IS_GENERATOR" = "1" ] || exit 0
    run_node_hook "$TRUSTED_PMAI_HOME/hooks/check-doc-currency.cjs" "check-doc-currency"
    run_node_hook "$TRUSTED_PMAI_HOME/hooks/check-sync-asset-jargon.cjs" "check-sync-asset-jargon"
    run_node_hook "$TRUSTED_PMAI_HOME/hooks/check-stage-number-jargon.cjs" "check-stage-number-jargon"
    ;;
  prompt-review)
    run_node_hook "$TRUSTED_PMAI_HOME/hooks/review-skill-guard.cjs" "prompt-review"
    ;;
  prompt-build)
    if ! PROMPT_BUILD_BUDGET=$(remaining_prompt_build_budget); then
      block_for_hook_failure "prompt-build 无法计算剩余执行预算。"
    fi
    if [ "$PROMPT_BUILD_BUDGET" -le 0 ]; then
      if ! PROMPT_BUILD_OUTPUT=$(emit_prompt_build_unavailable \
        "Kimi hook 的共享总预算已耗尽。"); then
        block_for_hook_failure "无法生成 prompt-build 的失败关闭上下文。"
      fi
      printf '%s' "$PROMPT_BUILD_OUTPUT"
      exit 0
    fi
    export PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS="$PROMPT_BUILD_BUDGET"
    run_node_hook "$TRUSTED_PMAI_HOME/hooks/active-build-guard.cjs" "prompt-build"
    ;;
esac

exit 0
