#!/usr/bin/env bash
# Versioned implementation landing + post-land documentation finalization.

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
CONTRACT_JSON=$(python3 "$SCRIPT_DIR/_lib/work_contract.py" "$WORK_DIR/.work-meta.json")
VERSION=$(printf '%s' "$CONTRACT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("contract_version") or 0)')
if [ "$VERSION" -lt 2 ]; then
  echo "❌ land-work.sh 只处理 build contract v2+；v1 由 close-work.sh 兼容路径处理。" >&2
  exit 1
fi

STATE=$(printf '%s' "$CONTRACT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("lifecycle_state",""))')
DOCS_STATUS=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("docs_status","pending"))')
MODE=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("mode",""))')
BRANCH=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("branch",""))')
BASELINE=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("baseline_sha","") or "")')
IMPLEMENTATION_COMMIT=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("implementation_commit","") or "")')
SOURCE_HASH=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("approved_source_hash","") or "")')
MODULE_NAME=$(basename "$WORK_DIR")
MAIN_MODULE="$REPO_ROOT/docs/modules/$MODULE_NAME"
AUDIT_DIR_REL=$(printf '%s' "$BUILD_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("audit_dir","") or "")')
if [ -z "$AUDIT_DIR_REL" ]; then
  AUDIT_DIR_REL=".pm-workflow/audits/$MODULE_NAME"
fi
case "$AUDIT_DIR_REL" in
  /*|../*|*/../*|*/..) echo "❌ build.audit_dir 必须是仓内相对路径: $AUDIT_DIR_REL" >&2; exit 1 ;;
esac
IMPACT_MAP="$REPO_ROOT/$AUDIT_DIR_REL/doc-impact.json"
IMPACT_MAP_REL="$AUDIT_DIR_REL/doc-impact.json"
TIMING_FILE="$REPO_ROOT/$AUDIT_DIR_REL/timing.json"
TIMING_REL="$AUDIT_DIR_REL/timing.json"
CURRENT_TIMING_ID=""
CURRENT_TIMING_PHASE=""
PENDING_CLEANUP_FILE="$REPO_ROOT/.runs/pending-cleanup.json"
CLEANUP_PREPARED=false
CLEANUP_TRANSACTION_ID=""
INTEGRATION_REF=""

timing_running_id() {
  local phase="$1"
  python3 - "$TIMING_FILE" "$phase" <<'PY'
import json, os, sys
path, phase = sys.argv[1:]
if not os.path.exists(path):
    raise SystemExit(0)
data = json.load(open(path))
matches = [item for item in data.get("entries", []) if item.get("phase") == phase and item.get("status") == "running"]
if len(matches) > 1:
    raise SystemExit(f"timing 中存在多个 running {phase} 阶段，拒绝猜测恢复点。")
if matches:
    print(matches[0]["id"])
PY
}

timing_begin() {
  local phase="$1"
  local started_at="${2:-}"
  local output
  CURRENT_TIMING_PHASE="$phase"
  CURRENT_TIMING_ID=$(timing_running_id "$phase")
  if [ -z "$CURRENT_TIMING_ID" ]; then
    if [ -n "$started_at" ]; then
      output=$(python3 "$SCRIPT_DIR/build-timing.py" start \
        --audit-file "$TIMING_FILE" --phase "$phase" --kind final \
        --started-at "$started_at")
    else
      output=$(python3 "$SCRIPT_DIR/build-timing.py" start \
        --audit-file "$TIMING_FILE" --phase "$phase" --kind final)
    fi
    CURRENT_TIMING_ID=$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  fi
}

timing_finish() {
  local status="$1"
  local reason="${2:-}"
  [ -n "$CURRENT_TIMING_ID" ] || return 0
  if [ -n "$reason" ]; then
    python3 "$SCRIPT_DIR/build-timing.py" finish --audit-file "$TIMING_FILE" \
      --id "$CURRENT_TIMING_ID" --status "$status" --reason "$reason" >/dev/null
  else
    python3 "$SCRIPT_DIR/build-timing.py" finish --audit-file "$TIMING_FILE" \
      --id "$CURRENT_TIMING_ID" --status "$status" >/dev/null
  fi
  CURRENT_TIMING_ID=""
  CURRENT_TIMING_PHASE=""
}

