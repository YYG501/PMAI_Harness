#!/usr/bin/env bash
# test-state-lib.sh
#
# 包装 scripts/_lib/state_test.py 进 bash test suite，
# 让 _lib/state.py 的单元覆盖也进 run-all 绿网（此前只在 python -m unittest 手动跑、CI 扫不到）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

start_test "_lib/state.py 单元测试（state_test.py）"

if PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 -m unittest _lib.state_test > /tmp/state_lib_test.out 2>&1; then
  pass_test "_lib/state.py 单元测试（state_test.py）"
else
  _fail "_lib/state.py 单元测试失败"
  cat /tmp/state_lib_test.out >&2
fi

start_test "work contract normalization 单元测试"
if PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 -m unittest _lib.work_contract_test > /tmp/work_contract_test.out 2>&1; then
  pass_test "work contract normalization 单元测试"
else
  _fail "work contract normalization 单元测试失败"
  cat /tmp/work_contract_test.out >&2
fi

start_test "skill-preamble prefers the owning build worktree over stale main state"
t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-preamble-state.XXXXXX")
t_real=$(cd "$t" && pwd -P)
git -C "$t" init -q -b main
git -C "$t" config user.email "test@example.com"
git -C "$t" config user.name "PMAI Test"
mkdir -p "$t/docs/modules/access"
cat > "$t/docs/modules/access/.work-meta.json" <<'JSON'
{"id":"work-access","name":"access","branch":"build-work-access","stage":1,"status":"active","lifecycle_state":"ready_to_build"}
JSON
printf '# PMAI project\n' > "$t/PRODUCT.md"
git -C "$t" add -A
git -C "$t" commit -q -m "ready on main"
git -C "$t" worktree add -q -b build-work-access "$t/build-work-access"
python3 - "$t/build-work-access/docs/modules/access/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
meta = json.load(open(path))
meta["branch"] = "build-stale-branch"
meta["build"] = {"branch": "build-work-access"}
meta["stage"] = 2
meta["lifecycle_state"] = "iterating"
json.dump(meta, open(path, "w"))
PY
out=$(cd "$t" && PMAI_HOME="$FRAMEWORK_ROOT" bash -c 'source "$PMAI_HOME/scripts/skill-preamble.sh" >/dev/null; printf "%s|%s|%s\n" "$ACTIVE_WORK" "$ACTIVE_WORK_STAGE" "$ACTIVE_WORK_DIR"')
if [ "$out" = "work-access|2|$t_real/build-work-access/docs/modules/access" ]; then
  pass_test
else
  _fail "preamble selected stale state: $out"
fi
git -C "$t" worktree remove --force "$t/build-work-access" >/dev/null 2>&1 || true
rm -rf "$t"

start_test "skill-preamble suppresses stale main active after worktree completion"
t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-preamble-closed.XXXXXX")
git -C "$t" init -q -b main
git -C "$t" config user.email "test@example.com"
git -C "$t" config user.name "PMAI Test"
mkdir -p "$t/docs/modules/access"
cat > "$t/docs/modules/access/.work-meta.json" <<'JSON'
{"id":"work-access","name":"access","branch":"build-work-access","stage":1,"status":"active","lifecycle_state":"ready_to_build"}
JSON
printf '# PMAI project\n' > "$t/PRODUCT.md"
git -C "$t" add -A
git -C "$t" commit -q -m "ready on main"
git -C "$t" worktree add -q -b build-work-access "$t/build-work-access"
python3 - "$t/build-work-access/docs/modules/access/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
meta = json.load(open(path))
meta["status"] = "closed"
meta["lifecycle_state"] = "complete"
json.dump(meta, open(path, "w"))
PY
out=$(cd "$t" && PMAI_HOME="$FRAMEWORK_ROOT" bash -c 'source "$PMAI_HOME/scripts/skill-preamble.sh" >/dev/null; printf "%s|%s\n" "$ACTIVE_WORK_COUNT" "$ACTIVE_WORK"')
if [ "$out" = "0|" ]; then
  pass_test
else
  _fail "preamble revived stale main state after completion: $out"
fi
git -C "$t" worktree remove --force "$t/build-work-access" >/dev/null 2>&1 || true
rm -rf "$t"

report_results "state-lib"
exit $((FAIL_COUNT > 0 ? 1 : 0))
