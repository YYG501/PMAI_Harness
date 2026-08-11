#!/usr/bin/env bash
# check-branch.sh — PreToolUse hook for Edit/Write
# Reads JSON from stdin (Claude Code hook format), enforces 4 gates.
# Output: {} on allow (exit 0), {"decision":"deny","reason":"..."} on deny (exit 2)
set -euo pipefail

# 脚本所在目录（用于找 sibling python3 helpers，全局安装模式）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

deny() {
  local reason="$1"
  echo "$reason" >&2
  reason=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
  printf '{"decision": "deny", "reason": "%s"}\n' "$reason"
  exit 2
}

# --- Read JSON from stdin (one-shot) ---
INPUT=$(cat)

# --- Extract fields via python3 into a temp file for safe multiline handling ---
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

if ! printf '%s' "$INPUT" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    if not isinstance(data, dict):
        raise ValueError('hook payload must be an object')
    ti = data.get('tool_input', data)
    if not isinstance(ti, dict):
        raise ValueError('tool_input must be an object')
    file_path = ti.get('file_path')
    path_alias = ti.get('path')
    for label, value in (('file_path', file_path), ('path', path_alias)):
        if value is not None and not isinstance(value, str):
            raise ValueError(f'{label} must be a string')
    if file_path and path_alias and file_path != path_alias:
        raise ValueError('file_path and path disagree')
    fp = file_path or path_alias or ''
    if not fp or any(char in fp for char in ('\\x00', '\\r', '\\n')):
        raise ValueError('write path is missing or unsafe')
    old = ti.get('old_string', '')
    new = ti.get('new_string', '')
    content = ti.get('content', '')  # Write tool
except Exception:
    raise SystemExit(2)

with open(sys.argv[1], 'w') as f:
    json.dump({'file_path': fp, 'old_string': old, 'new_string': new, 'content': content}, f)
" "$TMPFILE" 2>/dev/null; then
  deny "写入护栏无法解析宿主载荷或取得唯一文件路径；为保护项目，已拒绝本次写入。"
fi

if ! FILE_PATH=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['file_path'])" "$TMPFILE" 2>/dev/null); then
  deny "写入护栏无法读取已校验的文件路径；为保护项目，已拒绝本次写入。"
fi

# No file path after successful parsing is an invalid hook contract.
if [ -z "$FILE_PATH" ]; then
  deny "写入护栏没有取得文件路径；为保护项目，已拒绝本次写入。"
fi

# --- Determine main repo root and current worktree root ---
CURRENT_WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$CURRENT_WORKTREE_ROOT" ]; then
  deny "写入护栏无法定位当前 Git 工作区；为保护项目，已拒绝本次写入。"
fi

# MAIN_REPO_ROOT: 主仓根（通过 git-common-dir 推导）
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  if [[ "$GIT_COMMON" == */.git/worktrees/* ]]; then
    MAIN_REPO_ROOT=$(echo "$GIT_COMMON" | sed 's|/\.git/worktrees.*||')
  elif [[ "$GIT_COMMON" == */.git ]]; then
    MAIN_REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
  else
    MAIN_REPO_ROOT="$CURRENT_WORKTREE_ROOT"
  fi
else
  MAIN_REPO_ROOT="$CURRENT_WORKTREE_ROOT"
fi

# REPO_ROOT: 路径归一化的锚点——用主仓根，这样跨 worktree 的绝对路径也能被识别
REPO_ROOT="$MAIN_REPO_ROOT"

