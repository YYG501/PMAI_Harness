#!/usr/bin/env bash
# close-task.sh — Task 关闭：文档偏差检查 → 归档 → merge → 清理
# 用法: bash $HOME/.pmai/scripts/close-task.sh <task-file>
# 前置条件：task 状态必须为「已完成」

set -euo pipefail

TASK_FILE="${1:?用法: close-task.sh <task-file>}"

# --- 找到真正的主仓根目录（不是 worktree） ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

# 找自身脚本目录（I-mini：framework scripts/ 互相调用走 SCRIPT_DIR，不假设消费仓有 $HOME/.pmai/scripts/）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENTS_SCRIPT="$SCRIPT_DIR/task-events.py"

# 加载 worktree 解析 helper
source "$SCRIPT_DIR/_lib/worktree.sh"
source "$SCRIPT_DIR/_lib/dev-server.sh"

if [ ! -f "$TASK_FILE" ]; then
  echo "❌ task 文件不存在: $TASK_FILE" >&2
  exit 1
fi

# --- 提取 task 元信息字段（兼容旧段落格式 + 新任务卡表格格式） ---
extract_task_field() {
  local file="$1"
  local field="$2"
  local val
  # 旧格式：**字段：** 值
  val=$(grep -m1 "^\*\*${field}：\*\*" "$file" 2>/dev/null \
    | sed -E "s/^\*\*${field}：\*\* +//; s/[ 	]+$//" || true)
  if [ -n "$val" ]; then
    echo "$val"
    return 0
  fi
  # 新格式：| **字段** | 值 |
  val=$(grep -m1 "^|[ 	]*\*\*${field}\*\*[ 	]*|" "$file" 2>/dev/null \
    | sed -E "s/^\|[ 	]*\*\*${field}\*\*[ 	]*\|[ 	]*//; s/[ 	]*\|[ 	]*$//; s/[ 	]+$//" || true)
  echo "$val"
}

# --- task 格式判别（三态：v1/v2/v3） ---
ENG_FILE="${TASK_FILE%.md}.engineering.md"
TASK_FMT=$(python3 "$SCRIPT_DIR/_lib/state.py" detect_format "$TASK_FILE" 2>/dev/null || echo "v3")
if [ "$TASK_FMT" = "v2" ]; then
  HAS_ENG=true
  echo "ℹ️  检测到旧格式 task（双文件），兼容模式继续。" >&2
else
  HAS_ENG=false
  # v3 单文件 typed contract / v1 老单文件 —— 无 .engineering.md 是正常，不报告警。
fi

# --- 校验状态 ---
STATUS=$(extract_task_field "$TASK_FILE" "状态")
if [ "$STATUS" != "已完成" ]; then
  echo "❌ task 状态为「${STATUS}」，不是「已完成」。只有 PM 确认通过后才能关闭。" >&2
  exit 1
fi

# --- 偏差记录留作 close-req 聚合输入 ---
# 不在 close-task 阶段调 /doc-update（避免 N 次启动成本累加，§0.1 痛点）。
# 偏差原样保留在 task 文件，由 close-req 步骤 1.5 聚合处理。
# .md §0.1 + §1 + §3 。
# 历史 collect_diff_section helper + DOC_DIFF 阻塞 block 已删。

# --- 提取分支名 ---
BRANCH=$(extract_task_field "$TASK_FILE" "分支" | sed 's/[ 	].*//')
if [ -z "$BRANCH" ]; then
  echo "⚠️ task 文件中未找到分支名，跳过分支操作。" >&2
fi

TASK_STEM=$(basename "$TASK_FILE" .md)
TASK_TITLE=$(head -1 "$TASK_FILE" | sed 's/^# //')

# --- 确定 req 目录和 req 分支 ---
REQ_DIR=$(echo "$TASK_FILE" | sed 's|/tasks/.*||')
REQ_META="$REQ_DIR/.req-meta.json"
REQ_BRANCH=""
if [ -f "$REQ_META" ]; then
  REQ_BRANCH=$(python3 -c "import json; print(json.load(open('$REQ_META'))['branch'])" 2>/dev/null || true)
