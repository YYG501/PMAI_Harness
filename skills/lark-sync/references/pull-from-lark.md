# 飞书 -> 本地回拉为最终版

## 适用场景

- PM 或协作者已经在飞书上完成最终稿
- 用户明确说"以飞书为准"、"飞书是最终版"、"把飞书拉回来"
- 本地 markdown 可能落后，不能再覆盖飞书

## 流程

1. 从本地 frontmatter 或用户给的 URL / token 定位飞书文档。
2. 拉取飞书 markdown：

   ```bash
   lark-cli docs +fetch --api-version v2 --doc <doc_id> --doc-format markdown
   ```

3. 记录飞书 revision。
4. 如果本地目标文件有未提交正文改动，先说明：这条路径会用飞书正文覆盖本地正文，只保留追踪 frontmatter。
5. 本地文件 frontmatter 只保留 PMAI 追踪字段：

   ```yaml
   ---
   lark_doc_id: <doc_id>
   lark_doc_url: <url>
   lark_synced_at: <ISO timestamp>
   lark_revision_id: <revision_id>
   ---
   ```

6. 正文完全使用飞书返回内容。
7. 不顺手修正文案、不补章节、不从旧本地稿恢复概念。
8. 跑关键口径检查：PM 指定必须存在的词是否存在，已要求删除的旧概念是否消失，标题和主章节是否完整。

## 输出

```text
已按飞书最终版同步本地文件
文件：<markdown_path>
飞书 revision：<revision_id>
检查：<关键词 / 旧概念 / 主章节>
```

## 禁止

- 禁止把本地旧正文片段混回飞书最终稿。
- 禁止顺手 humanize / 重排 / 改标题。
- 禁止修改目标 markdown 之外的文件。
