#!/usr/bin/env bash
# close-req.sh — Req 收尾（方案 A·清模块 .req-meta）
# 用法: bash scripts/close-req.sh <模块目录>  （= docs/modules/<模块>/）
#
# 新模型（lifecycle 迁移批 3，方案 A）：
#   一个模块 = 一个长期文件夹 docs/modules/<模块>/（三件套 spec/decisions/discussion 长期真相源）。
#   「在做的工作」由模块内 .req-meta.json（status=active）标记；收尾 = 删掉 .req-meta.json，
#   模块文件夹本身不消失（不再 git mv active→closed，不再留 status=closed 占位）。
#
# 两条 close 路径：
#   有 worktree + 分支 → 在 worktree 内删 .req-meta + commit → merge 回 main（ancestor 验证）。
#   无 worktree / 无分支（讨论 / 小改直接在 main 改的）→ 直接在 main 删 .req-meta + commit，跳 merge。
#
# 前置条件：
#   1. 在主仓 cwd 运行（不在 req worktree 内）
#   2. stage = 4（六步「沉淀」= MAX_STAGE；close-req/SKILL.md Phase 1 已 --to 4）
#   3. 该模块下所有 task 已关闭

set -euo pipefail

# 在任何 cd 之前记录调用方的 cwd
CALLER_CWD="$(pwd -P 2>/dev/null || echo "")"

REQ_DIR="${1:?用法: close-req.sh <模块目录>}"

# --- Setup PYTHONPATH for _lib.state ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib/_setup-pythonpath.sh"
source "$SCRIPT_DIR/_lib/worktree.sh"
source "$SCRIPT_DIR/_lib/symlink-prd.sh"

# --- 找到主仓根目录 ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

REQ_META="$REQ_DIR/.req-meta.json"
if [ ! -f "$REQ_META" ]; then
  echo "❌ 模块工作状态文件不存在: $REQ_META" >&2
  echo "   （模块没有在做的工作，或已收尾。）" >&2
  exit 1
fi

# --- 读取模块工作信息（走 _lib.state.read_req_meta CLI；单次读全部字段）---
REQ_META_JSON=$(python3 -m _lib.state read_req_meta "$REQ_DIR" 2>/dev/null || echo "{}")
REQ_BRANCH=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('branch',''))")
REQ_ID=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
REQ_STAGE=$(printf '%s' "$REQ_META_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stage',''))")

# --- 校验 stage ---
# 六步：沉淀 = stage 4（MAX_STAGE）。/pmai-next 走到沉淀时 close-req/SKILL.md Phase 1 先 --to 4。
if [ "$REQ_STAGE" != "4" ]; then
  echo "❌ 模块当前在 stage ${REQ_STAGE}，不是 stage 4（沉淀）。请先推进到沉淀阶段（/pmai-next）。" >&2
  exit 1
fi

# --- 校验所有 task 已关闭（task 系列 dormant：模块下通常无 tasks/，循环空过自动通过）---
# 用 _lib.state.get_status 双兼容 v1/v2 格式
TASKS_DIR="$REQ_DIR/tasks"
if [ -d "$TASKS_DIR" ]; then
  OPEN_TASKS=""
  for TF in "$TASKS_DIR"/task-*.md; do
    [ -f "$TF" ] || continue
    case "$TF" in *.engineering.md) continue;; esac
    STATUS=$(python3 -m _lib.state get_status "$TF" 2>/dev/null || echo "")
    case "$STATUS" in
      待执行|执行中)
        OPEN_TASKS="${OPEN_TASKS}${TF}"$'\n'
        ;;
    esac
  done
  if [ -n "$OPEN_TASKS" ]; then
    echo "❌ 以下 task 尚未关闭：" >&2
    printf "%s" "$OPEN_TASKS" >&2
    exit 1
  fi
fi

# --- 判定 close 路径：有无分支 / worktree ---
# I-CR3/4 改语义（lifecycle 迁移批 3）：分支 / worktree 可选。
#   分支存在 + worktree 存在 → merge 路径（先 commit 清 .req-meta 到 req 分支，再 merge main）。
#   分支不存在 或 worktree 不存在 → main 直接清 .req-meta（讨论 / 小改无 worktree 的常态）。
HAVE_BRANCH=false
if [ -n "$REQ_BRANCH" ] && git show-ref --verify --quiet "refs/heads/$REQ_BRANCH" 2>/dev/null; then
  HAVE_BRANCH=true
fi

REQ_WORKTREE=""
if [ "$HAVE_BRANCH" = "true" ]; then
  REQ_WORKTREE=$(resolve_worktree_path "$REQ_BRANCH" "$REPO_ROOT" || true)
fi

