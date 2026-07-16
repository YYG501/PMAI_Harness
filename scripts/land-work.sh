#!/usr/bin/env bash
# v2 implementation landing + post-land documentation finalization.

set -euo pipefail

WORK_DIR="${1:?用法: land-work.sh <模块目录>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_lib/worktree.sh"

if [ ! -f "$WORK_DIR/.work-meta.json" ]; then
  echo "❌ 模块工作状态文件不存在: $WORK_DIR/.work-meta.json" >&2
  exit 1
fi

GIT_COMMON=$(git -C "$WORK_DIR" rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  case "$GIT_COMMON" in
    /*) REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd) ;;
    *) REPO_ROOT=$(cd "$WORK_DIR/$GIT_COMMON/.." && pwd) ;;
  esac
else
  REPO_ROOT=$(git -C "$WORK_DIR" rev-parse --show-toplevel 2>/dev/null)
fi

META_JSON=$(python3 -m json.tool "$WORK_DIR/.work-meta.json")
BUILD_JSON=$(printf '%s' "$META_JSON" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin).get("build",{}), ensure_ascii=False))')
VERSION=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("contract_version",1))')
if [ "$VERSION" -lt 2 ]; then
  echo "❌ land-work.sh 只处理 build contract v2；v1 由 close-work.sh 兼容路径处理。" >&2
  exit 1
fi

STATE=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("lifecycle_state",""))')
DOCS_STATUS=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("docs_status","pending"))')
MODE=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("mode",""))')
BRANCH=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("branch",""))')
BASELINE=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("baseline_sha","") or "")')
IMPLEMENTATION_COMMIT=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("implementation_commit","") or "")')
MODULE_NAME=$(basename "$WORK_DIR")
MAIN_MODULE="$REPO_ROOT/docs/modules/$MODULE_NAME"
IMPACT_MAP="$REPO_ROOT/.pm-workflow/audits/$MODULE_NAME/doc-impact.json"
IMPACT_MAP_REL=".pm-workflow/audits/$MODULE_NAME/doc-impact.json"

queue_pending_cleanup() {
  local worktree="$1"
  local branch="$2"
  local pending_file="$REPO_ROOT/.runs/pending-cleanup.json"
  mkdir -p "$REPO_ROOT/.runs"
  python3 - "$pending_file" "$branch" "$worktree" "$MAIN_MODULE" <<'PY'
import datetime
import json
import os
import sys

pending_file, branch, worktree, work_dir = sys.argv[1:5]
entries = []
if os.path.exists(pending_file):
    try:
        with open(pending_file, encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, list):
            entries = loaded
    except (OSError, json.JSONDecodeError):
        entries = []
entries = [entry for entry in entries if entry.get("branch") != branch]
entries.append(
    {
        "kind": "work",
        "branch": branch,
        "worktree": worktree,
        "work_dir": work_dir,
        "queued_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    }
)
with open(pending_file, "w", encoding="utf-8") as handle:
    json.dump(entries, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
}

current_main_branch() {
  local branch
  branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
  if [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
    echo "❌ 自动落地主线必须从主仓 main/master 运行，当前是 ${branch:-<detached>}。" >&2
    exit 1
  fi
}

finish_docs() {
  current_main_branch
  python3 "$SCRIPT_DIR/build-contract.py" validate-docs "$MAIN_MODULE" >/dev/null
  python3 "$SCRIPT_DIR/doc-impact.py" validate "$IMPACT_MAP" >/dev/null

  DOC_PATHS=()
  while IFS= read -r path; do
    [ -n "$path" ] && DOC_PATHS[${#DOC_PATHS[@]}]="$path"
  done < <(python3 - "$IMPACT_MAP" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for item in data.get("items", []):
    path = item.get("destination")
    if isinstance(path, str) and path:
        print(path)
PY
  )

  ALREADY_STAGED=()
  while IFS= read -r path; do
    [ -n "$path" ] && ALREADY_STAGED[${#ALREADY_STAGED[@]}]="$path"
  done < <(git -C "$REPO_ROOT" diff --cached --name-only)
  if [ "${#ALREADY_STAGED[@]}" -gt 0 ]; then
    echo "❌ main 上已有 staged 改动。自动文档提交不会把它们混进来，请先取消暂存或单独提交。" >&2
    printf '  - %s\n' "${ALREADY_STAGED[@]}" >&2
    exit 1
  fi

  for path in "${DOC_PATHS[@]}"; do
    if [ -e "$REPO_ROOT/$path" ] || git -C "$REPO_ROOT" ls-files --error-unmatch "$path" >/dev/null 2>&1; then
      git -C "$REPO_ROOT" add -A -- "$path"
    fi
  done
  git -C "$REPO_ROOT" add -A -- "$IMPACT_MAP_REL"
  git -C "$REPO_ROOT" rm -q -f -- "docs/modules/$MODULE_NAME/.work-meta.json"
  if git -C "$REPO_ROOT" diff --cached --quiet; then
    echo "❌ 没有可提交的文档变化，不能把工作伪装成 complete。" >&2
    exit 1
  fi
  PMAI_ALLOW_MIXED_DELIVERY=build-close git -C "$REPO_ROOT" commit -m "docs($MODULE_NAME): sync landed product truth"
  echo "✅ 实现已在主线，正式文档已整体对齐并单独提交。"
}

start_docs() {
  current_main_branch
  if [ ! -f "$MAIN_MODULE/.work-meta.json" ]; then
    echo "❌ main 上找不到 landed 状态: $MAIN_MODULE/.work-meta.json" >&2
    exit 1
  fi
  if [ ! -f "$IMPACT_MAP" ]; then
    python3 "$SCRIPT_DIR/doc-impact.py" init "$MAIN_MODULE" \
      --repo-root "$REPO_ROOT" \
      ${BASELINE:+--base "$BASELINE"} \
      --head HEAD \
      --output "$IMPACT_MAP" >/dev/null
  fi
  DOC_DESTINATIONS=()
  while IFS= read -r path; do
    [ -n "$path" ] && DOC_DESTINATIONS[${#DOC_DESTINATIONS[@]}]="$path"
  done < <(python3 - "$IMPACT_MAP" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1])).get("items", []):
    path = item.get("destination")
    if isinstance(path, str) and path and not path.startswith("/"):
        print(path)
PY
  )
  COLLISIONS=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path="${line:3}"
    case "$path" in
      *" -> "*) path="${path##* -> }" ;;
    esac
    for destination in "${DOC_DESTINATIONS[@]}"; do
      if [ "$path" = "$destination" ]; then
        COLLISIONS[${#COLLISIONS[@]}]="$path"
        break
      fi
    done
  done < <(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)
  if [ "${#COLLISIONS[@]}" -gt 0 ]; then
    echo "❌ 实现已经落到主线，但正式文档目标里有此前未提交的改动；为避免混入本次文档提交，先保留 landed/docs_pending。" >&2
    printf '  - %s\n' "${COLLISIONS[@]}" >&2
    echo "   处理这些已有改动后重试，只会继续文档阶段，不会重复 merge。" >&2
    exit 1
  fi
  python3 "$SCRIPT_DIR/build-contract.py" docs-start "$MAIN_MODULE" >/dev/null
  echo "✅ 实现已落到主线。继续按文档影响地图更新当前事实；完成后由同一流程提交文档。"
  echo "DOC_IMPACT_MAP=$IMPACT_MAP"
}

land_implementation() {
  python3 "$SCRIPT_DIR/build-contract.py" validate-land "$WORK_DIR" >/dev/null
  current_main_branch

  if [ "$MODE" = "worktree" ]; then
    if [ -z "$BRANCH" ] || ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      echo "❌ build 合同记录的分支不存在: ${BRANCH:-<empty>}" >&2
      exit 1
    fi
    WORKTREE=$(resolve_worktree_path "$BRANCH" "$REPO_ROOT" || true)
    if [ -z "$WORKTREE" ] || [ ! -d "$WORKTREE" ]; then
      echo "❌ build 合同记录的隔离环境不存在，不能猜成 main 直收。" >&2
      exit 1
    fi
    REL_MODULE="docs/modules/$MODULE_NAME"
    STATUS=$(git -C "$WORKTREE" status --porcelain --untracked-files=all)
    BAD=$(printf '%s\n' "$STATUS" | awk -v allowed="$REL_MODULE/.work-meta.json" '
      NF { path=substr($0,4); if (path != allowed) print $0 }
    ')
    if [ -n "$BAD" ]; then
      echo "❌ 最终实现尚有未提交改动；先完成实现提交和最终检查，不能直接 merge：" >&2
      echo "$BAD" >&2
      exit 1
    fi
    if [ -n "$STATUS" ]; then
      git -C "$WORKTREE" add -- "$REL_MODULE/.work-meta.json"
      git -C "$WORKTREE" commit -m "build($MODULE_NAME): record final acceptance"
    fi

    if ! git -C "$REPO_ROOT" merge --autostash --no-ff --no-commit "$BRANCH"; then
      git -C "$REPO_ROOT" merge --abort 2>/dev/null || true
      echo "❌ 合并发生冲突；实现和隔离环境均保留，状态仍在 final_check，解决冲突后可续跑。" >&2
      exit 1
    fi
    python3 "$SCRIPT_DIR/build-contract.py" landed "$MAIN_MODULE" \
      --landed-commit "$IMPLEMENTATION_COMMIT" >/dev/null
    git -C "$REPO_ROOT" add -- "docs/modules/$MODULE_NAME/.work-meta.json"
    PMAI_ALLOW_MIXED_DELIVERY=build-close git -C "$REPO_ROOT" commit -m "build($MODULE_NAME): land accepted implementation"
    CLEANUP_PENDING=false
    if ! git -C "$REPO_ROOT" worktree remove "$WORKTREE"; then
      CLEANUP_PENDING=true
    elif ! git -C "$REPO_ROOT" branch -d "$BRANCH" >/dev/null; then
      CLEANUP_PENDING=true
    fi
    if [ "$CLEANUP_PENDING" = "true" ]; then
      queue_pending_cleanup "$WORKTREE" "$BRANCH"
      echo "⚠️ 实现已落主线；隔离环境仍被运行进程或缓存占用，已转入安全待清理队列，不阻塞文档同步。" >&2
    fi
  elif [ "$MODE" = "main" ]; then
    python3 "$SCRIPT_DIR/build-contract.py" landed "$MAIN_MODULE" \
      --landed-commit "$IMPLEMENTATION_COMMIT" >/dev/null
  else
    echo "❌ build.mode 不合法: $MODE" >&2
    exit 1
  fi
  start_docs
}

case "$STATE:$DOCS_STATUS" in
  final_check:*) land_implementation ;;
  landed:complete|documenting:complete) finish_docs ;;
  landed:*|documenting:*) start_docs ;;
  *)
    echo "❌ 当前状态是 ${STATE:-<empty>}，还不能落地主线。先继续 build 修改或完成最终检查。" >&2
    exit 1
    ;;
esac
