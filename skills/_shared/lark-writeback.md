# 飞书精细写回合同

本文件是 PMAI 内部共享能力，不是公开 Skill。`/pmai-publish-to-lark` 在更新已有文档时使用它；`/pmai-lark-review` 在目标版本已经确认并 apply 后，也直接使用同一合同。两个公开入口不得为了复用执行步骤而互相调用。

当前版本定义 Agent 必须遵守的写回协议。确定性 Writeback Runner 尚未实现前，Agent 仍需通过 `lark-doc-edit` / `lark-cli` 完成操作，但不得降低 revision、原生内容保留和回读验收要求。

## 输入

普通发布更新必须具备：

- 本地 Markdown 路径及其稳定正文快照。
- 绑定的 `lark_doc_id` / `lark_doc_url`。
- `lark_published_revision_id` 与 `lark_published_source_hash` 组成的最后对齐基线。

评审回流写回还必须具备：

- 当前批次的 sealed `apply-plan.json`。
- `remote-native.json` 与 `remote-coverage.json`。
- 已 apply 的目标版本 T。

## 写入前判断

1. 拉取飞书当前 full 内容和 revision，确认文档身份仍与本地绑定一致。
2. 普通发布更新只有在当前飞书 revision 等于 `lark_published_revision_id` 时才能继续。基线缺失、远端 revision 已前进或无法证明远端未独立变化时，零写入并转 `/pmai-lark-review`；不得把远端变化当成发布缓存覆盖。
3. 评审回流必须确认当前 revision 同时等于 apply plan 的 `remote_revision_id` 和首笔写入采用的 expected revision；`target_base` 必须是 `remote_native_snapshot`，内容与格式未归位都必须为 0。
4. 本地正文必须仍等于本轮绑定的稳定快照。写入期间本地内容变化时停止，不把旧飞书 revision 与新正文绑定。

## 精细写入

先按章节和原生 block 建立差异，再为每处差异选择最小动作：

| 差异类型 | 动作 |
|---|---|
| 唯一锚点内的纯文本小改 | XML `str_replace` |
| 连续、无图片且无复杂结构的安全区段 | 有边界的范围替换 |
| 表格、列表或图文混排附近 | fetch with ids 后使用 `block_replace` / `block_insert_after` / `block_delete` |
| 图片、白板、附件或未知原生块附近 | 默认保留；没有明确计划不得修改 |

执行纪律：

- `str_replace` 的 pattern 必须唯一；不唯一时扩大锚点或改用 block 操作。
- `block_replace` 会生成新 block ID；后续仍需操作相邻块时重新 fetch 定位。
- 第一笔写入携带写前 revision；后续每笔携带上一笔写操作返回的 revision。
- revision 冲突时立即停止，不使用 latest、`-1` 或重新 fetch 后盲目重放。
- 向 `docs +update` 传正文时固定使用 `--content -` 和 stdin；不创建临时正文文件，不把正文放进 argv。
- 普通发布也必须保留未计划修改的图片、评论、白板、附件、复杂格式和原生 block。
- 评审回流只允许 apply plan 和 coverage 明确列出的 XML / block 操作；禁止 Markdown overwrite 或大段重建。

## 验收与基线

1. 写后重新 fetch 同一文档，确认必须出现的内容已经出现、必须删除的内容已经消失，未计划章节没有变化。
2. 普通发布至少核对图片、附件、白板和嵌入内容没有减少；评审回流还必须运行：

   ```bash
   python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" verify-sync \
     --manifest "$REVIEW_DIR/review.json" \
     --plan "$REVIEW_DIR/apply-plan.json"
   ```

3. 只有回读内容和 revision 都稳定后，运行：

   ```bash
   python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" baseline \
     "<markdown_path>" \
     --revision-id "<final_revision_id>" \
     --expected-source-hash "<本轮稳定本地正文 hash>"
   ```

4. `lark_published_revision_id` 与 `lark_published_source_hash` 必须作为同一个对齐点一起更新。任一侧变化或验收失败都不得刷新基线。
