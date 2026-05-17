#!/usr/bin/env bash
# check-branch.sh — PreToolUse hook for Edit/Write
# Reads JSON from stdin (Claude Code hook format), enforces 4 gates.
# Output: {} on allow (exit 0), {"decision":"deny","reason":"..."} on deny (exit 2)
set -euo pipefail

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
            wt_branch = parts[1]  # 例如 'task-001-xxx' 或 'req-001-xxx'
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
      reason="写仓库外的路径被拒绝：${FILE_PATH}。业务改动必须在 req/task worktree 内进行。如需写临时文件请用 /tmp/ 或 /var/tmp/。"
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
# GATE 1: Task 状态直改拦截
# ======================================================
case "$REL_PATH" in
  requirements/*/tasks/task-*.md)
    # 用 _lib.state.parse_status_from_text 检测状态字段
    # 双兼容 v1（**状态：**）+ v2（| **状态** |）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/_lib/_setup-pythonpath.sh"

    STATUS_MODIFIED=$(echo "$INPUT" | python3 -c "
import sys, json
from _lib.state import parse_status_from_text

data = json.load(sys.stdin)
ti = data.get('tool_input', data)
old = ti.get('old_string', '')
new = ti.get('new_string', '')
content = ti.get('content', '')
file_path = ti.get('file_path', '')

# Edit tool: check if old_string or new_string touches status
if old or new:
    old_status = parse_status_from_text(old)
    new_status = parse_status_from_text(new)
    if old_status is not None or new_status is not None:
        # 任一边有状态字段
        if old_status != new_status:
            print('DENY')
            sys.exit(0)

# Write tool: content vs existing file
if content and not old:
    proposed = parse_status_from_text(content)
    if proposed:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                existing_content = f.read()
            existing = parse_status_from_text(existing_content)
            if existing and proposed != existing:
                print('DENY')
                sys.exit(0)
        except FileNotFoundError:
            pass  # New file creation — allow

print('ALLOW')
" 2>/dev/null || echo "ALLOW")

    if [ "$STATUS_MODIFIED" = "DENY" ]; then
      deny "请使用 python3 .claude/scripts/task-transition.py 修改 task 状态"
    fi
    ;;
esac

# ======================================================
# GATE 2: Req stage 直改拦截
# ======================================================
case "$REL_PATH" in
  requirements/*/.req-meta.json)
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
      deny "请使用 python3 .claude/scripts/req-transition.py 修改 req stage"
    fi
    ;;
esac

# ======================================================
# GATE 3: Main 分支写保护（白名单模式，默认拒绝）
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
    # req 生命周期元数据：close-req/cancel-req 需要在 main 上动 requirements/ 目录
    requirements/active/*|requirements/closed/*)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 运行时元数据：不入库，但允许写（gitignored）
    .runs/*|.worktrees/*|.dev-port)
      MAIN_WRITE_ALLOWED=true
      ;;
    # 项目启动时的初始化（init-project.sh 的产出）
    docs/CONTEXT.md|docs/DESIGN.md|docs/prd.md|docs/modules/*)
      # 这些文档首次创建时可写（init），后续修改必须走 req 分支
      # 用 git log 判断：如果还没 commit 过，允许；否则拒绝
      if git -C "$REPO_ROOT" log --oneline -1 -- "$REL_PATH" 2>/dev/null | grep -q .; then
        deny "文档 $REL_PATH 已存在，不能在 main 分支直接修改。请通过 req 分支修改（/doc-update）。"
      fi
      MAIN_WRITE_ALLOWED=true
      ;;
  esac

  if [ "$MAIN_WRITE_ALLOWED" != "true" ]; then
    deny "main 分支写保护：不允许直接修改 ${REL_PATH}。业务代码和文档必须通过 req/task 分支操作。如需初始化新项目，请用 /init-project 创建新的业务项目仓。"
  fi
fi

# ======================================================
# GATE 4: Worktree 作用域保护
# ======================================================
case "$BRANCH" in
  task-*)
    case "$REL_PATH" in
      docs/*)
        deny "task worktree 中不能编辑 docs/ 下的文件，文档改动请在 req 分支操作"
        ;;
    esac
    ;;
  req-*)
    case "$REL_PATH" in
      prototypes/*)
        deny "req worktree 中不能编辑 prototypes/ 下的文件，代码改动请在 task 分支操作"
        ;;
    esac
    ;;
esac

# ======================================================
# GATE 5: Task 状态约束（I-CB10）
# 只有 task 状态 == 执行中 才允许写 task worktree 下的代码。
# 目的：防 agent 跳过 /task-confirm → task-transition → /task-execute 流程直接写代码。
# ======================================================
case "$BRANCH" in
  task-*)
    # 豁免：task 文件本身（填执行日志/自审记录/文档偏差）+ 运行时元数据
    case "$REL_PATH" in
      requirements/*/tasks/task-*.md)
        # task 文件本身的写入：允许（gate 1 已经保护状态字段不被直改）
        ;;
      .runs/*|.worktrees/*|.dev-port)
        # 运行时元数据：gitignore，放行
        ;;
      *)
        # 其他路径（prototypes/ 代码、docs/ 等）：要求状态 == 执行中
        # 定位 task 文件：task 文件存在于 task worktree 和 req worktree 里，不在主仓根
        # 搜索顺序：优先 task 自己的 worktree → fallback 所有 worktree
        TASK_FILE="$MAIN_REPO_ROOT/.worktrees/$BRANCH"
        TASK_FILE=$(find "$MAIN_REPO_ROOT/.worktrees" -type f -path "*/tasks/${BRANCH}.md" 2>/dev/null | head -1)
        if [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
          deny "I-CB10: 找不到 task 分支 ${BRANCH} 对应的 task 文件，无法校验状态。请通过 /task-confirm 正常创建。"
        fi

        TASK_STATUS=$(python3 "${MAIN_REPO_ROOT}/.claude/scripts/task-transition.py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
        if [ "$TASK_STATUS" != "执行中" ]; then
          deny "I-CB10: task 状态为「${TASK_STATUS:-未知}」，不允许写 task worktree 代码。正确流程：1) /task-confirm 转「执行中」  2) /task-execute 启动执行器  3) 再改代码。若需补填 task 文件的执行日志/文档偏差/自审记录，只能改 task 文件本身。"
        fi
        ;;
    esac
    ;;
esac

# --- All gates passed ---
echo '{}'
exit 0