# Normalize file_path to be relative to main repo root
# 如果路径在 .worktrees/<name>/ 里，进一步推断目标分支类型
REL_PATH_INFO=$(python3 -c "
from pathlib import Path
import sys

main_root = Path(sys.argv[1]).resolve()
cur_root = Path(sys.argv[2]).resolve()
raw_path = sys.argv[3]

if raw_path.startswith('/'):
    try:
        resolved = Path(raw_path).resolve()
    except Exception:
        resolved = Path(raw_path)
    target = resolved
else:
    rel = raw_path[2:] if raw_path.startswith('./') else raw_path
    target = (cur_root / rel).resolve()

# 检查是否在主仓范围内（主仓根 + 所有 worktree 在 .worktrees/ 下）
main_str = str(main_root) + '/'
if str(target).startswith(main_str) or str(target) == str(main_root):
    rel_to_main = str(target.relative_to(main_root)) if target != main_root else '.'
    # 检查是否在某个 worktree 里
    if rel_to_main.startswith('.worktrees/'):
        parts = rel_to_main.split('/', 2)
        if len(parts) >= 2:
            wt_branch = parts[1]  # 例如 'build-demo'
            wt_rel = parts[2] if len(parts) >= 3 else '.'
            print(f'WORKTREE|{wt_branch}|{wt_rel}')
        else:
            print(f'MAIN|{rel_to_main}')
    else:
        print(f'MAIN|{rel_to_main}')
else:
    print('__OUTSIDE_REPO__|')
" "$MAIN_REPO_ROOT" "$CURRENT_WORKTREE_ROOT" "$FILE_PATH" 2>/dev/null || echo "__OUTSIDE_REPO__|")

SCOPE="${REL_PATH_INFO%%|*}"
REMAINDER="${REL_PATH_INFO#*|}"

# File outside repo → deny（fail-closed：写仓库外的绝对路径会绕过所有 gate，所以默认拒绝）
# 允许的例外：系统临时目录（/tmp, /var/folders 等），这些写入不会影响项目代码
if [ "$SCOPE" = "__OUTSIDE_REPO__" ]; then
  case "$FILE_PATH" in
    /tmp/*|/var/tmp/*|/var/folders/*|/private/tmp/*|/private/var/*)
      # 系统临时目录：允许
      echo '{}'
      exit 0
      ;;
    *)
      reason="写仓库外的路径被拒绝：${FILE_PATH}。业务改动必须在 main 或 build worktree 内进行。如需写临时文件请用 /tmp/ 或 /var/tmp/。"
      reason_escaped=$(echo "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])")
      echo "$reason" >&2
      printf '{"decision": "deny", "reason": "%s"}\n' "$reason_escaped"
      exit 2
      ;;
  esac
fi

# 根据目标位置决定"有效分支"和"相对路径"
# - 如果目标在 .worktrees/<branch>/ 下，有效分支是 <branch>，相对路径是 worktree 内的路径
# - 否则（主仓根本身），有效分支是当前分支
if [ "$SCOPE" = "WORKTREE" ]; then
  EFFECTIVE_BRANCH="${REMAINDER%%|*}"
  REL_PATH="${REMAINDER#*|}"
else
  # 目标在主仓根（不在任何 worktree 里）。如果我们当前不在主仓根，说明是跨 worktree 写，
  # 有效分支应该是主仓的分支，而不是当前 worktree 的分支
  if [ "$CURRENT_WORKTREE_ROOT" != "$MAIN_REPO_ROOT" ]; then
    EFFECTIVE_BRANCH=$(git -C "$MAIN_REPO_ROOT" branch --show-current 2>/dev/null || echo "")
  else
    EFFECTIVE_BRANCH=""
  fi
  REL_PATH="$REMAINDER"
fi

# --- Get current branch ---
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || true)
if [ -z "$CURRENT_BRANCH" ]; then
  deny "写入护栏无法确认当前分支（可能处于 detached HEAD）；为保护项目，已拒绝本次写入。"
fi

# BRANCH 用于 gate 检查：取目标文件所在 worktree 的分支
# 如果目标在 main 仓根，就用当前分支；如果在某个 worktree 里，用那个 worktree 的分支
if [ -n "$EFFECTIVE_BRANCH" ]; then
  BRANCH="$EFFECTIVE_BRANCH"
else
  BRANCH="$CURRENT_BRANCH"
fi

# A full build may run in the current main environment only after /pmai-build
# has shown the PM confirmation card and written a versioned contract with mode=main.
# Keep the exception scoped to that contract's declared target paths; docs and
# framework metadata continue to use the ordinary whitelist below.
active_main_build_allows_path() {
  local rel_path="$1"
  python3 - "$MAIN_REPO_ROOT" "$rel_path" "$SCRIPT_DIR" <<'PY'
import json
import sys
from pathlib import Path, PurePosixPath
sys.path.insert(0, sys.argv[3])
from _lib.work_contract import normalize_work_state

repo = Path(sys.argv[1])

def normalize(raw: str) -> str:
    raw = raw.strip()
    while raw.startswith("./"):
        raw = raw[2:]
    return PurePosixPath(raw).as_posix().rstrip("/")

requested = normalize(sys.argv[2])
allowed_states = {"building", "iterating", "final_check"}

for meta_path in (repo / "docs" / "modules").glob("*/.work-meta.json"):
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        contract = normalize_work_state(meta)
        build = meta.get("build", {})
    except Exception:
        continue
    try:
        version = int(build.get("contract_version", 1))
    except (TypeError, ValueError):
        continue
    if version < 2 or build.get("mode") != "main":
        continue
    if contract.lifecycle_state not in allowed_states:
        continue
    target = build.get("target", {})
    paths = target.get("paths", []) if isinstance(target, dict) else []
    for raw in paths:
        if not isinstance(raw, str) or not raw.strip() or raw.startswith("/"):
            continue
        normalized = normalize(raw)
        if normalized in {"", "."}:
            continue
        if requested == normalized or requested.startswith(normalized + "/"):
            raise SystemExit(0)
raise SystemExit(1)
PY
}