fi

# --- 1. 归档推迟到 merge 后，在 req worktree 中做并 commit ---
# （归档必须 commit 到 req 分支，否则在 close-req 清理 worktree 时会丢失）

RUNS_FILE="$REPO_ROOT/.runs/$TASK_STEM.json"
EVENTS_FILE="$REPO_ROOT/.runs/events/$TASK_STEM.jsonl"

# --- 2. 合并 task 分支到 req 分支 ---
# 规则：merge 必须成功才清理。任何前置条件缺失都 exit 1，防止未合并就删除分支（数据丢失）
MERGE_OK=false

if [ -z "$BRANCH" ]; then
  echo "❌ task 文件中未找到分支名，无法安全清理。请检查 task 文件的「分支」字段。" >&2
  exit 1
fi

if ! git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
  echo "❌ task 分支 $BRANCH 不存在。可能已被手动删除。人工检查后再处理。" >&2
  exit 1
fi

if [ -z "$REQ_BRANCH" ]; then
  echo "❌ req 元数据缺失 branch 字段 ($REQ_META)。人工检查后再处理。" >&2
  exit 1
fi

REQ_WORKTREE=$(resolve_worktree_path "$REQ_BRANCH" "$REPO_ROOT" || true)
if [ -z "$REQ_WORKTREE" ] || [ ! -d "$REQ_WORKTREE" ]; then
  echo "❌ req worktree 不存在（git worktree list 中找不到分支 ${REQ_BRANCH}）。需要先恢复 req worktree 才能关闭 task。" >&2
  echo "   建议：bash \$HOME/.pmai/scripts/create-req-worktree.sh ${REQ_BRANCH}" >&2
  exit 1
fi

