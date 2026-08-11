# 飞书正文机械同步回本地

## 前提

- PM 已明确以飞书正文为最终版，不需要判断产品影响。
- 目标文件没有未提交正文变化。
- 目标模块没有 active build。

任一前提不成立都停止；需要理解正文或评论影响时转 `/pmai-lark-review`。

## 流程

1. 从本地 frontmatter 或 PM 提供的 URL / token 定位同一篇飞书 Docx。
2. 拉取飞书 Markdown 和 revision：

   ```bash
   lark-cli docs +fetch --doc <doc_id> --doc-format markdown --as user
   ```

3. 确认返回的文档身份与本地绑定一致。
4. 逐字保留原 frontmatter，包括未知字段、嵌套 YAML 和注释；只替换正文，不重建整个文件。
5. 使用 adapter 的 `replace_markdown_body` 原子替换正文。不得顺手润色、补章节、改标题或恢复本地旧概念。
6. 计算写入后的规范化正文 hash，按 `skills/_shared/lark-document-verification.md` 刷新 revision 与正文 hash 组成的对齐基线。
7. 检查标题、主章节、PM 指定关键词和明确删除的旧概念，并确认目标文件之外没有变化。

## 禁止

- 禁止把本地旧正文片段混回飞书最终稿。
- 禁止处理评论或回复并据此修改产品资产。
- 禁止修改目标 Markdown 之外的文件。
- 禁止在 active build 中把规格机械替换成未经判断的新版本。
