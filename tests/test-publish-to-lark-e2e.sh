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

test_first_time_create_modern_shape
test_warns_on_html_table
test_no_warn_on_pipe_table
test_overwrite_uses_existing_doc_id
test_overwrite_strips_frontmatter
test_first_time_create_legacy_nested_shape
test_cwd_workaround_present_in_real_invocation
test_preflight_blocks_old_lark_cli
test_preflight_blocks_unlogged_in

report_results "publish-to-lark-e2e"
