#!/usr/bin/env bash
# migrate-reqs-to-modules.py 回归（lifecycle 迁移批 0）：
# 把 requirements/active|closed/<req>/ 迁到 docs/modules/<模块>/。
# 验：--dry-run 默认不写 / --apply 真搬 / 幂等 / 模块名派生 / 歧义区列出 / --map 指定 / 撞名检测 / 跳过附件&task。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATE="$FRAMEWORK_ROOT/scripts/migrate-reqs-to-modules.py"

echo "▶ Running test-migrate-reqs-to-modules.sh"
echo "─────────────────────────────────────────"

# 用 python 建 fixture（避免 echo >file 触发沙箱写盘提示，且 json 更可控）。
# 建：active/req-001-能力匹配卡(+brief.md+attachments/+tasks/) / closed/req-002-待办 / active/req-003(无前缀名)
_setup() {
  T=$(mktemp -d)
  python3 - "$T" <<'PY'
import json, sys
from pathlib import Path
T = Path(sys.argv[1])
def mk(path, status, name, stage=2, extra_md=False, subdirs=()):
    d = T / path
    d.mkdir(parents=True, exist_ok=True)
    (d/".req-meta.json").write_text(json.dumps(
        {"id": d.name.split("-")[0]+"-"+d.name.split("-")[1] if d.name.startswith("req-") else d.name,
         "name": name, "stage": stage, "status": status}, ensure_ascii=False), encoding="utf-8")
    if extra_md:
        (d/"brief.md").write_text("# brief", encoding="utf-8")
    for s in subdirs:
        (d/s).mkdir(exist_ok=True)
mk("requirements/active/req-001-能力匹配卡", "active", "能力匹配卡",
   extra_md=True, subdirs=("attachments", "tasks"))
mk("requirements/closed/req-002-待办", "closed", "待办", stage=4)
mk("requirements/active/req-003", "active", "")  # 无 req-NNN- 前缀且 name 空 → 歧义
(T/"docs"/"modules").mkdir(parents=True)
PY
}
_teardown() { rm -rf "$T" 2>/dev/null || true; }

test_dry_run_default_no_write() {
  start_test "migrate-modules: 默认 dry-run 不写盘（不传 --apply）"
  _setup
  local out
  out=$(python3 "$MIGRATE" "$T" 2>&1)
  if echo "$out" | grep -q "dry-run" && [ ! -e "$T/docs/modules/能力匹配卡/.req-meta.json" ]; then
    pass_test
  else
    _fail "默认应 dry-run 不写：out=$out；模块目录不该有 .req-meta.json"
  fi
  _teardown
}

test_derives_module_name() {
  start_test "migrate-modules: 从 req-NNN-<name> 派生模块名 + closed/active 都覆盖"
  _setup
  local out
  out=$(python3 "$MIGRATE" "$T" 2>&1)
  if echo "$out" | grep -q "docs/modules/能力匹配卡" && echo "$out" | grep -q "docs/modules/待办"; then
    pass_test
  else
    _fail "应派生 能力匹配卡 / 待办：out=$out"
  fi
  _teardown
}

test_apply_writes() {
  start_test "migrate-modules: --apply 真搬（.req-meta.json + *.md 落 docs/modules/）"
  _setup
  python3 "$MIGRATE" "$T" --apply >/dev/null 2>&1
  if [ -f "$T/docs/modules/能力匹配卡/.req-meta.json" ] \
     && [ -f "$T/docs/modules/能力匹配卡/brief.md" ] \
     && [ -f "$T/docs/modules/待办/.req-meta.json" ]; then
    pass_test
  else
    _fail "--apply 应把文件 copy 到 docs/modules/（实测缺文件）"
  fi
  _teardown
}

test_skips_attachments_and_tasks() {
  start_test "migrate-modules: 不搬 attachments/ 与 tasks/（留接口给后续批）"
  _setup
  python3 "$MIGRATE" "$T" --apply >/dev/null 2>&1
  if [ ! -d "$T/docs/modules/能力匹配卡/attachments" ] \
     && [ ! -d "$T/docs/modules/能力匹配卡/tasks" ]; then
    pass_test
  else
    _fail "attachments/ 与 tasks/ 不应被搬到模块目录"
  fi
  _teardown
}

test_old_path_preserved() {
  start_test "migrate-modules: 旧 requirements/ 路径保留（copy 非 move，批 2 才删）"
  _setup
  python3 "$MIGRATE" "$T" --apply >/dev/null 2>&1
  if [ -f "$T/requirements/active/req-001-能力匹配卡/.req-meta.json" ]; then
    pass_test
  else
    _fail "旧 requirements/ 路径应保留（瘦身=缩活跃集不删）"
  fi
  _teardown
}

test_idempotent() {
  start_test "migrate-modules: 幂等（再跑 --apply 跳过已落地，不重复）"
  _setup
  python3 "$MIGRATE" "$T" --apply >/dev/null 2>&1
  local out
  out=$(python3 "$MIGRATE" "$T" --apply 2>&1)
  if echo "$out" | grep -q "幂等" && echo "$out" | grep -q "跳过"; then
    pass_test
  else
    _fail "再跑应跳过已落地的 req：out=$out"
  fi
  _teardown
}

test_ambiguous_flagged() {
  start_test "migrate-modules: 无法派生模块名的 req 列入歧义区、不搬"
  _setup
  local out
  out=$(python3 "$MIGRATE" "$T" 2>&1)
  if echo "$out" | grep -q "歧义" && echo "$out" | grep -q "req-003"; then
    pass_test
  else
    _fail "req-003 应列歧义（派生不出模块名）：out=$out"
  fi
  _teardown
}

test_map_override() {
  start_test "migrate-modules: --map 显式指定模块名（绕过歧义）"
  _setup
  local out
  out=$(python3 "$MIGRATE" "$T" --map req-003=自定义模块 2>&1)
  if echo "$out" | grep -q "docs/modules/自定义模块"; then
    pass_test
  else
    _fail "--map 应让 req-003 迁到 自定义模块：out=$out"
  fi
  _teardown
}

test_collision_detected() {
  start_test "migrate-modules: 多 req 撞同一派生模块名 → 都列歧义、不搬"
  T=$(mktemp -d)
  python3 - "$T" <<'PY'
import json, sys
from pathlib import Path
T = Path(sys.argv[1])
for rid in ("req-001-x", "req-002-x"):
    d = T/"requirements"/"active"/rid
    d.mkdir(parents=True)
    (d/".req-meta.json").write_text(json.dumps({"id":rid,"name":"x","status":"active"}), encoding="utf-8")
(T/"docs"/"modules").mkdir(parents=True)
PY
  local out
  out=$(python3 "$MIGRATE" "$T" 2>&1)
  if echo "$out" | grep -q "歧义" && echo "$out" | grep -q "被多个 req 抢" \
     && [ ! -e "$T/docs/modules/x/.req-meta.json" ]; then
    pass_test
  else
    _fail "撞名应都列歧义不搬：out=$out"
  fi
  _teardown
}

test_dry_run_default_no_write
test_derives_module_name
test_apply_writes
test_skips_attachments_and_tasks
test_old_path_preserved
test_idempotent
test_ambiguous_flagged
test_map_override
test_collision_detected

report_results "migrate-reqs-to-modules"
