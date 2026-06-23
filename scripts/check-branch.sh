#!/usr/bin/env bash
# check-branch.sh — PreToolUse hook for Edit/Write
# Reads JSON from stdin (Claude Code hook format), enforces 4 gates.
# Output: {} on allow (exit 0), {"decision":"deny","reason":"..."} on deny (exit 2)
set -euo pipefail

# 脚本所在目录（用于找 sibling python3 helpers，I-mini 全局 / --local 副本两种模式都对）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Read JSON from stdin (one-shot) ---
INPUT=$(cat)

# --- Extract fields via python3 into a temp file for safe multiline handling ---
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

echo "$INPUT" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    ti = data.get('tool_input', data)
    fp = ti.get('file_path', '')
    old = ti.get('old_string', '')
    new = ti.get('new_string', '')
    content = ti.get('content', '')  # Write tool
except Exception:
    fp, old, new, content = '', '', '', ''

with open(sys.argv[1], 'w') as f:
    json.dump({'file_path': fp, 'old_string': old, 'new_string': new, 'content': content}, f)
" "$TMPFILE" 2>/dev/null || echo '{"file_path":"","old_string":"","new_string":"","content":""}' > "$TMPFILE"

FILE_PATH=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['file_path'])" "$TMPFILE" 2>/dev/null || echo "")

# No file path → allow
if [ -z "$FILE_PATH" ]; then
  echo '{}'
  exit 0
fi

# --- Determine main repo root and current worktree root ---
CURRENT_WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$CURRENT_WORKTREE_ROOT" ]; then
  echo '{}'
  exit 0
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
            wt_branch = parts[1]  # 例如 'req-001-xxx'
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
      reason="写仓库外的路径被拒绝：${FILE_PATH}。业务改动必须在 main 或 req worktree 内进行。如需写临时文件请用 /tmp/ 或 /var/tmp/。"
      reason_escaped=$(echo "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])")
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
  echo '{}'
  exit 0
fi

# BRANCH 用于 gate 检查：取目标文件所在 worktree 的分支
# 如果目标在 main 仓根，就用当前分支；如果在某个 worktree 里，用那个 worktree 的分支
if [ -n "$EFFECTIVE_BRANCH" ]; then
  BRANCH="$EFFECTIVE_BRANCH"
else
  BRANCH="$CURRENT_BRANCH"
fi

# --- Helper: deny with reason ---
deny() {
  local reason="$1"
  reason=$(echo "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip())[1:-1])")
  printf '{"decision": "deny", "reason": "%s"}\n' "$reason"
  exit 2
}

# ======================================================
# GATE 1: Req stage 直改拦截
# ======================================================
# 批 2：req 状态真相源迁到 docs/modules/<模块>/.req-meta.json（补批 1 留下的 GATE2 洞——
# main 写保护放宽后 docs/** 全放行，stage 字段必须仍由 req-transition 走，不能 main 直改）。
# 旧 requirements/*/.req-meta.json 路径保留（过渡期 fixture/在飞 req 仍可能在场）。
case "$REL_PATH" in
  requirements/*/.req-meta.json|docs/modules/*/.req-meta.json)
    STAGE_MODIFIED=$(echo "$INPUT" | python3 -c "
import sys, json, re

data = json.load(sys.stdin)
ti = data.get('tool_input', data)
old = ti.get('old_string', '')
new = ti.get('new_string', '')
content = ti.get('content', '')
file_path = ti.get('file_path', '')

# Check Edit tool
if old or new:
    if re.search(r'\"stage\"', old) or re.search(r'\"stage\"', new):
        print('DENY')
        sys.exit(0)

# Check Write tool (full file rewrite)
if content and not old:
    if re.search(r'\"stage\"', content):
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                existing = json.load(f)
            proposed = json.loads(content)
            if existing.get('stage') != proposed.get('stage'):
                print('DENY')
                sys.exit(0)
        except (FileNotFoundError, json.JSONDecodeError, ValueError):
            pass

print('ALLOW')
" 2>/dev/null || echo "ALLOW")

    if [ "$STAGE_MODIFIED" = "DENY" ]; then
      deny "请使用 python3 $HOME/.pmai/scripts/req-transition.py 修改 req stage"
    fi
    ;;
esac

# ======================================================
# GATE 2: Main 分支写保护（白名单模式，默认拒绝）
# ======================================================
# main 分支上，只允许写入以下白名单路径。其他所有路径都拒绝。
# 业务代码、文档、配置都必须走 req 分支隔离
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  MAIN_WRITE_ALLOWED=false

  case "$REL_PATH" in
    # 框架元数据：init-project 和框架更新时需要写
    .claude/*|CLAUDE.md|.gitignore|README.md)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 批 2：删旧 requirements/active|closed/* 白名单条目（真相源已迁 docs/modules/*，
    # 走下方 docs/* 全放行；req 状态文件的 stage 字段仍由 GATE 2 拦直改）。
    # 运行时元数据：不入库，但允许写（gitignored）
    .runs/*|.worktrees/*|.dev-port)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 探索变体目录：mocks/ 是探索草稿的家（连当场否掉的草图都留），与产品真相源（prototype/ + docs/）
    # 两回事——探索发生在 main 上（new-req 范围确认期视觉变体探）、本就该随时可写。manifest + 生成的看版页同此。
    mocks/*)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 文档全树（lifecycle 迁移批 1，§1③ 写保护放宽）：docs/** 一律放行 main 直接写。
    # 「讨论=无 worktree、小改直接改」的前提是文档可在 main 上动——含 docs/modules 三件套 +
    # .req-meta.json 非状态字段（stage 字段仍由 GATE 2 走 req-transition 拦）、PRODUCT-STATE /
    # PRODUCT-RULES / TODO / decisions / PRODUCT / DESIGN。删了旧「docs/modules 已 commit 后拒绝」
    # 的 git-log 门控、删了 deposit marker 门控（deposit skill 进 dormant）。
    # 边界：prototype/ 及业务代码目录仍走 worktree（默认拒绝，见下方 deny）。
    docs/*)
      MAIN_WRITE_ALLOWED=true
      ;;
  esac

  if [ "$MAIN_WRITE_ALLOWED" != "true" ]; then
    deny "main 分支写保护：不允许直接修改 ${REL_PATH}。业务代码必须通过 build/req worktree 操作。如需初始化新项目，请用 /pmai-init-project 创建新的业务项目仓。"
  fi
fi

# ======================================================
# GATE 3: Worktree 作用域保护
# ======================================================
case "$BRANCH" in
  req-*)
    # req/build worktree 可以改 prototype/；文档真相源在 main/docs 或 req docs 下按具体流程沉淀。
    ;;
esac

# --- All gates passed ---
echo '{}'
exit 0
