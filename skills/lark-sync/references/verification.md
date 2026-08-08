# 飞书同步验收规则

## 写飞书后的必做回读

任何写飞书动作后，都不能只看 `update success`。必须重新 fetch，核验实际在线内容。

检查项：

- 必须出现的新文案是否出现
- 必须删除的旧文案是否消失
- 图片数量是否未减少
- 附件数量是否未减少
- 白板 / 嵌入内容数量是否未减少
- revision 是否更新
- 本轮没有误伤未计划修改的章节

若由 `/pmai-lark-review` 进入，数量检查不够：必须运行该批次的 `verify-sync`，逐个验证 `remote-coverage.json` 中 preserved 原生 block 的格式 hash、资源 token 和原引用映射，并证明飞书稳定语义投影等于 sealed T。未达到内容覆盖率 100%、格式保真率 100% 或未归位 0 时，不刷新 checkpoint。

## 本地 frontmatter 追踪字段

首次发布仍由 `/pmai-publish-to-lark` 回填文档身份和 `lark_published_at`。每次成功发布、精细同步或回拉完成后，都要记录下一轮三方比较所需的对齐基线。

同步类动作使用：

```yaml
lark_synced_at: <ISO timestamp>
lark_revision_id: <revision_id>
lark_published_revision_id: <revision_id>
lark_published_source_hash: <规范化正文 SHA-256>
```

含义：

- `lark_synced_at`：最近一次本地与飞书完成同步的时间
- `lark_revision_id`：同步完成后飞书侧 revision
- `lark_published_revision_id`：本地和飞书最后一次确认对齐的 revision
- `lark_published_source_hash`：该对齐点对应的本地正文 hash

评审 checkpoint 另使用 `lark_reviewed_revision_id`、`lark_reviewed_comment_at`、`lark_reviewed_comment_ids` 和 `lark_reviewed_at`；时间与同秒互动 ID 必须一起保留，避免漏掉同一秒出现的新评论或回复。

精细同步和回拉使用以下命令原子更新后两项：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" baseline \
  "<markdown_path>" \
  --revision-id "<回读确认后的 revision>" \
  --expected-source-hash "<本次同步正文的规范化 SHA-256>"
```

该命令会同时确认本地正文仍是本次同步源、飞书当前 revision 仍是回读版本；任一侧变化都不得刷新基线。

## 产品口径检查

对 PM 指定过的关键词和旧概念做机械检查：

- PM 要求保留的词必须存在
- PM 要求删除的旧概念必须消失
- 不从原型、旧文档或过程记录反推补回产品事实

如果检查失败，停止扩大修改范围，先报告失败项。

## 输出摘要

```text
同步完成
模式：A/B/C
飞书 revision：<before> -> <after>
回读验证：
- 新内容：通过 / 失败
- 旧内容：通过 / 失败
- 富内容数量：通过 / 失败
- 仍需 PM 判断：<列表>
```
