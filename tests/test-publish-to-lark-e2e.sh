#!/usr/bin/env bash
# End-to-end smoke for scripts/publish-to-lark.py — fake CLI in PATH，验证
# preflight + publish_first_time + publish_overwrite 走完整流程，重点：
# - doc_id 4-fallback 解析（≥1.0.27 inner.doc_id shape）
# - cwd workaround 真在 publish-to-lark 入口下生效
# - frontmatter 反写 lark_doc_id / lark_doc_url
# - 跑 --no-merge-cells 跳过表格 merge（merge 路径依赖真 lark-cli block tree）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIM_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/helpers/fake-lark-cli.sh" "$SHIM_DIR/lark-cli"
chmod +x "$SHIM_DIR/lark-cli"

cleanup() {
  rm -rf "$SHIM_DIR"
}
trap cleanup EXIT

export PATH="$SHIM_DIR:$PATH"

# 用一个临时 cwd（避免污染主仓 .claude/）
WORK=$(mktemp -d)
mkdir -p "$WORK/.claude"
cat > "$WORK/.claude/lark-publish.json" <<JSON
{
  "default_targets": {
    "prd": {
      "kind": "wiki",
      "token": "fakeWikiNodeT",
      "title_template": "{filename}"
    }
  }
}
JSON

cleanup_work() {
  rm -rf "$SHIM_DIR" "$WORK"
}
trap cleanup_work EXIT


test_first_time_create_modern_shape() {
  start_test "publish-to-lark first-time: 解析 ≥1.0.27 inner.doc_id shape"
  cat > "$WORK/doc.md" <<'MD'
# Hello

正文 first time。
MD
  pushd "$WORK" >/dev/null
  # 默认 shape: {"data":{"doc_id":"docX1","doc_url":"https://x"}}（fake-cli 默认）
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells doc.md 2>&1)
  rc=$?
  popd >/dev/null
  if [ $rc -ne 0 ]; then
    _fail "expected exit 0, got $rc; out: $out"
    return
  fi
  if ! echo "$out" | grep -q "docX1\|文档已创建"; then
    _fail "缺创建确认；out: $out"
    return
  fi
  # frontmatter 应被反写
  if ! grep -q "lark_doc_id: docX1" "$WORK/doc.md"; then
    _fail "frontmatter 未反写 lark_doc_id; head: $(head -10 "$WORK/doc.md")"
    return
  fi
  if ! grep -q '^lark_published_revision_id: 7$' "$WORK/doc.md" \
    || ! grep -Eq '^lark_published_source_hash: [0-9a-f]{64}$' "$WORK/doc.md"; then
    _fail "frontmatter 未记录可评审发布基线; head: $(head -12 "$WORK/doc.md")"
    return
  fi
  pass_test
}

test_overwrite_uses_existing_doc_id() {
  start_test "publish-to-lark overwrite: 复用 frontmatter 里的 doc_id"
  pushd "$WORK" >/dev/null
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells doc.md 2>&1)
  rc=$?
  popd >/dev/null
  if [ $rc -ne 0 ]; then
    _fail "expected exit 0, got $rc; out: $out"
    return
  fi
  if ! echo "$out" | grep -q "覆盖飞书文档.*docX1"; then
    _fail "未走 overwrite 分支或 doc_id 不对; out: $out"
    return
  fi
  pass_test
}