# ======================================================
# GATE 1: Main 分支写保护（白名单模式，默认拒绝）
# ======================================================
# main 分支上，只允许写入以下白名单路径。其他所有路径都拒绝。
# 业务代码默认走 build 分支隔离；PM 明确确认当前环境且已有 mode=main
# 合同时，仅合同 target.paths 可写。根目录项目脊柱和 docs/** 可在 main 上维护。
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  MAIN_WRITE_ALLOWED=false

  case "$REL_PATH" in
    # 框架元数据：init-project 和框架更新时需要写
    .claude/*|.codex/hooks.json|.kimi-code/*|.opencode/*|opencode.json|AGENTS.md|CLAUDE.md|.gitignore|README.md)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 项目脊柱：PM 和 AI 每次进项目都要认的主上下文，放仓库根目录。
    PRODUCT.md|PRODUCT-STATE.md|PRODUCT-RULES.md|DESIGN.md|TODO.md)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 旧 requirements/active|closed/* 不再是状态真相源，也不在 main 写入白名单内。
    # 运行时元数据：不入库，但允许写（gitignored）
    .runs/*|.worktrees/*|.dev-port)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 探索变体目录：mockups/ 是探索草稿的家（连当场否掉的草图都留），与产品真相源（prototype/ + docs/）
    # 两回事——探索发生在 main 上（design 期视觉变体探）、本就该随时可写。manifest + 生成的看版页同此。
    mockups/*)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 文档全树：docs/** 一律放行 main 直接写。
    # 「讨论=无 worktree、小改直接改」的前提是文档可在 main 上动——含 docs/modules 三件套、
    # .work-meta.json、输入材料、交付物、归档和 docs/decisions 冻结档。
    # 边界：prototype/ 及业务代码目录仍走 worktree（默认拒绝，见下方 deny）。
    docs/*)
      MAIN_WRITE_ALLOWED=true
      ;;
    # PMAI 内部运行态：审计、镜像站点走查和本地流程状态，允许写。
    .pm-workflow/*)
      MAIN_WRITE_ALLOWED=true
      ;;
  esac

  if [ "$MAIN_WRITE_ALLOWED" != "true" ] && active_main_build_allows_path "$REL_PATH"; then
    MAIN_WRITE_ALLOWED=true
  fi

  if [ "$MAIN_WRITE_ALLOWED" != "true" ]; then
    deny "main 分支写保护：不允许直接修改 ${REL_PATH}。完整 build 需要先由 PM 确认工作环境，并由 /pmai-build 写入目标范围；否则请使用独立环境。如需初始化新项目，请用 /pmai-init-project 创建新的业务项目仓。"
  fi
fi

# ======================================================
# GATE 3: Worktree 作用域保护
# ======================================================
case "$BRANCH" in
  build-*)
    # build worktree 可以改 prototype/；文档真相源在 main/docs 或模块 docs 下按具体流程沉淀。
    ;;
esac

# --- All gates passed ---
echo '{}'
exit 0