timing_on_exit() {
  local status=$?
  if [ "$status" -ne 0 ] && [ -n "$CURRENT_TIMING_ID" ]; then
    set +e
    timing_finish fail "${CURRENT_TIMING_PHASE:-finalize} interrupted or blocked"
  fi
  exit "$status"
}

trap timing_on_exit EXIT

validate_final_timing() {
  [ "${PMAI_REQUIRE_FINAL_TIMING:-0}" = "1" ] || return 0
  local marker="$REPO_ROOT/$AUDIT_DIR_REL/finalize-run.json"
  [ -f "$marker" ] || return 0
  local required=()
  local phases_output
  if ! phases_output=$(python3 - "$marker" "$IMPLEMENTATION_COMMIT" "$SOURCE_HASH" <<'PY'
import json, sys
path, commit, source_hash = sys.argv[1:]
marker = json.load(open(path))
if marker.get("schema_version") != 1 or marker.get("runner") != "finalize-work":
    raise SystemExit("finalize timing 游标 schema 不兼容。")
if marker.get("implementation_commit") != commit or marker.get("source_hash") != source_hash:
    raise SystemExit("finalize timing 游标与当前 implementation commit/source hash 不一致。")
phases = marker.get("required_timing_phases")
if not isinstance(phases, list) or not phases:
    raise SystemExit("finalize timing 游标缺少 required_timing_phases。")
for phase in phases:
    print(phase)
PY
  ); then
    return 1
  fi
  while IFS= read -r phase; do
    [ -n "$phase" ] && required[${#required[@]}]="$phase"
  done <<< "$phases_output"
  local command=(python3 "$SCRIPT_DIR/build-timing.py" validate-finalization --audit-file "$TIMING_FILE")
  local phase
  for phase in "${required[@]}"; do
    command+=(--required-phase "$phase")
  done
  "${command[@]}" >/dev/null
}

prepare_pending_cleanup() {
  local worktree="$1"
  local branch="$2"
  mkdir -p "$REPO_ROOT/.runs"
  CLEANUP_TRANSACTION_ID=$(python3 "$SCRIPT_DIR/_lib/pending_cleanup.py" prepare \
    --file "$PENDING_CLEANUP_FILE" \
    --kind work \
    --branch "$branch" \
    --worktree "$worktree" \
    --work-dir "$MAIN_MODULE" \
    --integration-ref "$INTEGRATION_REF" \
    --activation main_meta_landed \
    --module-meta "docs/modules/$MODULE_NAME/.work-meta.json")
  CLEANUP_PREPARED=true
}

activate_pending_cleanup() {
  local branch="$1"
  if ! python3 "$SCRIPT_DIR/_lib/pending_cleanup.py" activate \
    --file "$PENDING_CLEANUP_FILE" --branch "$branch" \
    --transaction-id "$CLEANUP_TRANSACTION_ID"; then
    return 1
  fi
  CLEANUP_PREPARED=false
  CLEANUP_TRANSACTION_ID=""
}

discard_prepared_cleanup() {
  local branch="$1"
  [ "$CLEANUP_PREPARED" = true ] || return 0
  if ! python3 "$SCRIPT_DIR/_lib/pending_cleanup.py" remove \
    --file "$PENDING_CLEANUP_FILE" --branch "$branch" \
    --transaction-id "$CLEANUP_TRANSACTION_ID"; then
    return 1
  fi
  CLEANUP_PREPARED=false
  CLEANUP_TRANSACTION_ID=""
}

current_main_branch() {
  local branch
  branch=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)
  if [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
    echo "❌ 自动落地主线必须从主仓 main/master 运行，当前是 ${branch:-<detached>}。" >&2
    exit 1
  fi
  INTEGRATION_REF="refs/heads/$branch"
}

preflight_untracked_overlap() {
  local branch="$1"
  local merge_base path candidate
  local incoming_paths untracked_paths collisions

  merge_base=$(git -C "$REPO_ROOT" merge-base HEAD "$branch")
  incoming_paths=$(git -C "$REPO_ROOT" diff --name-only --diff-filter=ACMR "$merge_base" "$branch")
  untracked_paths=$(git -C "$REPO_ROOT" ls-files --others --exclude-standard)
  collisions=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if [ "$path" = "$candidate" ]; then
        collisions="${collisions}${path}"$'\n'
        break
      fi
    done <<< "$untracked_paths"
  done <<< "$incoming_paths"
  if [ -n "$collisions" ]; then
    echo "❌ merge 前发现 main 未跟踪文件会被本次实现覆盖；尚未开始 merge：" >&2
    while IFS= read -r path; do
      [ -n "$path" ] && printf '  - %s\n' "$path" >&2
    done <<< "$collisions"
    echo "   请先归位、移走或提交这些文件，再从 final_check 重试。" >&2
    return 1
  fi
}

record_landing_failure_worktree() {
  local worktree="$1"
  local started_at="$2"
  local reason="$3"
  local audit_file="$worktree/$AUDIT_DIR_REL/timing.json"
  local audit_rel="$AUDIT_DIR_REL/timing.json"
  local output entry_id
  output=$(python3 "$SCRIPT_DIR/build-timing.py" start \
    --audit-file "$audit_file" --phase landing --kind final \
    --started-at "$started_at")
  entry_id=$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  python3 "$SCRIPT_DIR/build-timing.py" finish --audit-file "$audit_file" \
    --id "$entry_id" --status fail --reason "$reason" >/dev/null
  git -C "$worktree" add -- "$audit_rel"
  PMAI_ALLOW_MIXED_DELIVERY=build-close git -C "$worktree" commit \
    -m "build($MODULE_NAME): record landing failure" -- "$audit_rel" >/dev/null
}

rollback_pending_merge() {
  local worktree="$1"
  local started_at="$2"
  local reason="$3"
  CURRENT_TIMING_ID=""
  CURRENT_TIMING_PHASE=""
  if ! git -C "$REPO_ROOT" merge --abort 2>/dev/null; then
    echo "❌ main 半合并态无法自动中止；已停止后续操作，请先人工执行 git merge --abort。" >&2
    return 1
  fi
  if ! discard_prepared_cleanup "$BRANCH"; then
    echo "❌ main 已回滚，但 prepared 清理记录未能撤销；记录不会自动激活，请人工检查队列。" >&2
    return 1
  fi
  if ! record_landing_failure_worktree "$worktree" "$started_at" "$reason"; then
    echo "❌ main 已回滚，但 landing 失败证据未能写入隔离分支；隔离环境仍保留。" >&2
    return 1
  fi
}

finish_docs() {
  current_main_branch
  timing_begin documentation
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

  timing_finish pass
  validate_final_timing
  for path in "${DOC_PATHS[@]}"; do
    if [ -e "$REPO_ROOT/$path" ] || git -C "$REPO_ROOT" ls-files --error-unmatch "$path" >/dev/null 2>&1; then
      git -C "$REPO_ROOT" add -A -- "$path"
    fi
  done
  git -C "$REPO_ROOT" add -A -- "$IMPACT_MAP_REL"
  git -C "$REPO_ROOT" add -A -- "$TIMING_REL"
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
      --head "$IMPLEMENTATION_COMMIT" \
      --output "$IMPACT_MAP" >/dev/null
  fi
  timing_begin documentation
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
  # 文档更新跨进程继续；下次恢复会复用同一个 running timing entry。
  CURRENT_TIMING_ID=""
  CURRENT_TIMING_PHASE=""
  echo "✅ 实现已落到主线。继续按文档影响地图更新当前事实；完成后由同一流程提交文档。"
  echo "DOC_IMPACT_MAP=$IMPACT_MAP"
}

land_implementation() {
  local landing_started_at
  python3 "$SCRIPT_DIR/build-contract.py" validate-land "$WORK_DIR" >/dev/null
  current_main_branch
  landing_started_at=$(python3 -c 'from datetime import datetime; print(datetime.now().astimezone().isoformat(timespec="seconds"))')

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
    if ! preflight_untracked_overlap "$BRANCH"; then
      record_landing_failure_worktree "$WORKTREE" "$landing_started_at" \
        "main untracked path collision"
      exit 1
    fi
    if [ -n "$STATUS" ]; then
      git -C "$WORKTREE" add -- "$REL_MODULE/.work-meta.json"
      if ! git -C "$WORKTREE" commit -m "build($MODULE_NAME): record final acceptance"; then
        git -C "$WORKTREE" reset -q -- "$REL_MODULE/.work-meta.json" 2>/dev/null || true
        echo "❌ 最终验收状态提交失败；状态文件已保留，可修复 hook 或 Git 配置后重试。" >&2
        exit 1
      fi
    fi

    # 最终验收提交后、merge 前先落一条 prepared 意图。后续即使进程在
    # landing commit 后中断，主仓 cleanup 也能从 Git 真相自动恢复激活。
    prepare_pending_cleanup "$WORKTREE" "$BRANCH"

    if ! git -C "$REPO_ROOT" merge --autostash --no-ff --no-commit "$BRANCH"; then
      if ! git -C "$REPO_ROOT" merge --abort 2>/dev/null; then
        echo "❌ 合并冲突且无法自动中止半合并态；隔离环境保留，请先人工执行 git merge --abort。" >&2
        exit 1
      fi
      if ! discard_prepared_cleanup "$BRANCH"; then
        echo "❌ 合并已中止，但 prepared 清理记录未能撤销；记录不会自动激活，请人工检查队列。" >&2
        exit 1
      fi
      record_landing_failure_worktree "$WORKTREE" "$landing_started_at" "merge conflict"
      echo "❌ 合并发生冲突；实现和隔离环境均保留，状态仍在 final_check，解决冲突后可续跑。" >&2
      exit 1
    fi
    if ! python3 "$SCRIPT_DIR/build-contract.py" landed "$MAIN_MODULE" \
      --landed-commit "$IMPLEMENTATION_COMMIT" >/dev/null; then
      rollback_pending_merge "$WORKTREE" "$landing_started_at" "landed state update failed" || exit 1
      echo "❌ 合并后的状态写入失败；main 已回滚，隔离环境保留，可重试。" >&2
      exit 1
    fi
    if ! timing_begin landing "$landing_started_at" || ! timing_finish pass; then
      rollback_pending_merge "$WORKTREE" "$landing_started_at" "landing timing update failed" || exit 1
      echo "❌ 落地计时写入失败；main 已回滚，隔离环境保留，可重试。" >&2
      exit 1
    fi
    if ! git -C "$REPO_ROOT" add -- "docs/modules/$MODULE_NAME/.work-meta.json" "$TIMING_REL"; then
      rollback_pending_merge "$WORKTREE" "$landing_started_at" "landing state staging failed" || exit 1
      echo "❌ 落地状态暂存失败；main 已回滚，隔离环境保留，可重试。" >&2
      exit 1
    fi
    if ! PMAI_ALLOW_MIXED_DELIVERY=build-close git -C "$REPO_ROOT" commit \
      -m "build($MODULE_NAME): land accepted implementation"; then
      rollback_pending_merge "$WORKTREE" "$landing_started_at" "landing commit failed" || exit 1
      echo "❌ 落地主线提交失败；main 已回滚，隔离环境保留，可重试。" >&2
      exit 1
    fi
    if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$BRANCH" HEAD; then
      echo "❌ 落地提交未包含 build 分支，停止清理隔离环境，请人工检查 main 历史。" >&2
      exit 1
    fi
    if ! activate_pending_cleanup "$BRANCH"; then
      echo "⚠️ 实现已落主线；清理记录仍处于 prepared，主仓 cleanup 将按 Git 状态自动恢复。" >&2
    else
      echo "🕓 实现已落主线；隔离环境已进入安全待清理队列，不阻塞文档同步。"
    fi
  elif [ "$MODE" = "main" ]; then
    python3 "$SCRIPT_DIR/build-contract.py" landed "$MAIN_MODULE" \
      --landed-commit "$IMPLEMENTATION_COMMIT" >/dev/null
    timing_begin landing "$landing_started_at"
    timing_finish pass
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