test_overwrite_uses_docx_url_without_doc_id() {
  start_test "publish-to-lark overwrite: 仅有 Docx URL 时仍覆盖原文档并补齐 doc_id"
  cat > "$WORK/url-only.md" <<'MD'
---
lark_doc_url: https://tenant.feishu.cn/docx/docURL1
lark_published_revision_id: 11
lark_published_source_hash: old-source-hash
---

# URL only

正文。
MD
  : > "$WORK/url-only-calls.log"
  export FAKE_LARK_LOG="$WORK/url-only-calls.log"
  export FAKE_LARK_DOCS_UPDATE_OUT='{"ok":true,"data":{"document":{"document_id":"docURL1","revision_id":12},"result":"success","updated_blocks_count":1,"warnings":[]}}'
  export FAKE_LARK_DOCS_FETCH_OUT='{"ok":true,"data":{"document":{"document_id":"docURL1","revision_id":12,"content":"# URL only\n\n正文。\n"}}}'
  pushd "$WORK" >/dev/null
  local out rc
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
    --type prd --no-merge-cells url-only.md 2>&1)
  rc=$?
  popd >/dev/null
  unset FAKE_LARK_LOG FAKE_LARK_DOCS_UPDATE_OUT FAKE_LARK_DOCS_FETCH_OUT
  if [ "$rc" -ne 0 ] \
    || ! grep -q '^ARGV: docs +update .*--doc docURL1' "$WORK/url-only-calls.log" \
    || grep -q '^ARGV: docs +create' "$WORK/url-only-calls.log" \
    || ! grep -q '^lark_doc_id: docURL1$' "$WORK/url-only.md" \
    || ! grep -q '^lark_published_revision_id: 12$' "$WORK/url-only.md"; then
    _fail "URL-only binding did not overwrite safely; rc=$rc out=$out log=$(cat "$WORK/url-only-calls.log")"
    return
  fi
  pass_test
}

test_partial_update_clears_stale_review_baseline() {
  start_test "publish-to-lark overwrite: partial_success 失败关闭并清除旧基线"
  cat > "$WORK/partial.md" <<'MD'
---
lark_doc_id: docPartial
lark_doc_url: https://tenant.feishu.cn/docx/docPartial
lark_published_revision_id: 5
lark_published_source_hash: old-source-hash
---

# Partial

正文。
MD
  export FAKE_LARK_DOCS_UPDATE_OUT='{"ok":true,"data":{"document":{"document_id":"docPartial","revision_id":6},"result":"partial_success","updated_blocks_count":1,"warnings":["one block failed"]}}'
  pushd "$WORK" >/dev/null
  local out rc
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
    --type prd --no-merge-cells partial.md 2>&1)
  rc=$?
  popd >/dev/null
  unset FAKE_LARK_DOCS_UPDATE_OUT
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '未完整成功' \
    || grep -q '^lark_published_revision_id:' "$WORK/partial.md" \
    || grep -q '^lark_published_source_hash:' "$WORK/partial.md" \
    || ! grep -q '^lark_doc_id: docPartial$' "$WORK/partial.md"; then
    _fail "partial update should fail without a stale baseline; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_overwrite_refreshes_review_baseline() {
  start_test "publish-to-lark overwrite: 刷新 revision 与本地正文 hash 基线"
  local old_hash
  old_hash=$(sed -n 's/^lark_published_source_hash: //p' "$WORK/doc.md")
  printf '\n覆盖后的新内容。\n' >> "$WORK/doc.md"
  export FAKE_LARK_DOCS_FETCH_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","revision_id":8,"content":"# Hello\n\n正文 first time。\n\n覆盖后的新内容。\n"}}}'
  export FAKE_LARK_DOCS_UPDATE_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","revision_id":8},"result":"success","updated_blocks_count":1,"warnings":[]}}'
  pushd "$WORK" >/dev/null
  python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
    --type prd --no-merge-cells doc.md >/dev/null 2>&1
  local rc=$?
  popd >/dev/null
  unset FAKE_LARK_DOCS_FETCH_OUT FAKE_LARK_DOCS_UPDATE_OUT
  local new_hash
  new_hash=$(sed -n 's/^lark_published_source_hash: //p' "$WORK/doc.md")
  if [ "$rc" -ne 0 ] || ! grep -q '^lark_published_revision_id: 8$' "$WORK/doc.md" \
    || [ -z "$new_hash" ] || [ "$old_hash" = "$new_hash" ]; then
    _fail "overwrite 未刷新评审基线; rc=$rc old=$old_hash new=$new_hash head=$(head -12 "$WORK/doc.md")"
    return
  fi
  pass_test
}

