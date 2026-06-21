#!/usr/bin/env bash
# D-iii v2 vp-4：attachments AI 接管 helper + path-contract 回归。
# 覆盖（11 case）：
#   ① copy_attachment 成功（机械命名 + attachments_seen append + pending_inject）
#   ② SensitivePathError 触发（.env / .ssh / token denylist）
#   ③ FileSizeError 触发（>50MB hard cap）
#   ④ register + list round-trip
#   ⑤ is_seen 旧 req 兼容（无 attachments_seen 字段 → 空）
#   ⑥ remove_attachment（rm + 清 seen 行）
#   ⑦ replace_attachment（保留 filename + attachments_seen 更新）
#   ⑧ Path.expanduser 处理 ~/x.pdf
#   ⑨ 含空格文件名不炸
#   ⑩ trigger 2 regression：现有 PM 手动 cp + is_seen 判定（REGRESSION RULE）
#   ⑪ 静态 grep：SKILL prose 已加 trigger 0 段 + B 分支 disable + commit pathspec
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

# -----------------------------------------------------------------
# Helper for running attachments.py inline test scripts
# -----------------------------------------------------------------

_run_py() {
  local script="$1"
  python3 -c "
import sys, json
from pathlib import Path
sys.path.insert(0, '$FRAMEWORK_ROOT/scripts')
$script
" 2>&1
}

# -----------------------------------------------------------------
# ① copy_attachment happy path
# -----------------------------------------------------------------