if [ "$HAVE_BRANCH" = "true" ] && [ -n "$REQ_WORKTREE" ] && [ -d "$REQ_WORKTREE" ]; then
  # ======================================================
  # 路径 A：有 worktree + 分支 → 在 req 分支清 .req-meta + commit → merge main
  # ======================================================

  # --- 校验：调用方 cwd 不能在 req worktree 内 ---
  # 原因：删 worktree 前 Claude Code 父进程 cwd 必须不在其内，否则 Stop hook posix_spawn ENOENT
  REQ_WORKTREE_REAL="$(cd "$REQ_WORKTREE" 2>/dev/null && pwd -P || echo "$REQ_WORKTREE")"
  if [ -n "$CALLER_CWD" ] && [ -n "$REQ_WORKTREE_REAL" ]; then
    if [ "$CALLER_CWD" = "$REQ_WORKTREE_REAL" ] || \
       printf '%s/' "$CALLER_CWD" | grep -qF "${REQ_WORKTREE_REAL}/"; then
      echo "⚠️ 这个会话窗口正站在 worktree 里头，删不掉它自己所在的 worktree。" >&2
      echo "   （系统限制：删 worktree 时进程不能正站在里面，否则收尾会报 ENOENT——这不是你的操作错。）" >&2
      echo "" >&2
      echo "   当前位置：    $CALLER_CWD" >&2
      echo "   要收尾的 worktree：$REQ_WORKTREE_REAL" >&2
      echo "" >&2
      echo "   换个地方跑 close 就行（二选一）：" >&2
      echo "   · 推荐：到主仓窗口（位置 = ${REPO_ROOT}）跑 —— 主仓会话本就能远程操作 worktree：" >&2
      echo "       bash scripts/close-req.sh $REQ_DIR" >&2
      echo "   · 或：这条需求先不收尾、worktree 留着继续干，等回到主仓窗口再 /close。" >&2
      exit 1
    fi
  fi

  # 模块目录在 worktree 内的相对路径（REQ_DIR 可能是主仓侧路径；统一推导 worktree 内同名模块）
  MODULE_BASENAME=$(basename "$REQ_DIR")
  REL_MODULE="docs/modules/$MODULE_BASENAME"
  WT_MODULE_META="$REQ_WORKTREE/$REL_MODULE/.req-meta.json"

  cd "$REQ_WORKTREE"

  # close-req 只允许动当前模块的 .req-meta。worktree 里漂着其他未提交改动时，
  # 直接 git add -A 会把无关代码/文档静默带进 main。
  REQ_STATUS=$(git status --porcelain --untracked-files=all 2>/dev/null || true)
  UNRELATED_DIRTY=""
  if [ -n "$REQ_STATUS" ]; then
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
    done <<< "$REQ_STATUS"
  fi
  if [ -n "$UNRELATED_DIRTY" ]; then
    echo "❌ req worktree 有当前模块目录外的未提交改动，close-req 不会静默带入 main：" >&2
    printf "%s" "$UNRELATED_DIRTY" >&2
    echo "" >&2
    echo "请先提交、移走或清理这些改动后再运行 close-req。" >&2
    exit 1
  fi

  # 记录 pre-close HEAD：如果后面 merge 失败，把 req 分支 reset 回这个点，避免半关闭状态
  PRE_CLOSE_HEAD=$(git rev-parse HEAD 2>/dev/null)
  if [ -z "$PRE_CLOSE_HEAD" ]; then
    echo "❌ 无法读取 req 分支 HEAD，中止。" >&2
    exit 1
  fi

  # Step 1: 在 req 分支删模块 .req-meta（方案 A：清工作状态层，三件套留在场）+ commit
  if [ -f "$WT_MODULE_META" ]; then
    git rm -q -- "$REL_MODULE/.req-meta.json" 2>&1 || {
      echo "❌ 在 req worktree 中删除 .req-meta.json 失败。请人工检查。" >&2
      exit 1
    }
    echo "🧹 已清模块工作状态: $REL_MODULE/.req-meta.json"
  fi

  if ! git commit -m "close: 收尾 ${REQ_ID}（清模块 .req-meta）" 2>&1; then
    echo "❌ 提交清状态改动到 req 分支失败（可能是 git 身份未配置或 hook 拒绝）。" >&2
    exit 1
  fi
  echo "✅ 清状态改动已 commit 到 $REQ_BRANCH"

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

  if ! git merge "$REQ_BRANCH" --no-edit -m "close: $REQ_ID" 2>&1; then
    # merge 失败：先 abort merge，再把 req 分支 reset 回 pre-close，避免半关闭状态
    git merge --abort 2>/dev/null || true
    if ! git -C "$REQ_WORKTREE" reset --hard "$PRE_CLOSE_HEAD" 2>&1; then
      echo "❌ merge 失败，且回滚 req 分支失败。需要人工修复: cd $REQ_WORKTREE && git reset --hard $PRE_CLOSE_HEAD" >&2
      exit 1
    fi
    echo "❌ merge ${REQ_BRANCH} → main 失败。req 分支已回滚到 ${PRE_CLOSE_HEAD}，请手动解决冲突后再运行 close-req。" >&2
    exit 1
  fi

  # 验证 merge 生效（I-CR6 ancestor 验证）
  REQ_HEAD=$(git rev-parse "$REQ_BRANCH" 2>/dev/null)
  if ! git merge-base --is-ancestor "$REQ_HEAD" HEAD 2>/dev/null; then
    git reset --hard "HEAD@{1}" 2>/dev/null || true
    git -C "$REQ_WORKTREE" reset --hard "$PRE_CLOSE_HEAD" 2>/dev/null || true
    echo "❌ merge 声称成功但 $REQ_BRANCH 的提交未进入 main。数据完整性校验失败，已回滚。" >&2
    exit 1
  fi

  echo "🔀 已合并 $REQ_BRANCH → main（已验证提交落地）"

  # Step 3: 删 req worktree + branch
  cd "$REPO_ROOT"

  if [ -d "$REQ_WORKTREE" ]; then
    git worktree remove "$REQ_WORKTREE" 2>/dev/null || {
      rm -rf "$REQ_WORKTREE"
      git worktree prune 2>/dev/null || true
    }
    echo "🗑  worktree 已删除: $REQ_WORKTREE"
  fi

  if git show-ref --verify --quiet "refs/heads/$REQ_BRANCH" 2>/dev/null; then
    git branch -D "$REQ_BRANCH" 2>/dev/null && echo "🗑  branch 已删除: $REQ_BRANCH"
  fi