test_remote_edit_during_publish_does_not_become_baseline() {
  start_test "publish-to-lark overwrite: 远端并发修改不吸收到发布基线"
  export FAKE_LARK_DOCS_UPDATE_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","revision_id":9},"result":"success","updated_blocks_count":1,"warnings":[]}}'
  export FAKE_LARK_DOCS_FETCH_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","revision_id":10,"content":"# Hello\n\nPM concurrent edit\n"}}}'
  pushd "$WORK" >/dev/null
  local out rc
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
    --type prd --no-merge-cells doc.md 2>&1)
  rc=$?
  popd >/dev/null
  unset FAKE_LARK_DOCS_FETCH_OUT FAKE_LARK_DOCS_UPDATE_OUT
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '远端并发编辑'; then
    _fail "远端并发修改应触发安全降级; rc=$rc out=$out"
    return
  fi
  if grep -q '^lark_published_revision_id:' "$WORK/doc.md" \
    || grep -q '^lark_published_source_hash:' "$WORK/doc.md"; then
    _fail "远端并发修改被错误记录为发布基线: $(head -12 "$WORK/doc.md")"
    return
  fi
  pass_test
}

test_frontmatter_refresh_preserves_concurrent_local_edit() {
  start_test "publish-to-lark overwrite: 基线回填不覆盖发布期间的本地编辑"
  cat > "$WORK/concurrent.md" <<'MD'
---
lark_doc_id: docX1
lark_doc_url: https://x.feishu.cn/docx/docX1
lark_published_revision_id: 7
lark_published_source_hash: stale-source-hash
---

# Concurrent
MD
  export FAKE_LARK_MUTATE_FILE="$WORK/concurrent.md"
  export FAKE_LARK_MUTATE_CONTENT='发布期间新增的本地内容。'
  pushd "$WORK" >/dev/null
  python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
    --type prd --no-merge-cells concurrent.md >/dev/null 2>&1
  local rc=$?
  popd >/dev/null
  unset FAKE_LARK_MUTATE_FILE FAKE_LARK_MUTATE_CONTENT
  if [ "$rc" -ne 0 ] || ! grep -q '^发布期间新增的本地内容。$' "$WORK/concurrent.md" \
    || grep -q '^lark_published_revision_id:' "$WORK/concurrent.md" \
    || grep -q '^lark_published_source_hash:' "$WORK/concurrent.md"; then
    _fail "基线回填覆盖了本地正文或绑定了错配版本; rc=$rc tail=$(tail -10 "$WORK/concurrent.md")"
    return
  fi
  pass_test
}

test_overwrite_clears_stale_baseline_when_revision_fetch_fails() {
  start_test "publish-to-lark overwrite: revision 回读失败时清除旧基线"
  cat > "$WORK/fetch-fail.md" <<'MD'
---
lark_doc_id: docX1
lark_doc_url: https://x.feishu.cn/docx/docX1
lark_published_revision_id: 8
lark_published_source_hash: stale-source-hash
---

# Hello

覆盖后的新内容。
MD
  export FAKE_LARK_DOCS_UPDATE_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","revision_id":9},"result":"success","updated_blocks_count":1,"warnings":[]}}'
  export FAKE_LARK_DOCS_FETCH_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","content":"# Hello"}}}'
  pushd "$WORK" >/dev/null
  local out rc
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
    --type prd --no-merge-cells fetch-fail.md 2>&1)
  rc=$?
  popd >/dev/null
  unset FAKE_LARK_DOCS_FETCH_OUT FAKE_LARK_DOCS_UPDATE_OUT
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '后续评审将按旧文档降级处理'; then
    _fail "revision 回读失败应保留发布成功并明确降级; rc=$rc out=$out"
    return
  fi
  if grep -q '^lark_published_revision_id:' "$WORK/fetch-fail.md" \
    || grep -q '^lark_published_source_hash:' "$WORK/fetch-fail.md"; then
    _fail "revision 回读失败后仍保留过期基线: $(head -12 "$WORK/fetch-fail.md")"
    return
  fi
  if ! grep -q '^lark_doc_id: docX1$' "$WORK/fetch-fail.md" \
    || ! grep -q '^覆盖后的新内容。$' "$WORK/fetch-fail.md"; then
    _fail "清理旧基线时破坏了文档身份或正文: $(head -12 "$WORK/fetch-fail.md")"
    return
  fi
  pass_test
}