# --- Phase 2 cwd 校验：本脚本只服务 close-task Phase 2（merge + 删 task worktree/branch） ---
# 必须在 req worktree 内跑：删 task worktree 不能"删自己脚下"。
# Phase 1（对齐 / 偏差 / commit / 写 marker）在 task 窗口由 skill 步骤直接执行，不调本脚本。
CALLER_PWD="$(pwd -P 2>/dev/null || echo "")"
REQ_WT_REAL="$(cd "$REQ_WORKTREE" && pwd -P)"
if [ "$CALLER_PWD" != "$REQ_WT_REAL" ] && [[ "$CALLER_PWD" != "$REQ_WT_REAL"/* ]]; then
  echo "❌ close-task Phase 2 必须在 req worktree cwd 内运行。" >&2
  echo "   当前 cwd: $CALLER_PWD" >&2
  echo "   期望:     $REQ_WT_REAL" >&2
  echo "   提示：close-task 是两阶段调用——Phase 1 在 task 窗口（对齐/偏差/commit/写 marker），完成后切到 req 窗口跑 /close-task 进 Phase 2（merge + 清理）。" >&2
  exit 1
fi

# --- 检查 task worktree 是否 clean（防止 worktree remove --force 静默丢失未提交改动） ---
# docs/DESIGN.md + docs/PRODUCT-RULES.md 例外：close-task skill §1.5 / §1.6 沉淀视觉规范 /
# 跨功能产品规则反馈到这两份文件时不 commit（PM 在 req 窗口审 diff 再 commit）。
# 若 task worktree 里它们真有 uncommitted（AI patch 走错 worktree 的容错）→
# 先把改动 carry 到 req worktree（保留 PM 在 req 审 diff 的语义），再做 clean 检查。
#  ：PRODUCT-RULES.md 与 DESIGN.md 同一处理（同类 bug 防回归）。
CARRY_FORWARD_FILES="docs/DESIGN.md docs/PRODUCT-RULES.md"
TASK_WORKTREE=$(resolve_worktree_path "$BRANCH" "$REPO_ROOT" || true)
if [ -n "$TASK_WORKTREE" ] && [ -d "$TASK_WORKTREE" ]; then
  for cf in $CARRY_FORWARD_FILES; do
    if [ -f "$TASK_WORKTREE/$cf" ]; then
      CF_STATUS=$(git -C "$TASK_WORKTREE" status --porcelain "$cf" 2>/dev/null || true)
      if [ -n "$CF_STATUS" ]; then
        mkdir -p "$REQ_WORKTREE/$(dirname "$cf")"
        cp "$TASK_WORKTREE/$cf" "$REQ_WORKTREE/$cf"
        echo "📋 task worktree 中 $cf uncommitted，已 carry 到 req worktree（防 rm -rf 丢失；PM 在 req 窗口审 diff + commit）"
      fi
    fi
  done
  UNCOMMITTED=$(git -C "$TASK_WORKTREE" status --porcelain 2>/dev/null | grep -vE 'docs/(DESIGN|PRODUCT-RULES)\.md' || true)
  if [ -n "$UNCOMMITTED" ]; then
    echo "❌ task worktree 有未提交改动（不含 docs/DESIGN.md / docs/PRODUCT-RULES.md），不能关闭（worktree remove --force 会丢失数据）：" >&2
    echo "$UNCOMMITTED" >&2
    echo "" >&2
    echo "请先在 task worktree 中提交：" >&2
    echo "  cd $TASK_WORKTREE" >&2
    echo "  git add -A && git commit -m \"wip: <描述>\"" >&2
    echo "然后重新运行 /close-task。" >&2
    exit 1
  fi

  # 检查 task 分支是否有未推到 req 分支的提交（确保 merge 能带走所有提交）
  UNMERGED_COMMITS=$(git -C "$TASK_WORKTREE" log "$REQ_BRANCH..$BRANCH" --oneline 2>/dev/null || true)
  if [ -z "$UNMERGED_COMMITS" ]; then
    # task 分支和 req 分支完全一致，没有新提交。允许继续（可能是空 task 或已手动 merge）
    :
  fi
fi

# --- 检查 req worktree 是否 clean（有未提交改动会导致 merge 被 git 拒绝） ---
# docs/DESIGN.md 例外：close-task skill §P2.4 明确"DESIGN.md uncommitted 等 PM 在 req 窗口审 diff + commit"，
# 也是上面 carry 步骤的落点。merge 不会动 DESIGN.md（task 分支不 commit 它），working tree dirty 不阻塞 merge。
REQ_UNCOMMITTED=$(git -C "$REQ_WORKTREE" status --porcelain 2>/dev/null | grep -vE 'docs/(DESIGN|PRODUCT-RULES)\.md' || true)
if [ -n "$REQ_UNCOMMITTED" ]; then
  echo "❌ req worktree ($REQ_BRANCH) 有未提交改动（不含 docs/DESIGN.md / docs/PRODUCT-RULES.md），git 会拒绝 merge：" >&2
  echo "$REQ_UNCOMMITTED" >&2
  echo "" >&2
  echo "请先在 req worktree 中提交：" >&2
  echo "  cd $REQ_WORKTREE" >&2
  echo "  git add -A && git commit -m \"chore: <描述>\"" >&2
  echo "然后重新运行 /close-task。" >&2
  exit 1
fi

# --- I-CT7 / I-CT8: 事件流与 commit 时间戳审计（merge 前强拦） ---
AUDIT_SCRIPT="$SCRIPT_DIR/audit-task-events.py"
if [ -f "$AUDIT_SCRIPT" ]; then
  if ! python3 "$AUDIT_SCRIPT" \
      --task-file "$TASK_FILE" \
      --task-branch "$BRANCH" \
      --req-branch "$REQ_BRANCH"; then
    # audit-task-events.py 已打印违规详情，直接退出
    exit 1
  fi
else
  echo "⚠️ 找不到事件流审计脚本 ${AUDIT_SCRIPT}，跳过 I-CT7/I-CT8 校验。" >&2
fi

# --- v4.5：防 task md modify/delete 冲突 ---
# req 分支在 task-confirm 时删了 task md（task 分支独家所有），但 task 分支还在改它。
# merge 时 git 报 modify/delete 冲突。先把 task md 从 task 分支 checkout 出来 + add，
# 让 req 分支"先认回"它，merge 时 task 分支再 merge 进来就无冲突。
cd "$REQ_WORKTREE"
# 相对路径 = 从 task worktree 根剥前缀（worktree 共享同 repo，path 相对仓根有效）。
# TASK_WORKTREE 已由 git worktree list 解析，不假设物理位置。
_strip_wt_prefix() {
  local abs="$1" wt="$2"
  if [ -n "$wt" ] && [[ "$abs" == "$wt"/* ]]; then
    printf '%s\n' "${abs#${wt}/}"
  else
    # fallback：保留旧 sed 兼容（task worktree 解析失败 / 路径形如 .worktrees/<branch>/...）
    echo "$abs" | sed -E "s|^.*\.worktrees/[^/]+/||"
  fi
}
TASK_FILE_REL=$(_strip_wt_prefix "$TASK_FILE" "$TASK_WORKTREE")
ENG_FILE_REL=$(_strip_wt_prefix "$ENG_FILE" "$TASK_WORKTREE")
# 仅当 req 分支当前不存在该路径时才"认回"（v4.5 fork 时已删；旧格式未删时跳过）
RECLAIMED=()
if ! git ls-files --error-unmatch "$TASK_FILE_REL" >/dev/null 2>&1; then
  if git show "$BRANCH:$TASK_FILE_REL" >/dev/null 2>&1; then
    git checkout "$BRANCH" -- "$TASK_FILE_REL" 2>/dev/null && RECLAIMED+=("$TASK_FILE_REL")
  fi
fi
if [ "$HAS_ENG" = "true" ] && ! git ls-files --error-unmatch "$ENG_FILE_REL" >/dev/null 2>&1; then
  if git show "$BRANCH:$ENG_FILE_REL" >/dev/null 2>&1; then
    git checkout "$BRANCH" -- "$ENG_FILE_REL" 2>/dev/null && RECLAIMED+=("$ENG_FILE_REL")
  fi
fi
if [ ${#RECLAIMED[@]} -gt 0 ]; then
  git add "${RECLAIMED[@]}"
  git commit -q -m "close-prep: reclaim task md from $BRANCH (v4.5 merge prep)"
fi

# 执行 merge
if ! git merge "$BRANCH" --no-edit -m "close: $TASK_TITLE" 2>&1; then
  echo "❌ merge $BRANCH → $REQ_BRANCH 失败。请手动解决冲突后再运行 close-task。" >&2
  exit 1
fi

# 验证 merge 生效：req 分支的 HEAD 必须包含 task 分支的所有提交
TASK_HEAD=$(git -C "$REPO_ROOT" rev-parse "$BRANCH" 2>/dev/null)
if ! git merge-base --is-ancestor "$TASK_HEAD" HEAD 2>/dev/null; then
  echo "❌ merge 声称成功但 ${BRANCH} 的提交未进入 ${REQ_BRANCH}。数据完整性校验失败。" >&2
  exit 1
fi

MERGE_OK=true
echo "🔀 已合并 ${BRANCH} → ${REQ_BRANCH}（已验证提交落地）"

# --- ：promote task 「文档偏差」→ req adjustment 事件 ---
# Phase 2 在 req worktree：merge 后 task 文件已在 req 分支，读其文档偏差段、
# 逐行 append 成 req-events.jsonl 的 adjustment 事件（close-req 反向对齐读它）。
# 格式判别复用  detect_format 三态（v2 在 .engineering.md §10、v3 在审计区）。
REQ_EVENTS_SCRIPT="$SCRIPT_DIR/req-events.py"
REQ_BASENAME_FOR_EVENTS=$(basename "$REQ_DIR")
REQ_DIR_IN_WT="$REQ_WORKTREE/requirements/active/$REQ_BASENAME_FOR_EVENTS"
MERGED_TASK_FILE="$REQ_WORKTREE/$TASK_FILE_REL"
if [ -f "$REQ_EVENTS_SCRIPT" ] && [ -d "$REQ_DIR_IN_WT" ] && [ -f "$MERGED_TASK_FILE" ]; then
  python3 - "$MERGED_TASK_FILE" "$REQ_WORKTREE/$ENG_FILE_REL" "$REQ_DIR_IN_WT" "$TASK_STEM" "$REQ_EVENTS_SCRIPT" <<'PY' || true
import sys, subprocess, re
from pathlib import Path

task_file, eng_path_s, req_dir, task_stem, script = sys.argv[1:6]
eng_path = Path(eng_path_s)

# detect_format 三态：v2 = .engineering.md 存在 → 偏差在 §10；否则在 task 文件审计区
if eng_path.exists():
    src = eng_path.read_text(encoding="utf-8")
    m = re.search(r'^##\s+(?:10\.\s+)?文档偏差\s*$', src, re.M)
else:
    src = Path(task_file).read_text(encoding="utf-8")
    m = re.search(r'^##\s+📋?\s*文档偏差\s*$', src, re.M)
if not m:
    sys.exit(0)

start = m.end()
nm = re.search(r'^##\s+', src[start:], re.M)
section = src[start: start + nm.start()] if nm else src[start:]

rows = []
for line in section.splitlines():
    line = line.strip()
    if not line.startswith('|'):
        continue
    rows.append([c.strip() for c in line.strip('|').split('|')])

# 去表头 + 分隔行；保留 ≥3 列的数据行
data = [
    r for r in rows
    if len(r) >= 3
    and not all(set(c) <= set('-: ') for c in r if c)
    and '文档位置' not in r[0]
]
tm = re.match(r'(task-\d+)', task_stem)
task_id = tm.group(1) if tm else task_stem

n = 0
for r in data:
    loc = r[0]
    if not loc or loc in ('无', '-'):
        continue
    before = r[1] if len(r) > 1 else ''
    after = r[2] if len(r) > 2 else ''
    reason = r[3] if len(r) > 3 else ''
    subprocess.run(
        ['python3', script, 'append', req_dir, '--type', 'adjustment',
         '--source', 'close-task@6', '--from-task', task_id,
         '--prd-anchor', loc, '--before', before, '--after', after,
         '--reason', reason],
        check=False,
    )
    n += 1
print(f"  promoted {n} adjustment event(s)", file=sys.stderr)
PY
  REQ_EVENTS_REL="requirements/active/$REQ_BASENAME_FOR_EVENTS/req-events.jsonl"
  if [ -n "$(git -C "$REQ_WORKTREE" status --porcelain "$REQ_EVENTS_REL" 2>/dev/null)" ]; then
    git -C "$REQ_WORKTREE" add "$REQ_EVENTS_REL"
    git -C "$REQ_WORKTREE" commit -q -m "req-events: promote $TASK_STEM 文档偏差 → adjustment"
    echo "📝 已 promote $TASK_STEM 文档偏差 → req adjustment 事件"
  fi
fi

# --- 2.5. 在 req worktree 中归档 .runs/ 并 commit 到 req 分支 ---
# 必须 commit，否则 close-req 清理 worktree 时归档文件会丢失
# 归档路径：req worktree 里的 requirements/active/<req>/tasks/_archived/<task>/
REQ_BASENAME=$(basename "$REQ_DIR")
ARCHIVE_DIR_IN_WORKTREE="$REQ_WORKTREE/requirements/active/$REQ_BASENAME/tasks/_archived/$TASK_STEM"
mkdir -p "$ARCHIVE_DIR_IN_WORKTREE"

ARCHIVED_FILES=()
if [ -f "$RUNS_FILE" ]; then
  cp "$RUNS_FILE" "$ARCHIVE_DIR_IN_WORKTREE/"
  ARCHIVED_FILES+=("$ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.json")
  echo "📦 归档 runtime: $ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.json"
fi
if [ -f "$EVENTS_FILE" ]; then
  cp "$EVENTS_FILE" "$ARCHIVE_DIR_IN_WORKTREE/"
  ARCHIVED_FILES+=("$ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.jsonl")
  echo "📦 归档事件流: $ARCHIVE_DIR_IN_WORKTREE/$TASK_STEM.jsonl"
fi

if [ ${#ARCHIVED_FILES[@]} -gt 0 ]; then
  # 在 req worktree 里 commit 归档文件
  cd "$REQ_WORKTREE"
  git add "requirements/active/$REQ_BASENAME/tasks/_archived/$TASK_STEM/" 2>/dev/null
  if ! git commit -m "archive: runtime for $TASK_STEM" 2>&1; then
    echo "❌ 归档文件提交失败。为防止数据丢失，保留 .runs/ 原件，请手动检查。" >&2
    exit 1
  fi
  echo "✅ 归档已 commit 到 $REQ_BRANCH"
fi

# --- 2.6. 杀 dev server（按进程 cwd 校验归属后才 kill） ---
DEV_SERVER=$(extract_task_field "$TASK_FILE" "开发服务器")
if [ -z "$DEV_SERVER" ]; then
  DEV_SERVER=$(extract_task_field "$TASK_FILE" "dev server")
fi
PORT=$(echo "$DEV_SERVER" | grep -oE '[0-9]+' | tail -1 || true)
if [ -n "$PORT" ] && [ "$PORT" -gt 0 ] 2>/dev/null; then
  stop_dev_server_port "$PORT" "$TASK_WORKTREE" "$REQ_WORKTREE"
fi

# --- 3. 直接删 task worktree + branch（v4.5：cwd 在 req worktree，不删自己脚下） ---
if [ "$MERGE_OK" = "true" ]; then
  if [ -d "$TASK_WORKTREE" ]; then
    if git -C "$REPO_ROOT" worktree remove "$TASK_WORKTREE" 2>/dev/null; then
      echo "🧹 已删 task worktree: $TASK_WORKTREE"
    else
      # 回退：rm -rf + worktree prune
      rm -rf "$TASK_WORKTREE"
      git -C "$REPO_ROOT" worktree prune 2>/dev/null || true
      echo "🧹 已强制清理 task worktree: $TASK_WORKTREE"
    fi
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    if git -C "$REPO_ROOT" branch -D "$BRANCH" >/dev/null 2>&1; then
      echo "🧹 已删 task branch: $BRANCH"
    else
      echo "❌ 删 task branch $BRANCH 失败。请人工检查。" >&2
      exit 1
    fi
  fi
fi

# --- 6. 清理 .runs/ 原件 ---
[ -f "$RUNS_FILE" ] && rm -f "$RUNS_FILE"
[ -f "$EVENTS_FILE" ] && rm -f "$EVENTS_FILE"

# --- 6.5. 清 verify 目录运行时元数据（PID/PORT 文件，task close 后无意义）---
# 不动审计资产（report.md / flow-*.png / _plan.md）；只清纯运行时副产物。
# 在 main 仓和 req worktree 两处都扫（不同阶段 task-verify 可能写不同 cwd）。
for _vdir in "$REPO_ROOT/.pm-workflow/tasks/$TASK_STEM/verify" \
             "$REQ_WORKTREE/.pm-workflow/tasks/$TASK_STEM/verify"; do
  [ -d "$_vdir" ] || continue
  rm -f "$_vdir/dev-server.info" "$_vdir/_dev-server.log" 2>/dev/null || true
done

# --- 7. 追加关闭事件 ---
if [ -f "$EVENTS_SCRIPT" ]; then
  python3 "$EVENTS_SCRIPT" append "$TASK_FILE" --type task_closed 2>/dev/null || true
fi

echo "✅ Task 已关闭: $TASK_TITLE"
