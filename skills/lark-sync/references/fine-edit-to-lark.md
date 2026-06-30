# 本地 -> 飞书精细同步

## 适用场景

- 本地 markdown 里有最新规格口径，但飞书文档已有图片、评论、复杂表格、白板或附件
- PM 明确要求"不要全覆盖"、"别丢图"、"只改几段"
- 飞书是在线协作面，需要保留非正文内容

## 流程

1. 读取本地 markdown 和 frontmatter，取得 `lark_doc_id` / `lark_doc_url` / 已有 `lark_revision_id`。
2. 拉取飞书当前内容：

   ```bash
   lark-cli docs +fetch --api-version v2 --doc <doc_id>
   ```

3. 记录当前 revision。若返回内容含图片、白板、附件或复杂表格，记录数量作为验收基线。
4. 对比本地正文与飞书正文，按章节列出差异。
5. 为每处差异选择最小动作：

| 差异类型 | 动作 |
|---|---|
| 纯文本小改 | `str_replace` |
| 连续无图片、无复杂结构的区段 | markdown 范围替换 |
| 表格、列表、图文混排附近 | `fetch --detail with-ids` 后用 `block_replace` / `block_insert_after` / `block_delete` |
| 图片、白板、附件附近 | 默认不碰，除非 PM 明确要改 |

6. 分批执行，每批修改后立即 fetch 回读。
7. 终检通过后，更新本地 frontmatter 的 `lark_synced_at` 和 `lark_revision_id`，不改正文。

## 操作纪律

- `str_replace` 是全局替换，pattern 必须唯一；不唯一就改用更长锚点或 block 操作。
- `block_replace` 会生成新 id；后续还要动相邻块时先重新 fetch。
- 图片相邻块要保守处理；改完必须比较图片数量。
- 列表项通常是独立块；替换段落不会自动替换后续列表项。
- 临时内容文件必须放 cwd 下，并用相对路径传给 `--content @file`。

## 验收

必须满足：

- 必须出现的新文案已经出现。
- 必须删除的旧文案已经消失。
- 图片、附件、白板数量没有减少。
- revision 已更新。
- 飞书回读内容与本轮预期一致。