test_overwrite_strips_frontmatter() {
  start_test "publish-to-lark overwrite: 发给飞书的正文已剥离 frontmatter"
  # doc.md 此时已带首次发布回写的 frontmatter（lark_doc_id 等）—— 覆盖路径必然带
  : > "$WORK/fm-calls.log"
  export FAKE_LARK_LOG="$WORK/fm-calls.log"
  pushd "$WORK" >/dev/null
  python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells doc.md >/dev/null 2>&1
  popd >/dev/null
  unset FAKE_LARK_LOG
  # --no-merge-cells 下只有 docs +update 一次带 @./ 的调用 → 唯一 MARKDOWN_HEAD
  local head_line
  head_line=$(grep "^MARKDOWN_HEAD:" "$WORK/fm-calls.log")
  if [ -z "$head_line" ]; then
    _fail "未捕获 docs +update 的 MARKDOWN_HEAD; log: $(cat "$WORK/fm-calls.log")"
    return
  fi
  if echo "$head_line" | grep -q -- "MARKDOWN_HEAD: ---" \
     || echo "$head_line" | grep -q "lark_doc_id"; then
    _fail "覆盖发布把 frontmatter 当正文发了; got: $head_line"
    return
  fi
  if ! grep '^ARGV: docs +update' "$WORK/fm-calls.log" \
    | grep -q -- '--revision-id 7'; then
    _fail "覆盖发布没有携带写前 revision 栅栏: $(grep '^ARGV: docs +update' "$WORK/fm-calls.log")"
    return
  fi
  pass_test
}

test_first_time_create_legacy_nested_shape() {
  start_test "publish-to-lark first-time: 解析旧版 document.document_id 嵌套 shape"
  # 切换 fake CLI 返回旧 shape
  export FAKE_LARK_DOCS_CREATE_OUT='{"data":{"document":{"document_id":"legacyD"}}}'
  cat > "$WORK/legacy.md" <<'MD'
# Legacy shape test

正文。
MD
  pushd "$WORK" >/dev/null
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells legacy.md 2>&1)
  rc=$?
  popd >/dev/null
  unset FAKE_LARK_DOCS_CREATE_OUT
  if [ $rc -ne 0 ]; then
    _fail "expected exit 0, got $rc; out: $out"
    return
  fi
  if ! grep -q "lark_doc_id: legacyD" "$WORK/legacy.md"; then
    _fail "未解析嵌套 shape; head: $(head -10 "$WORK/legacy.md")"
    return
  fi
  pass_test
}

