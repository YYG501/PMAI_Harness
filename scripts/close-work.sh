#!/usr/bin/env bash
# close-work.sh — Work 收尾（方案 A·清模块 .work-meta）
# 用法: bash scripts/close-work.sh <模块目录>  （= docs/modules/<模块>/）
#
# 新模型（lifecycle 迁移批 3，方案 A）：
#   一个模块 = 一个长期文件夹 docs/modules/<模块>/（三件套 spec/decisions/discussion 长期真相源）。
#   「在做的工作」由模块内 .work-meta.json（status=active）标记；收尾 = 删掉 .work-meta.json，
#   模块文件夹本身不消失（不再 git mv active→closed，不再留 status=closed 占位）。
#
# 两条 close 路径由 /pmai-build 写入的 build 合同决定：
#   build.mode=worktree → 在记录的 build 分支内删 .work-meta + commit → merge 回 main（ancestor 验证）。
#   build.mode=main     → 直接在 main 删 .work-meta + commit，跳 merge。
#
# 前置条件：
#   1. 在主仓 cwd 运行（不在 worktree 内）
#   2. PM 明确确认当前模块可以收尾；stage 只作为展示状态，不再作为机器门。

set -euo pipefail

# 在任何 cd 之前记录调用方的 cwd
CALLER_CWD="$(pwd -P 2>/dev/null || echo "")"

WORK_DIR="${1:?用法: close-work.sh <模块目录>}"

# --- Setup PYTHONPATH for _lib.state ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib/_setup-pythonpath.sh"
source "$SCRIPT_DIR/_lib/worktree.sh"

# --- 找到主仓根目录 ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

WORK_META="$WORK_DIR/.work-meta.json"
if [ ! -f "$WORK_META" ]; then
  echo "❌ 模块工作状态文件不存在: $WORK_META" >&2
  echo "   （模块没有在做的工作，或已收尾。）" >&2
  exit 1
fi

# --- 读取模块工作信息（走 _lib.state.read_work_meta CLI；单次读全部字段）---
WORK_META_JSON=$(python3 -m _lib.state read_work_meta "$WORK_DIR" 2>/dev/null || echo "{}")
WORK_ID=$(printf '%s' "$WORK_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")

if ! BUILD_CONTRACT_JSON=$(python3 "$SCRIPT_DIR/build-contract.py" validate-close "$WORK_DIR" 2>/tmp/pmai-build-contract.err.$$); then
  cat /tmp/pmai-build-contract.err.$$ >&2
  rm -f /tmp/pmai-build-contract.err.$$
  exit 1
fi
rm -f /tmp/pmai-build-contract.err.$$

BUILD_MODE=$(printf '%s' "$BUILD_CONTRACT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode',''))")
WORK_BRANCH=$(printf '%s' "$BUILD_CONTRACT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('branch',''))")

# --- 判定 close 路径：只看 build 合同，不从当前 cwd / 分支形态猜 ---
HAVE_BRANCH=false
if [ "$BUILD_MODE" = "worktree" ]; then
  if [ -n "$WORK_BRANCH" ] && git show-ref --verify --quiet "refs/heads/$WORK_BRANCH" 2>/dev/null; then
    HAVE_BRANCH=true
  else
    echo "❌ build 合同要求隔离环境收尾，但找不到记录的分支: ${WORK_BRANCH:-<empty>}。" >&2
    echo "   请先恢复本次 build 分支，或补全/修正 build 合同后再收尾。" >&2
    exit 1
  fi
fi

WORK_WORKTREE=""
if [ "$HAVE_BRANCH" = "true" ]; then
  WORK_WORKTREE=$(resolve_worktree_path "$WORK_BRANCH" "$REPO_ROOT" || true)
fi

if [ "$BUILD_MODE" = "worktree" ] && { [ -z "$WORK_WORKTREE" ] || [ ! -d "$WORK_WORKTREE" ]; }; then
  echo "❌ build 合同要求隔离环境收尾，但找不到记录分支对应的 worktree: ${WORK_BRANCH}。" >&2
  echo "   close 不会退化成主线直收；请先恢复 worktree，或补全本次 build 上下文。" >&2
  exit 1
fi

