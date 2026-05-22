#!/usr/bin/env bash
# check-req-doc-drift.sh — 检测 task worktree 与 req 分支之间的文档 drift
#
# 用法：
#   check-req-doc-drift.sh <worktree-dir> <req-branch> <task-file>
#
# 行为：
#   1. 扫 sync 范围（项目级 DESIGN.md / CLAUDE.md + requirements/active/<req-id>/）
#   2. 对每个文件比 worktree 当前 hash vs req 分支 hash
#   3. 跳过 task own 文件 — task own 由 task 自决，永远不该被 req 推送
#      delta-3：v3 单文件只跳 task-NNN.md；v2 旧双文件兼容时多跳 .engineering.md
#   4. stdout 输出 JSON：{"drift_count": N, "files": [{"path": ..., "worktree_hash": ..., "req_hash": ...}]}
#   5. stderr 输出给人读的清单（无 drift 时一行 "✓"，有 drift 时列文件路径）
#   6. 纯只读 — 不写 worktree 任何文件，不写 .git/index.lock，不 emit 事件
#
# 4.5f 替代 sync-req-docs.sh 静默覆盖：drift 检测 + PM 看 diff + apply-req-doc 单文件应用
set -uo pipefail

if [ $# -lt 3 ]; then
  echo "用法: check-req-doc-drift.sh <worktree-dir> <req-branch> <task-file>" >&2
  exit 2
fi

WORKTREE="$1"
REQ_BRANCH="$2"
TASK_FILE="$3"

if [ ! -d "$WORKTREE" ]; then
  echo "错误：worktree 不存在: $WORKTREE" >&2
  exit 1
fi

# REQ_ID 约定 = REQ_BRANCH（跟 sync-req-docs 历史约定一致）
REQ_ID="$REQ_BRANCH"

# task own 路径（用 basename 推；约定 task 位于 requirements/active/<req-id>/tasks/）
TASK_BASENAME=$(basename "$TASK_FILE")
TASK_STEM="${TASK_BASENAME%.md}"
TASK_OWN_PM="requirements/active/${REQ_ID}/tasks/${TASK_BASENAME}"
# v2 旧双文件兼容（delta-3）：工程合同实际存在时才把它列入 task own 排除集；
# v3/v1 单文件无 .engineering.md，TASK_OWN_ENG 置空（占位匹配不会命中真实路径）。
TASK_OWN_ENG=""
if [ -f "$WORKTREE/requirements/active/${REQ_ID}/tasks/${TASK_STEM}.engineering.md" ]; then
  TASK_OWN_ENG="requirements/active/${REQ_ID}/tasks/${TASK_STEM}.engineering.md"
fi

# 收集候选路径（项目级 + req 目录 ls-tree 全集）
CANDIDATES=""
for p in DESIGN.md CLAUDE.md; do
  CANDIDATES+="${p}"$'\n'
done
REQ_PATH="requirements/active/${REQ_ID}"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  CANDIDATES+="${f}"$'\n'
done < <(git -C "$WORKTREE" ls-tree -r --name-only "$REQ_BRANCH" -- "$REQ_PATH" 2>/dev/null || true)

# 遍历比对，收集 drift（用 NUL 分隔字段、newline 分隔记录便于 python 解析）
DRIFT_RECORDS=""
while IFS= read -r path; do
  [ -z "$path" ] && continue
  # skip task own（v3 单文件只跳 .md；v2 兼容时 TASK_OWN_ENG 非空才多跳工程合同）
  if [ "$path" = "$TASK_OWN_PM" ]; then
    continue
  fi
  if [ -n "$TASK_OWN_ENG" ] && [ "$path" = "$TASK_OWN_ENG" ]; then
    continue
  fi
  # req 分支侧 hash（不存在 → MISSING）
  if git -C "$WORKTREE" cat-file -e "${REQ_BRANCH}:${path}" 2>/dev/null; then
    req_hash=$(git -C "$WORKTREE" rev-parse "${REQ_BRANCH}:${path}")
  else
    req_hash="MISSING"
  fi
  # worktree 侧 hash（不存在 → MISSING；存在 → git hash-object 对齐 git 算法）
  if [ -f "$WORKTREE/$path" ]; then
    wt_hash=$(git -C "$WORKTREE" hash-object "$path" 2>/dev/null || echo "MISSING")
  else
    wt_hash="MISSING"
  fi
  if [ "$req_hash" != "$wt_hash" ]; then
    DRIFT_RECORDS+="${path}"$'\t'"${wt_hash}"$'\t'"${req_hash}"$'\n'
  fi
done <<< "$CANDIDATES"

# stdout JSON（python 渲染，避免手拼 JSON 转义坑）
python3 - <<PY
import json, sys
records = """$DRIFT_RECORDS"""
files = []
for line in records.splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        continue
    files.append({"path": parts[0], "worktree_hash": parts[1], "req_hash": parts[2]})
print(json.dumps({"drift_count": len(files), "files": files}))
PY

# stderr 给人读的摘要
# `grep -c` 没匹配时 exit=1 会触发 `|| echo 0` 多输出一行 → DRIFT_COUNT 变 "0\n0"
# 走 if/else 直接判断 records 是否为空，避开陷阱
if [ -z "$DRIFT_RECORDS" ]; then
  echo "✓ check-req-doc-drift: 无 drift（worktree 与 ${REQ_BRANCH} 一致）" >&2
else
  DRIFT_COUNT=$(printf "%s" "$DRIFT_RECORDS" | grep -c '^')
  echo "⚠ check-req-doc-drift: ${DRIFT_COUNT} 个文件在 ${REQ_BRANCH} 上变了：" >&2
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    p=$(echo "$line" | cut -f1)
    echo "  - ${p}" >&2
  done <<< "$DRIFT_RECORDS"
fi