test_cwd_workaround_present_in_real_invocation() {
  start_test "publish-to-lark 真实入口下 cwd workaround 生效"
  export FAKE_LARK_LOG="$WORK/calls.log"
  cat > "$WORK/cwd.md" <<'MD'
# cwd workaround test
正文
MD
  pushd "$WORK" >/dev/null
  # shim 里 $(pwd) 取逻辑路径（与 publish-to-lark 启动时的 cwd 一致）
  local md_dir; md_dir=$(pwd)
  python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells cwd.md >/dev/null 2>&1
  popd >/dev/null
  unset FAKE_LARK_LOG
  # 校验：docs +create 那次调用的 CWD = md_dir，--markdown 是 @./cwd.md
  if ! awk '/^ARGV: docs \+create/{flag=1} /^---/{flag=0} flag' "$WORK/calls.log" \
       | grep -q "@./cwd.md"; then
    _fail "docs +create 没用 @./cwd.md"
    cat "$WORK/calls.log" >&2
    return
  fi
  if ! awk '/^ARGV: docs \+create/{flag=1} /^---/{flag=0} flag' "$WORK/calls.log" \
       | grep -q "CWD: $md_dir"; then
    _fail "docs +create 没切到 $md_dir; got: $(awk '/^ARGV: docs \+create/{flag=1} /^---/{flag=0} flag' "$WORK/calls.log" | grep CWD:)"
    return
  fi
  pass_test
}

test_preflight_blocks_old_lark_cli() {
  start_test "preflight: 版本 < 1.0.27 → 拒绝"
  export FAKE_LARK_VERSION="lark-cli 1.0.10"
  cat > "$WORK/old.md" <<'MD'
# x
正文
MD
  pushd "$WORK" >/dev/null
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells old.md 2>&1)
  rc=$?
  popd >/dev/null
  unset FAKE_LARK_VERSION
  if [ $rc -eq 0 ]; then
    _fail "expected non-zero; got 0; out: $out"
    return
  fi
  if echo "$out" | grep -q "低于最低要求"; then
    pass_test
  else
    _fail "未触发版本不足错误; out: $out"
  fi
}

test_preflight_blocks_unlogged_in() {
  start_test "preflight: auth status 失败 → 拒绝"
  export FAKE_LARK_AUTH_STATUS_RC=1
  cat > "$WORK/auth.md" <<'MD'
# x
正文
MD
  pushd "$WORK" >/dev/null
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells auth.md 2>&1)
  rc=$?
  popd >/dev/null
  unset FAKE_LARK_AUTH_STATUS_RC
  if [ $rc -eq 0 ]; then
    _fail "expected non-zero; got 0; out: $out"
    return
  fi
  if echo "$out" | grep -q "飞书 CLI 未登录"; then
    pass_test
  else
    _fail "未触发未登录错误; out: $out"
  fi
}

test_warns_on_html_table() {
  start_test "preflight: 正文含裸 HTML <table> → 大声警告（不阻断发布）"
  cat > "$WORK/htmltable.md" <<'MD'
# HTML 表格测试

正文一段。

<table>
  <tr><td>a</td><td>b</td></tr>
</table>

收尾。
MD
  pushd "$WORK" >/dev/null
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells htmltable.md 2>&1)
  rc=$?
  popd >/dev/null
  # 警告不阻断发布 → 仍应 exit 0
  if [ $rc -ne 0 ]; then
    _fail "HTML <table> 警告不应阻断发布; rc=$rc out: $out"
    return
  fi
  if echo "$out" | grep -q "检测到 1 处 HTML <table>"; then
    pass_test
  else
    _fail "未对 HTML <table> 报警; out: $out"
  fi
}

test_no_warn_on_pipe_table() {
  start_test "preflight: 纯管道表格 + 围栏代码块里的 <table> → 不误报"
  cat > "$WORK/pipetable.md" <<'MD'
# 管道表格测试

| 角色 | 描述 |
| --- | --- |
| 普通成员 | 无特殊权限 |

下面是代码示例，不算真表格：

```html
<table><tr><td>示例</td></tr></table>
```
MD
  pushd "$WORK" >/dev/null
  out=$(python3 "$FRAMEWORK_ROOT/scripts/publish-to-lark.py" \
        --type prd --no-merge-cells pipetable.md 2>&1)
  rc=$?
  popd >/dev/null
  if [ $rc -ne 0 ]; then
    _fail "expected exit 0, got $rc; out: $out"
    return
  fi
  if echo "$out" | grep -q "检测到.*HTML <table>"; then
    _fail "管道表格 / 围栏内 <table> 被误报; out: $out"
    return
  fi
  pass_test
}