if [ "$BUILD_MODE" = "worktree" ]; then
  # ======================================================
  # 路径 A：有 worktree + 分支 → 在 work branch清 .work-meta + commit → merge main
  # ======================================================

  # --- 校验：调用方 cwd 不能在 worktree 内 ---
  # 原因：删 worktree 前 Claude Code 父进程 cwd 必须不在其内，否则 Stop hook posix_spawn ENOENT
  WORK_WORKTREE_REAL="$(cd "$WORK_WORKTREE" 2>/dev/null && pwd -P || echo "$WORK_WORKTREE")"
  if [ -n "$CALLER_CWD" ] && [ -n "$WORK_WORKTREE_REAL" ]; then
    if [ "$CALLER_CWD" = "$WORK_WORKTREE_REAL" ] || \
       printf '%s/' "$CALLER_CWD" | grep -qF "${WORK_WORKTREE_REAL}/"; then
      echo "⚠️ 这个会话窗口正站在 worktree 里头，删不掉它自己所在的 worktree。" >&2
      echo "   （系统限制：删 worktree 时进程不能正站在里面，否则收尾会报 ENOENT——这不是你的操作错。）" >&2
      echo "" >&2
      echo "   当前位置：    $CALLER_CWD" >&2
      echo "   要收尾的 worktree：$WORK_WORKTREE_REAL" >&2
      echo "" >&2
      echo "   换个地方跑 close 就行（二选一）：" >&2
      echo "   · 推荐：到主仓窗口（位置 = ${REPO_ROOT}）跑 —— 主仓会话本就能远程操作 worktree：" >&2
      echo "       bash scripts/close-work.sh $WORK_DIR" >&2
      echo "   · 或：当前工作先不收尾、worktree 留着继续干，等回到主仓窗口再 /pmai-build-close。" >&2
      exit 1
    fi
  fi

  # 模块目录在 worktree 内的相对路径（WORK_DIR 可能是主仓侧路径；统一推导 worktree 内同名模块）
  MODULE_BASENAME=$(basename "$WORK_DIR")
  REL_MODULE="docs/modules/$MODULE_BASENAME"
  WT_MODULE_META="$WORK_WORKTREE/$REL_MODULE/.work-meta.json"

  cd "$WORK_WORKTREE"

  # close-work 只允许动当前模块的 .work-meta。worktree 里漂着其他未提交改动时，
  # 直接 git add -A 会把无关代码/文档静默带进 main。
  WORK_STATUS=$(git status --porcelain --untracked-files=all 2>/dev/null || true)
  UNRELATED_DIRTY=""
  if [ -n "$WORK_STATUS" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      path="${line:3}"
      case "$path" in
        *" -> "*) path="${path##* -> }" ;;
      esac
      case "$path" in
        "$REL_MODULE"/*) ;;
        *)
          UNRELATED_DIRTY="${UNRELATED_DIRTY}${line}"$'\n'
          ;;
      esac
    done <<< "$WORK_STATUS"
  fi
  if [ -n "$UNRELATED_DIRTY" ]; then
    echo "❌ worktree 有当前模块目录外的未提交改动，close-work 不会静默带入 main：" >&2
    printf "%s" "$UNRELATED_DIRTY" >&2
    echo "" >&2
    echo "请先提交、移走或清理这些改动后再运行 close-work。" >&2
    exit 1
  fi

  # 记录 pre-close HEAD：如果后面 merge 失败，把 work branch reset 回这个点，避免半关闭状态
  PRE_CLOSE_HEAD=$(git rev-parse HEAD 2>/dev/null)
  if [ -z "$PRE_CLOSE_HEAD" ]; then
    echo "❌ 无法读取 work branch HEAD，中止。" >&2
    exit 1
  fi

  # Step 1: 在 work branch删模块 .work-meta（方案 A：清工作状态层，三件套留在场）+ commit
  if [ -f "$WT_MODULE_META" ]; then
    git rm -q -- "$REL_MODULE/.work-meta.json" 2>&1 || {
      echo "❌ 在 worktree 中删除 .work-meta.json 失败。请人工检查。" >&2
      exit 1
    }
    echo "🧹 已清模块工作状态: $REL_MODULE/.work-meta.json"
  fi

  if ! git commit -m "close: 收尾 ${WORK_ID}（清模块 .work-meta）" 2>&1; then
    echo "❌ 提交清状态改动到 work branch失败（可能是 git 身份未配置或 hook 拒绝）。" >&2
    exit 1
  fi
  echo "✅ 清状态改动已 commit 到 $WORK_BRANCH"

  # Step 2: 切到主仓 main 执行 merge
  cd "$REPO_ROOT"

  CURRENT=$(git branch --show-current 2>/dev/null || true)
  if [ "$CURRENT" != "main" ]; then
    git checkout main 2>/dev/null || {
      echo "❌ 无法切到 main 分支（可能有未提交改动）。请先处理。" >&2
      exit 1
    }
    echo "🔙 已切到 main 分支"
  fi

  if ! git merge "$WORK_BRANCH" --no-edit -m "close: $WORK_ID" 2>&1; then
    # merge 失败：先 abort merge，再把 work branch reset 回 pre-close，避免半关闭状态
    git merge --abort 2>/dev/null || true
    if ! git -C "$WORK_WORKTREE" reset --hard "$PRE_CLOSE_HEAD" 2>&1; then
      echo "❌ merge 失败，且回滚 work branch失败。需要人工修复: cd $WORK_WORKTREE && git reset --hard $PRE_CLOSE_HEAD" >&2
      exit 1
    fi
    echo "❌ merge ${WORK_BRANCH} → main 失败。work branch已回滚到 ${PRE_CLOSE_HEAD}，请手动解决冲突后再运行 close-work。" >&2
    exit 1
  fi

  # 验证 merge 生效（I-CR6 ancestor 验证）
  WORK_HEAD=$(git rev-parse "$WORK_BRANCH" 2>/dev/null)
  if ! git merge-base --is-ancestor "$WORK_HEAD" HEAD 2>/dev/null; then
    git reset --hard "HEAD@{1}" 2>/dev/null || true
    git -C "$WORK_WORKTREE" reset --hard "$PRE_CLOSE_HEAD" 2>/dev/null || true
    echo "❌ merge 声称成功但 $WORK_BRANCH 的提交未进入 main。数据完整性校验失败，已回滚。" >&2
    exit 1
  fi

  echo "🔀 已合并 $WORK_BRANCH → main（已验证提交落地）"

  # Step 3: 删 worktree + branch
  cd "$REPO_ROOT"

  if [ -d "$WORK_WORKTREE" ]; then
    git worktree remove "$WORK_WORKTREE" 2>/dev/null || {
      rm -rf "$WORK_WORKTREE"
      git worktree prune 2>/dev/null || true
    }
    echo "🗑  worktree 已删除: $WORK_WORKTREE"
  fi

  if git show-ref --verify --quiet "refs/heads/$WORK_BRANCH" 2>/dev/null; then
    git branch -D "$WORK_BRANCH" 2>/dev/null && echo "🗑  branch 已删除: $WORK_BRANCH"
  fi

else
  # ======================================================
  # 路径 B：build.mode=main → 直接在 main 清 .work-meta + commit（不 merge）
  # ======================================================
  cd "$REPO_ROOT"

  CURRENT=$(git branch --show-current 2>/dev/null || true)
  if [ "$CURRENT" != "main" ] && [ "$CURRENT" != "master" ]; then
    echo "❌ 无 worktree 路径要求在主仓 main 上运行，当前分支: ${CURRENT:-<detached>}。" >&2
    exit 1
  fi

  # WORK_DIR 必须落在主仓内（防止传了别处的模块目录）
  MODULE_BASENAME=$(basename "$WORK_DIR")
  MAIN_MODULE="$REPO_ROOT/docs/modules/$MODULE_BASENAME"
  MAIN_MODULE_META="$MAIN_MODULE/.work-meta.json"
  if [ ! -f "$MAIN_MODULE_META" ]; then
    echo "❌ 主仓上找不到模块 .work-meta: $MAIN_MODULE_META" >&2
    echo "   （无 worktree 路径下，模块三件套 + .work-meta 必须已在 main。）" >&2
    exit 1
  fi

  REL_MODULE="docs/modules/$MODULE_BASENAME"

  # main 污染防护：只允许本模块 .work-meta 的删除参与 commit
  DIRTY=$(git status --porcelain 2>/dev/null || true)
  if [ -n "$DIRTY" ]; then
    BAD=$(printf '%s\n' "$DIRTY" | awk -v prefix="$REL_MODULE/" '
      { path = substr($0, 4); if (index(path, prefix) != 1) print $0 }
    ')
    if [ -n "$BAD" ]; then
      echo "❌ main 分支有与本模块无关的未提交改动，拒绝 close 以防污染收尾 commit：" >&2
      echo "$BAD" >&2
      echo "请先处理（commit、stash 或 reset）这些改动后再运行 close-work。" >&2
      exit 1
    fi
  fi

  git rm -q -- "$REL_MODULE/.work-meta.json" 2>&1 || {
    echo "❌ 在 main 上删除 .work-meta.json 失败。请人工检查。" >&2
    exit 1
  }
  echo "🧹 已清模块工作状态（main 直接清，无 worktree）: $REL_MODULE/.work-meta.json"

  if ! git commit -m "close: 收尾 ${WORK_ID}（清模块 .work-meta·无 worktree）" 2>&1; then
    echo "❌ 提交收尾改动到 main 失败（可能是 git 身份未配置或 hook 拒绝）。" >&2
    exit 1
  fi
  echo "✅ 收尾改动已 commit 到 main"
fi

# --- 兜底清孤儿 worktree（按模块 .work-meta 定向；历史漏清 / 中断 close 留下的）---
cleanup_stale_worktrees "$REPO_ROOT"

echo ""
echo "✅ 当前工作已收尾: ${WORK_ID}（模块三件套留在 docs/modules/，工作状态 .work-meta 已清）"
echo "📍 当前位置: 主仓 main 分支"
echo ""
echo "运行 /pmai-design 开始下一个功能 / 模块。"
