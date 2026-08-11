# 飞书文档对齐验收

本文件是发布、评审写回和飞书回拉共用的内部验收合同。

## 写飞书后的回读

任何写飞书动作后都必须重新 fetch，不能只看 `update success`。至少检查：

- 必须出现的新内容已经出现。
- 必须删除的旧内容已经消失。
- 图片、附件、白板和嵌入内容没有减少。
- revision 已更新且等于最后一笔写操作返回的 revision。
- 未计划修改的章节没有变化。

由 `/pmai-lark-review` 进入时，数量检查不够：必须运行同批 `verify-sync`，逐个验证 `remote-coverage.json` 中 preserved 原生 block 的格式 hash、资源 token 和原引用映射，并证明飞书稳定语义投影等于 sealed T。内容覆盖率、格式保真率或未归位项任一不满足要求时，不得继续 checkpoint。

## 回拉本地后的检查

飞书正文写入本地后至少检查：

- PM 指定必须保留的词仍然存在。
- 明确要求删除的旧概念已经消失。
- 标题与主章节完整。
- 目标 Markdown 之外没有文件变化。
- 未从原型、旧文档或过程记录反推补回产品事实。

## 对齐基线

首次发布由 `/pmai-publish-to-lark` 回填文档身份和 `lark_published_at`。每次成功发布、精细写回或回拉后，使用以下命令原子刷新下一轮三方比较基线：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" baseline \
  "<markdown_path>" \
  --revision-id "<已回读确认的 revision>" \
  --expected-source-hash "<当前本地正文的规范化 SHA-256>"
```

该命令必须同时确认本地正文仍是本轮对齐版本、飞书 revision 仍是回读版本。`lark_published_revision_id` 与 `lark_published_source_hash` 不能只更新一项。

`lark_synced_at` 和 `lark_revision_id` 可记录最近一次机械同步；评审 checkpoint 继续使用 `lark_reviewed_revision_id`、`lark_reviewed_comment_at`、`lark_reviewed_comment_ids` 和 `lark_reviewed_at`。这些字段只用于内部校验与恢复，不进入正常 PM 回执。

## PM 回执

```text
处理结果：<已更新飞书 / 已按飞书更新本地 / 已完成差异比较>
目标文档：<本地路径或飞书 URL>
内容变化：<本轮实际变化>
校验结果：<已回读一致 / 未通过及原因>
需要你处理：<无需处理 / 仍需 PM 判断的具体问题>
```
