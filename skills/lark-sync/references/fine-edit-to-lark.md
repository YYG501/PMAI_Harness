# 本地 -> 飞书精细同步

## 适用场景

- 本地 markdown 里有最新规格口径，但飞书文档已有图片、评论、复杂表格、白板或附件
- PM 明确要求"不要全覆盖"、"别丢图"、"只改几段"
- 飞书是在线协作面，需要保留非正文内容

## 流程

1. 读取本地 markdown 和 frontmatter，取得 `lark_doc_id` / `lark_doc_url` / 已有 `lark_revision_id`。
2. 拉取飞书当前内容：

   ```bash
   lark-cli docs +fetch --doc <doc_id> --detail full --as user
   ```

3. 记录当前 revision 和待同步本地正文 hash。若由 `/pmai-lark-review` 进入，必须同时读取 ready apply plan、`remote-native.json` 和 `remote-coverage.json`：`target_base` 必须是 `remote_native_snapshot`，当前 revision 必须等于 plan 的 `remote_revision_id`，内容与格式未归位都必须为 0；不满足就回到 review，不写飞书。
4. 对比本地正文与飞书正文，按章节列出差异。
5. 为每处差异选择最小动作。普通同步可按下表选择；由 `/pmai-lark-review` 进入时只允许 XML `str_replace` / `block_*`，并以 coverage 里的原生 block ID 和格式处置为边界，禁止 Markdown overwrite 或大段重建：

| 差异类型 | 动作 |
|---|---|
| 纯文本小改 | `str_replace` |
| 连续无图片、无复杂结构的区段 | markdown 范围替换 |
| 表格、列表、图文混排附近 | `fetch --detail with-ids` 后用 `block_replace` / `block_insert_after` / `block_delete` |
| 图片、白板、附件附近 | 默认不碰，除非 PM 明确要改 |

6. 分批执行。第一笔 `lark-cli docs +update` 携带步骤 3 的 `--revision-id`；后续每笔携带上一笔返回的 revision。每批修改后立即 fetch 回读，revision 冲突时停止，不用 `-1` 或重试覆盖。
7. 终检通过后，更新本地 frontmatter 的 `lark_synced_at` 和 `lark_revision_id`，不改正文。review 路径还必须逐个确认标记为 preserved 的 block ID、样式属性、资源 token 和原引用映射未变化。
8. 用回读确认后的 revision 刷新下一轮评审基线：

   ```bash
   python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" baseline \
     "<markdown_path>" \
     --revision-id "<revision_id>" \
     --expected-source-hash "<步骤 3 的本地正文 hash>"
   ```

   该命令同时记录规范化本地正文 hash；revision 与 hash 必须一起更新，不能只改一项。

9. 由 `/pmai-lark-review` 进入时，基线刷新后运行：

   ```bash
   python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" verify-sync \
     --manifest "$REVIEW_DIR/review.json" \
     --plan "$REVIEW_DIR/apply-plan.json"
   ```

   只有正文稳定语义投影等于 T、原生格式 hash、资源 token 与原引用映射全部通过，才算同步完成。

## 操作纪律

- `str_replace` 是全局替换，pattern 必须唯一；不唯一就改用更长锚点或 block 操作。
- `block_replace` 会生成新 id；后续还要动相邻块时先重新 fetch。
- 每笔写入必须使用明确的 base revision，不能依赖默认 latest。
- 图片相邻块要保守处理；普通同步至少比较数量，review 路径必须比较原 block ID、token 和格式 hash。
- 列表项通常是独立块；替换段落不会自动替换后续列表项。
- 向 `docs +update` 传内容时使用 `--content -` 并通过 stdin 发送；不得创建临时正文文件，也不得把正文拼进 argv。

## 验收

必须满足：

- 必须出现的新文案已经出现。
- 必须删除的旧文案已经消失。
- 图片、附件、白板数量没有减少。
- revision 已更新。
- `lark_published_revision_id` 与 `lark_published_source_hash` 已刷新为最终对齐点。
- 飞书回读内容与本轮预期一致。
- review 路径的 `verify-sync` 已生成 100% 内容覆盖率与格式保真率回执。
