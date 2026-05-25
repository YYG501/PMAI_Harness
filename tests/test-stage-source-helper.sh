#!/usr/bin/env bash
# D-i v4 vp-6：stage 2 真相源 helper + path-contract 回归。
# 覆盖：
#   ① get_stage_source 4 case（meta 有 / 缺 / 旧 req fallback / KeyError 防御）
#   ② set_stage_source 3 case（新写 / append origin / 旧 meta 兼容写）
#   ⑤+⑥ 静态 grep：SKILL.md / templates 不再硬编码 analysis.md（关键 hook 点）
#   ⑦ new-req 砍选项 1：grep 删除痕迹
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

# -----------------------------------------------------------------
# ① get_stage_source 4 case
# -----------------------------------------------------------------

test_get_stage_source_meta_override() {
  start_test "get_stage_source: meta.stage2_source override B 分支文件名"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 1)
  python3 - "$req_dir" <<'PY' >/tmp/out.$$ 2>/tmp/err.$$
import json, sys
from pathlib import Path
sys.path.insert(0, "%s/scripts" % "$FRAMEWORK_ROOT")
PY
  # 改用真正运行 helper（FRAMEWORK_ROOT 不能在 heredoc 内插）
  python3 -c "
import json, sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import get_stage_source
rd = Path('$req_dir')
# 写 meta override
mf = rd / '.req-meta.json'
meta = json.loads(mf.read_text(encoding='utf-8'))
meta['stage2_source'] = 'stage2-office-hours.md'
mf.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
p = get_stage_source(rd, 2)
assert p == rd / 'stage2-office-hours.md', f'expected office-hours got {p}'
print('OK')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "OK" /tmp/out.$$; then
    pass_test
  else
    _fail "get_stage_source override 未生效"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_get_stage_source_fallback_no_field() {
  start_test "get_stage_source: meta 无 stage2_source → fallback analysis.md"
  fixture_setup
  req_dir=$(fixture_create_req "req-002" "test" 2)
  python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import get_stage_source
rd = Path('$req_dir')
p = get_stage_source(rd, 2)
assert p == rd / 'analysis.md', f'expected analysis.md got {p}'
print('OK')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "OK" /tmp/out.$$; then
    pass_test
  else
    _fail "get_stage_source fallback 未生效"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_get_stage_source_legacy_no_meta_file() {
  start_test "get_stage_source: 旧 req .req-meta.json 不存在 → fallback 默认产物"
  fixture_setup
  req_dir=$(fixture_create_req "req-003" "test" 1)
  rm "$req_dir/.req-meta.json"
  python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import get_stage_source
p = get_stage_source(Path('$req_dir'), 2)
# strict=False 路径，meta=None → 落到 STAGE_OUTPUT_FILES[2] = 'analysis.md'
assert p == Path('$req_dir') / 'analysis.md', f'expected analysis.md got {p}'
print('OK')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "OK" /tmp/out.$$; then
    pass_test
  else
    _fail "旧 req 兼容失败"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_get_stage_source_keyerror_unknown_stage() {
  start_test "get_stage_source: stage 4 不在 STAGE_OUTPUT_FILES → KeyError 契约"
  fixture_setup
  req_dir=$(fixture_create_req "req-004" "test" 1)
  python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import get_stage_source
rd = Path('$req_dir')
try:
    get_stage_source(rd, 4)
except KeyError:
    print('OK')
else:
    print('FAIL: should raise KeyError for stage 4')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "^OK$" /tmp/out.$$; then
    pass_test
  else
    _fail "KeyError 契约未触发"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# ② set_stage_source 3 case
# -----------------------------------------------------------------

test_set_stage_source_A_branch() {
  start_test "set_stage_source: A 分支写 analysis.md + tool 字段"
  fixture_setup
  req_dir=$(fixture_create_req "req-005" "test" 1)
  python3 -c "
import json, sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import set_stage_source
rd = Path('$req_dir')
set_stage_source(rd, 2, 'analysis.md', tool='req-analysis')
meta = json.loads((rd / '.req-meta.json').read_text())
assert meta['stage2_source'] == 'analysis.md', meta
assert meta['stage2_tool'] == 'req-analysis', meta
assert 'stage2_source_origin' not in meta, 'A 分支不应有 origin'
print('OK')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "OK" /tmp/out.$$; then
    pass_test
  else
    _fail "A 分支写入失败"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_set_stage_source_B_branch_with_origin() {
  start_test "set_stage_source: B 分支写 stage2-office-hours.md + origin 追溯字段"
  fixture_setup
  req_dir=$(fixture_create_req "req-006" "test" 1)
  python3 -c "
import json, sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import set_stage_source
rd = Path('$req_dir')
set_stage_source(rd, 2, 'stage2-office-hours.md', tool='office-hours',
                 origin='/Users/x/.gstack/projects/foo/y.md')
meta = json.loads((rd / '.req-meta.json').read_text())
assert meta['stage2_source'] == 'stage2-office-hours.md', meta
assert meta['stage2_tool'] == 'office-hours', meta
assert meta['stage2_source_origin'] == '/Users/x/.gstack/projects/foo/y.md', meta
# 不能丢已有字段
assert meta['id'] == 'req-006', meta
assert meta['stage'] == 1, meta
print('OK')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "OK" /tmp/out.$$; then
    pass_test
  else
    _fail "B 分支写入失败"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_set_stage_source_strict_no_meta_raises() {
  start_test "set_stage_source: .req-meta.json 不存在 → StateReadError"
  fixture_setup
  req_dir=$(fixture_create_req "req-007" "test" 1)
  rm "$req_dir/.req-meta.json"
  python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import set_stage_source, StateReadError
try:
    set_stage_source(Path('$req_dir'), 2, 'analysis.md', tool='req-analysis')
except StateReadError:
    print('OK')
else:
    print('FAIL: should raise StateReadError when meta missing')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "^OK$" /tmp/out.$$; then
    pass_test
  else
    _fail "缺 meta 时应抛 StateReadError"
    cat /tmp/out.$$ /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑤+⑥ 静态 grep：D-i v4 关键 hook 点已用 helper / 通用术语
# -----------------------------------------------------------------

test_grep_req_transition_uses_helper() {
  start_test "grep: req-transition.py 已 import get_stage_source（R3-C1）"
  if grep -q "from _lib.state import" "$FRAMEWORK_ROOT/scripts/req-transition.py" && \
     grep -q "get_stage_source" "$FRAMEWORK_ROOT/scripts/req-transition.py"; then
    pass_test
  else
    _fail "req-transition.py 应 import 并调用 get_stage_source"
  fi
}

test_grep_req_stage_gate_branch_B_has_set_stage_source() {
  start_test "grep: req-stage-gate B 分支调 set_stage_source(tool='office-hours')"
  if grep -q "set_stage_source" "$FRAMEWORK_ROOT/skills/req-stage-gate/SKILL.md" && \
     grep -q "tool='office-hours'" "$FRAMEWORK_ROOT/skills/req-stage-gate/SKILL.md"; then
    pass_test
  else
    _fail "req-stage-gate B 分支应调 set_stage_source 写 office-hours tool 元数据"
  fi
}

test_grep_new_req_option1_removed() {
  start_test "grep: new-req 砍选项 1（不再说"自跑 /office-hours 整理 brief"）"
  # 砍掉的特征：原选项 1 "自跑 /office-hours（gstack skill）做六问深挖思考"
  if grep -q "自跑 /office-hours" "$FRAMEWORK_ROOT/skills/new-req/SKILL.md"; then
    _fail "new-req 仍含 '自跑 /office-hours' 选项 1 残留"
  else
    pass_test
  fi
}

# -----------------------------------------------------------------
# ④ snapshot 集成：B 分支推 Stage 3 路径连通（合并到 ③ 由 test-req-transition 覆盖；
#                  这里独立验 helper 写完 → get 读回链路）
# -----------------------------------------------------------------

test_set_get_round_trip_B_branch() {
  start_test "round-trip: B 分支 set → get 拿到 stage2-office-hours.md 绝对路径"
  fixture_setup
  req_dir=$(fixture_create_req "req-008" "test" 1)
  # 模拟 snapshot 落盘
  echo "<!-- snapshot from /tmp/src.md -->" > "$req_dir/stage2-office-hours.md"
  python3 -c "
import sys
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
from _lib.state import set_stage_source, get_stage_source
rd = Path('$req_dir')
set_stage_source(rd, 2, 'stage2-office-hours.md', tool='office-hours',
                 origin='/tmp/src.md')
p = get_stage_source(rd, 2)
assert p == rd / 'stage2-office-hours.md', p
assert p.exists(), f'file should exist at {p}'
content = p.read_text()
assert '<!-- snapshot from' in content, content
print('OK')
" >/tmp/out.$$ 2>/tmp/err.$$
  if grep -q "OK" /tmp/out.$$; then
    pass_test
  else
    _fail "B 分支 set→get 链路断"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_get_stage_source_meta_override
test_get_stage_source_fallback_no_field
test_get_stage_source_legacy_no_meta_file
test_get_stage_source_keyerror_unknown_stage
test_set_stage_source_A_branch
test_set_stage_source_B_branch_with_origin
test_set_stage_source_strict_no_meta_raises
test_grep_req_transition_uses_helper
test_grep_req_stage_gate_branch_B_has_set_stage_source
test_grep_new_req_option1_removed
test_set_get_round_trip_B_branch

report_results "stage-source-helper"