test_no_merge_marker_parsing() {
  start_test "parse_table_skip_flags: <!-- lark:no-merge --> 标记按表对齐"
  out=$(python3 - "$FRAMEWORK_ROOT" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location(
    "p2l", sys.argv[1] + "/scripts/publish-to-lark.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
body = "\n".join([
    "普通表（应合并）：", "",
    "| a | b |", "| --- | --- |", "| 1 | 2 |", "",
    "<!-- lark:no-merge -->", "",
    "| x | y |", "| --- | --- |", "| 9 | 8 |", "",
])
flags = m.parse_table_skip_flags(body)
assert flags == [False, True], flags
print("OK", flags)
PY
)
  if echo "$out" | grep -q "OK \[False, True\]"; then
    pass_test
  else
    _fail "skip flags 不符预期; out: $out"
  fi
}

test_table_writes_chain_document_revision() {
  start_test "publish-to-lark tables: POST/DELETE/PATCH 串联 revision，缺失时停止"
  out=$(python3 - "$FRAMEWORK_ROOT" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location(
    "p2l_revision_chain", sys.argv[1] + "/scripts/publish-to-lark.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

cells = ["c00", "anchor", "c10", "source"]
blocks = {
    "anchor": {"children": []},
    "source": {"children": ["source-text"]},
    "source-text": {
        "block_type": 2,
        "text": {"elements": [{"text_run": {"content": "continued"}}]},
    },
}
merge_range = {
    "row_start_index": 0,
    "row_end_index": 2,
    "column_start_index": 1,
    "column_end_index": 2,
}

calls = []
revisions = iter([8, 9, 10])
def success_api(method, path, params=None, data=None):
    calls.append((method, params["document_revision_id"]))
    return {"code": 0, "data": {"document_revision_id": next(revisions)}}

module.lark_api = success_api
final_revision = module.merge_desc_group_with_content(
    "docTable", "table", cells, 2, blocks, merge_range, 7
)
assert final_revision == 10, final_revision
assert calls == [("POST", 7), ("DELETE", 8), ("PATCH", 9)], calls

failed_calls = []
responses = iter([
    {"code": 0, "data": {"document_revision_id": 8}},
    {"code": 0, "data": {}},
])
def incomplete_api(method, path, params=None, data=None):
    failed_calls.append((method, params["document_revision_id"]))
    return next(responses)

module.lark_api = incomplete_api
try:
    module.merge_desc_group_with_content(
        "docTable", "table", cells, 2, blocks, merge_range, 7
    )
except RuntimeError as exc:
    assert "未返回 document_revision_id" in str(exc), exc
else:
    raise AssertionError("missing revision should stop the merge chain")
assert failed_calls == [("POST", 7), ("DELETE", 8)], failed_calls
print("OK")
PY
)
  if [ "$out" = "OK" ]; then
    pass_test
  else
    _fail "revision chain assertions failed; out: $out"
  fi
}

test_first_time_create_modern_shape
test_warns_on_html_table
test_no_warn_on_pipe_table
test_no_merge_marker_parsing
test_table_writes_chain_document_revision
test_overwrite_uses_existing_doc_id
test_overwrite_uses_docx_url_without_doc_id
test_partial_update_clears_stale_review_baseline
test_overwrite_refreshes_review_baseline
test_remote_edit_during_publish_does_not_become_baseline
test_frontmatter_refresh_preserves_concurrent_local_edit
test_overwrite_clears_stale_baseline_when_revision_fetch_fails
test_overwrite_strips_frontmatter
test_first_time_create_legacy_nested_shape
test_cwd_workaround_present_in_real_invocation
test_preflight_blocks_old_lark_cli
test_preflight_blocks_unlogged_in

report_results "publish-to-lark-e2e"
