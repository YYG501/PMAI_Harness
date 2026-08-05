# 飞书 -> 本地回拉为最终版

## 适用场景

- PM 或协作者已经在飞书上完成最终稿
- 用户明确说"以飞书为准"、"飞书是最终版"、"把飞书拉回来"
- 本地 markdown 可能落后，不能再覆盖飞书

## 流程

1. 从本地 frontmatter 或用户给的 URL / token 定位飞书文档。
2. 拉取飞书 markdown：

   ```bash
   lark-cli docs +fetch --doc <doc_id> --doc-format markdown --as user
   ```

3. 记录飞书 revision。
4. 如果本地目标文件有未提交正文改动，先说明：这条路径会用飞书正文覆盖本地正文，但完整保留现有 frontmatter。
5. 逐字保留原 frontmatter（包括未知字段、嵌套 YAML 和注释），只补丁本次变化的 PMAI 顶层标量；不要重建成一份“只含追踪字段”的 YAML。需要更新的 PMAI 字段包括：

   ```yaml
   ---
   lark_doc_id: <doc_id>
   lark_doc_url: <url>
   lark_published_at: <首次发布时间；已有则保留>
   lark_synced_at: <ISO timestamp>
   lark_revision_id: <revision_id>
   lark_published_revision_id: <revision_id>
   lark_published_source_hash: <规范化正文 SHA-256>
   lark_reviewed_revision_id: <已有则保留>
   lark_reviewed_comment_at: <已有则保留>
   lark_reviewed_comment_ids: <已有则保留；同秒评论/回复边界>
   lark_reviewed_at: <已有则保留>
   ---
   ```

   上述只列 PMAI 字段示意；原文件里的其它键和值必须原样保留。

6. 正文完全使用飞书返回内容；使用 adapter 的 `replace_markdown_body` 做正文原子替换，不通过重写整文件破坏 frontmatter。
7. 写入正文后计算当前本地正文 hash，再运行 `lark-review.py baseline <markdown_path> --revision-id <revision_id> --expected-source-hash <hash>`，原子刷新 revision + 正文 hash；不要手写不匹配的基线字段。
8. 不顺手修正文案、不补章节、不从旧本地稿恢复概念。
9. 跑关键口径检查：PM 指定必须存在的词是否存在，已要求删除的旧概念是否消失，标题和主章节是否完整。

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