else
  # ======================================================
  # 路径 B：无 worktree / 无分支 → 直接在 main 清 .req-meta + commit（不 merge）
  # ======================================================
  cd "$REPO_ROOT"

  CURRENT=$(git branch --show-current 2>/dev/null || true)
  if [ "$CURRENT" != "main" ] && [ "$CURRENT" != "master" ]; then
    echo "❌ 无 worktree 路径要求在主仓 main 上运行，当前分支: ${CURRENT:-<detached>}。" >&2
    exit 1
  fi

  # REQ_DIR 必须落在主仓内（防止传了别处的模块目录）
  MODULE_BASENAME=$(basename "$REQ_DIR")
  MAIN_MODULE="$REPO_ROOT/docs/modules/$MODULE_BASENAME"
  MAIN_MODULE_META="$MAIN_MODULE/.req-meta.json"
  if [ ! -f "$MAIN_MODULE_META" ]; then
    echo "❌ 主仓上找不到模块 .req-meta: $MAIN_MODULE_META" >&2
    echo "   （无 worktree 路径下，模块三件套 + .req-meta 必须已在 main。）" >&2
    exit 1
  fi

  REL_MODULE="docs/modules/$MODULE_BASENAME"

  # main 污染防护：只允许本模块 .req-meta 的删除参与 commit
  DIRTY=$(git status --porcelain 2>/dev/null || true)
  if [ -n "$DIRTY" ]; then
    BAD=$(printf '%s\n' "$DIRTY" | awk -v prefix="$REL_MODULE/" '
      { path = substr($0, 4); if (index(path, prefix) != 1) print $0 }
    ')
    if [ -n "$BAD" ]; then
      echo "❌ main 分支有与本模块无关的未提交改动，拒绝 close 以防污染收尾 commit：" >&2
      echo "$BAD" >&2
      echo "请先处理（commit、stash 或 reset）这些改动后再运行 close-req。" >&2
      exit 1
    fi
  fi

  git rm -q -- "$REL_MODULE/.req-meta.json" 2>&1 || {
    echo "❌ 在 main 上删除 .req-meta.json 失败。请人工检查。" >&2
    exit 1
  }
  echo "🧹 已清模块工作状态（main 直接清，无 worktree）: $REL_MODULE/.req-meta.json"

  if ! git commit -m "close: 收尾 ${REQ_ID}（清模块 .req-meta·无 worktree）" 2>&1; then
    echo "❌ 提交收尾改动到 main 失败（可能是 git 身份未配置或 hook 拒绝）。" >&2
    exit 1
  fi
  echo "✅ 收尾改动已 commit 到 main"
fi

# --- PRD 收口 symlink：让 PM 一处查所有正常 close 的 req PRD ---
# 此时已在 main（路径 A merge 后 / 路径 B 本就在 main），模块 prd.md（若有）已在场。
# 若模块没写过 prd.md（少见：未走完方案设计就 close）则 silent skip。
cd "$REPO_ROOT"
MODULE_BASENAME=$(basename "$REQ_DIR")
if ! create_prd_symlink "$REPO_ROOT" "$MODULE_BASENAME" closed; then
  echo "❌ 创建 docs/prds/ symlink 失败。" >&2
  exit 1
fi
if [ -d "$REPO_ROOT/docs/prds" ]; then
  git add -A -- "docs/prds" 2>/dev/null || true
  if [ -n "$(git diff --cached --name-only)" ]; then
    git commit -q -m "close: PRD 收口 symlink $REQ_ID" 2>/dev/null || true
  fi
fi

# --- 兜底清孤儿 worktree（按模块 .req-meta 定向；历史漏清 / 中断 close 留下的）---
cleanup_stale_worktrees "$REPO_ROOT"

echo ""
echo "✅ Req 已收尾: ${REQ_ID}（模块三件套留在 docs/modules/，工作状态 .req-meta 已清）"
echo "📍 当前位置: 主仓 main 分支"
echo ""
echo "运行 /pmai-new-req 开始下一个需求。"