test_copy_attachment_happy_path() {
  start_test "copy_attachment: 成功 cp + 机械命名 + attachments_seen append + pending_inject"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 2)
  src="$req_dir/source-mock.pdf"
  printf 'PDF content mock' > "$src"

  out=$(_run_py "
from _lib.attachments import copy_attachment
r = copy_attachment(Path('$req_dir'), Path('$src'), 'analysis', 'test hint')
assert r['new_name'] == 'analysis-source-mock.pdf', r['new_name']
assert (Path('$req_dir') / 'attachments' / 'analysis-source-mock.pdf').exists()
meta = json.loads((Path('$req_dir') / '.req-meta.json').read_text())
seen = meta['attachments_seen']
assert len(seen) == 1, seen
assert seen[0]['name'] == 'analysis-source-mock.pdf'
assert seen[0]['hint'] == 'test hint'
assert seen[0]['stage_prefix'] == 'analysis'
# pending_inject: analysis.md 不存在
assert r['pending_inject'] == True, r
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "copy_attachment happy path 失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

test_copy_attachment_req_plan_anchor() {
  start_test "copy_attachment: req-plan 六步锚点 pending 判定（rewire 回归）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 2)
  src="$req_dir/spec-mock.pdf"
  printf 'mock' > "$src"

  out=$(_run_py "
from _lib.attachments import copy_attachment
# req-plan.md 不存在 → pending_inject True + 命名前缀 req-plan
r = copy_attachment(Path('$req_dir'), Path('$src'), 'req-plan', 'h')
assert r['new_name'] == 'req-plan-spec-mock.pdf', r['new_name']
assert r['pending_inject'] == True, r
# 建 req-plan.md 后 → pending_inject False（证明六步锚点在映射里）
(Path('$req_dir') / 'req-plan.md').write_text('# plan')
src2 = Path('$req_dir') / 'spec2.pdf'; src2.write_text('m')
r2 = copy_attachment(Path('$req_dir'), src2, 'req-plan')
assert r2['pending_inject'] == False, r2
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "req-plan 锚点回归失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ② SensitivePathError 触发
# -----------------------------------------------------------------

test_sensitive_path_error() {
  start_test "SensitivePathError: .env 命中 denylist"
  fixture_setup
  req_dir=$(fixture_create_req "req-002" "test" 2)
  src="$req_dir/.env"
  printf 'SECRET=xxx' > "$src"

  out=$(_run_py "
from _lib.attachments import copy_attachment, SensitivePathError
try:
    copy_attachment(Path('$req_dir'), Path('$src'), 'analysis')
    print('FAIL: should raise SensitivePathError')
except SensitivePathError as e:
    print(f'OK: pattern={e.pattern}')
")
  if echo "$out" | grep -q "^OK: pattern="; then
    pass_test
  else
    _fail "SensitivePathError 未触发"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ③ FileSizeError 触发
# -----------------------------------------------------------------

test_file_size_error() {
  start_test "FileSizeError: >50MB hard cap"
  fixture_setup
  req_dir=$(fixture_create_req "req-003" "test" 2)
  src="$req_dir/big.bin"
  # 51 MB 二进制
  dd if=/dev/zero of="$src" bs=1048576 count=51 2>/dev/null

  out=$(_run_py "
from _lib.attachments import copy_attachment, FileSizeError
try:
    copy_attachment(Path('$req_dir'), Path('$src'), 'analysis')
    print('FAIL: should raise FileSizeError')
except FileSizeError as e:
    print(f'OK: size_mb={e.size_mb:.1f}')
")
  if echo "$out" | grep -q "^OK: size_mb=51"; then
    pass_test
  else
    _fail "FileSizeError 未触发或 size 不符"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ④ register + list round-trip
# -----------------------------------------------------------------

test_register_list_round_trip() {
  start_test "register_attachment + list_attachments_seen round-trip"
  fixture_setup
  req_dir=$(fixture_create_req "req-004" "test" 2)

  out=$(_run_py "
from _lib.attachments import register_attachment, list_attachments_seen
register_attachment(Path('$req_dir'), 'analysis-x.pdf', src_origin='/orig/x.pdf', hint='hint X', stage_prefix='analysis')
register_attachment(Path('$req_dir'), 'analysis-y.pdf', src_origin='/orig/y.pdf', hint='hint Y', stage_prefix='analysis')
seen = list_attachments_seen(Path('$req_dir'))
assert len(seen) == 2, seen
assert seen[0]['name'] == 'analysis-x.pdf'
assert seen[1]['name'] == 'analysis-y.pdf'
assert seen[0]['src_origin'] == '/orig/x.pdf'
assert seen[0]['hint'] == 'hint X'
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "register + list round-trip 失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑤ is_seen 旧 req 兼容（无 attachments_seen 字段）
# -----------------------------------------------------------------

test_is_seen_legacy_req() {
  start_test "is_seen: 旧 req 无 attachments_seen 字段 → False（旧 req 兼容）"
  fixture_setup
  req_dir=$(fixture_create_req "req-005" "test" 2)
  # fixture 创建的 .req-meta.json 无 attachments_seen 字段（旧 req 形态）

  out=$(_run_py "
from _lib.attachments import is_seen, list_attachments_seen
assert is_seen(Path('$req_dir'), 'analysis-x.pdf') == False
assert list_attachments_seen(Path('$req_dir')) == []
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "旧 req 兼容失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑥ remove_attachment
# -----------------------------------------------------------------

test_remove_attachment() {
  start_test "remove_attachment: rm 文件 + 清 attachments_seen 行"
  fixture_setup
  req_dir=$(fixture_create_req "req-006" "test" 2)
  src="$req_dir/source.pdf"
  printf 'content' > "$src"

  out=$(_run_py "
from _lib.attachments import copy_attachment, remove_attachment, is_seen
copy_attachment(Path('$req_dir'), Path('$src'), 'analysis', 'hint')
assert is_seen(Path('$req_dir'), 'analysis-source.pdf')
remove_attachment(Path('$req_dir'), 'analysis-source.pdf')
assert not (Path('$req_dir') / 'attachments' / 'analysis-source.pdf').exists()
assert not is_seen(Path('$req_dir'), 'analysis-source.pdf')
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "remove_attachment 失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

test_register_attachment_rejects_traversal_name() {
  start_test "register_attachment: ../evil.md filename 被拒绝"
  fixture_setup
  req_dir=$(fixture_create_req "req-011" "test" 2)

  out=$(_run_py "
from _lib.attachments import register_attachment, AttachmentError
try:
    register_attachment(Path('$req_dir'), '../evil.md', stage_prefix='analysis')
    print('FAIL: traversal should be rejected')
except AttachmentError:
    print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "register_attachment 应拒绝 traversal filename"
    echo "$out" >&2
  fi
  fixture_teardown
}

test_remove_attachment_rejects_traversal_and_keeps_file() {
  start_test "remove_attachment: traversal 不得删除 attachments 外文件"
  fixture_setup
  req_dir=$(fixture_create_req "req-012" "test" 2)
  victim="$req_dir/victim.md"
  printf 'keep me' > "$victim"

  out=$(_run_py "
from _lib.attachments import remove_attachment, AttachmentError
rd = Path('$req_dir')
mf = rd / '.req-meta.json'
meta = json.loads(mf.read_text())
meta['attachments_seen'] = [{'name': '../victim.md'}]
mf.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
try:
    remove_attachment(rd, '../victim.md')
    print('FAIL: traversal should be rejected')
except AttachmentError:
    assert (rd / 'victim.md').read_text() == 'keep me'
    print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "remove_attachment traversal 防护失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

test_copy_attachment_rejects_unsafe_stage_prefix() {
  start_test "copy_attachment: stage_prefix traversal 被拒绝"
  fixture_setup
  req_dir=$(fixture_create_req "req-013" "test" 2)
  src="$req_dir/source.pdf"
  printf 'content' > "$src"

  out=$(_run_py "
from _lib.attachments import copy_attachment, AttachmentError
try:
    copy_attachment(Path('$req_dir'), Path('$src'), '../analysis')
    print('FAIL: unsafe stage_prefix should be rejected')
except AttachmentError:
    assert not (Path('$req_dir') / 'attachments').exists()
    print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "copy_attachment 应拒绝 unsafe stage_prefix"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑦ replace_attachment
# -----------------------------------------------------------------

test_replace_attachment() {
  start_test "replace_attachment: 保留旧 filename + 内容已替换 + attachments_seen 更新"
  fixture_setup
  req_dir=$(fixture_create_req "req-007" "test" 2)
  src_old="$req_dir/v1.pdf"
  printf 'OLD content' > "$src_old"
  src_new="$req_dir/v2.pdf"
  printf 'NEW content much longer' > "$src_new"

  out=$(_run_py "
from _lib.attachments import copy_attachment, replace_attachment, list_attachments_seen
copy_attachment(Path('$req_dir'), Path('$src_old'), 'analysis', 'v1 hint')
r = replace_attachment(Path('$req_dir'), 'analysis-v1.pdf', Path('$src_new'))
assert r['new_name'] == 'analysis-v1.pdf', r  # 保留旧 filename
dst = Path('$req_dir') / 'attachments' / 'analysis-v1.pdf'
assert dst.exists()
content = dst.read_bytes()
assert content == b'NEW content much longer', content  # 新内容已替换
seen = list_attachments_seen(Path('$req_dir'))
assert len(seen) == 1, seen
assert seen[0]['name'] == 'analysis-v1.pdf'
# src_origin 用 endswith 比较（macOS /var/ vs /private/var/ resolve 差异）
assert seen[0]['src_origin'].endswith('/v2.pdf'), seen[0]['src_origin']
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "replace_attachment 失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑧ Path.expanduser 处理 ~/x.pdf
# -----------------------------------------------------------------

test_path_expanduser() {
  start_test "expanduser: ~/x.pdf 自动展开"
  fixture_setup
  req_dir=$(fixture_create_req "req-008" "test" 2)
  # 在 $HOME 下放一个临时文件
  src_file="$HOME/.pmaiwf-test-expand-$$.pdf"
  printf 'expand test' > "$src_file"

  out=$(_run_py "
from _lib.attachments import copy_attachment
r = copy_attachment(Path('$req_dir'), Path('~/.pmaiwf-test-expand-$$.pdf'), 'analysis')
assert r['new_name'] == 'analysis-.pmaiwf-test-expand-$$.pdf' or '.pmaiwf-test-expand-' in r['new_name'], r
assert r['abs_path'].exists()
print('OK')
")
  rm -f "$src_file"
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "expanduser 失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑨ 含空格文件名
# -----------------------------------------------------------------

test_filename_with_spaces() {
  start_test "含空格文件名: foo bar.pdf 不炸"
  fixture_setup
  req_dir=$(fixture_create_req "req-009" "test" 2)
  src="$req_dir/foo bar.pdf"
  printf 'space content' > "$src"

  out=$(_run_py "
from _lib.attachments import copy_attachment
r = copy_attachment(Path('$req_dir'), Path('$src'), 'analysis')
assert r['new_name'] == 'analysis-foo bar.pdf', r
assert r['abs_path'].exists()
content = r['abs_path'].read_text()
assert content == 'space content'
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "含空格文件名失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑩ trigger 2 改造 regression（REGRESSION RULE）
# -----------------------------------------------------------------

test_trigger2_regression_manual_cp_detection() {
  start_test "trigger 2 regression: PM 手动 cp 进 attachments/ + is_seen 判定（基于 attachments_seen 真相源）"
  fixture_setup
  req_dir=$(fixture_create_req "req-010" "test" 2)

  # 模拟 PM 手动 cp（绕过 trigger 0）—— 文件落盘但 attachments_seen 无登记
  mkdir -p "$req_dir/attachments"
  printf 'manual cp content' > "$req_dir/attachments/analysis-manual.pdf"

  out=$(_run_py "
from _lib.attachments import is_seen, register_attachment, list_attachments_seen
# regression 关键：is_seen 是 False（因 attachments_seen 列表无该条目，即使文件已落盘）
# 这正是 trigger 2 改造的核心 —— 不用引用 section 判，用 attachments_seen 真相源判
assert is_seen(Path('$req_dir'), 'analysis-manual.pdf') == False
# trigger 2 流程：caller 扫到 + is_seen=False → 问 PM → 答 OK 后补登记
register_attachment(Path('$req_dir'), 'analysis-manual.pdf', src_origin='manual-cp', hint='补登记', stage_prefix='analysis')
# 补登记后 is_seen=True
assert is_seen(Path('$req_dir'), 'analysis-manual.pdf') == True
seen = list_attachments_seen(Path('$req_dir'))
assert len(seen) == 1
print('OK')
")
  if echo "$out" | grep -q "^OK$"; then
    pass_test
  else
    _fail "trigger 2 regression 失败"
    echo "$out" >&2
  fi
  fixture_teardown
}

# -----------------------------------------------------------------
# ⑪ 静态 grep：SKILL prose 已加 trigger 0 段 + B 分支 disable + commit pathspec
# -----------------------------------------------------------------

test_skill_prose_trigger0_added() {
  start_test "grep: 5 个 stage SKILL 已加 trigger 0 段"
  local all_ok=1
  # req-analysis 已删（C1 删 skill 搬内核到 _shared/req-questioning.md；探索段附件走 attachments-upload.md 按类型归类）
  for skill in skills/new-req/SKILL.md skills/prd-writing/SKILL.md skills/task-spec/SKILL.md skills/implementation-design/SKILL.md skills/task-plan/SKILL.md; do
    if ! grep -q "copy_attachment" "$FRAMEWORK_ROOT/$skill"; then
      _fail "$skill 未加 copy_attachment 引用（trigger 0 段缺失）"
      all_ok=0
    fi
  done
  if [ "$all_ok" = "1" ]; then
    pass_test
  fi
}

test_skill_prose_new_req_commit_pathspec() {
  start_test "grep: new-req 步骤 4D commit pathspec 含 attachments/"
  # worktree 创建后置后：attachments/ 总在 4D 一次 commit 范围里（更强契约）
  if grep -q '"$REQ_REL/attachments"' "$FRAMEWORK_ROOT/skills/new-req/SKILL.md"; then
    pass_test
  else
    _fail "new-req 4D commit pathspec 未含 attachments/"
  fi
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_copy_attachment_happy_path
test_copy_attachment_req_plan_anchor
test_sensitive_path_error
test_file_size_error
test_register_list_round_trip
test_is_seen_legacy_req
test_remove_attachment
test_register_attachment_rejects_traversal_name
test_remove_attachment_rejects_traversal_and_keeps_file
test_copy_attachment_rejects_unsafe_stage_prefix
test_replace_attachment
test_path_expanduser
test_filename_with_spaces
test_trigger2_regression_manual_cp_detection
test_skill_prose_trigger0_added
test_skill_prose_new_req_commit_pathspec

report_results "attachments-helper"
