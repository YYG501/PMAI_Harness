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

## 本地 frontmatter 追踪字段

首次发布仍由 `/pmai-publish-to-lark` 回填 `lark_published_at`。

同步类动作使用：

```yaml
lark_synced_at: <ISO timestamp>
lark_revision_id: <revision_id>
```

含义：

- `lark_synced_at`：最近一次本地与飞书完成同步的时间
- `lark_revision_id`：同步完成后飞书侧 revision

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
