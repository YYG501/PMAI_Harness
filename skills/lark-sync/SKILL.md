---
name: pmai-lark-sync
description: |
  在 PMAI 项目中同步本地 markdown 规格与飞书在线文档：先判断真相源和同步方向，再选择精细编辑、整篇覆盖、飞书回拉或只 diff，最后回读验证并同步本地追踪信息。若要读取 PM 在飞书 review 后的正文修改和批注并更新规格/原型，改用 pmai-lark-review。
---

# /pmai-lark-sync

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要判断本地/飞书真相源或写同步追踪信息。

## When To Use

- PM 要把本地规格、PRD、功能型文档同步到飞书，但没有明确说可以整篇覆盖
- PM 说"更新飞书"、"同步飞书"、"不要覆盖"、"别丢图"、"只改某几段"
- PM 说"飞书是最终版"、"以飞书为准"、"把飞书拉回本地"
- PM 要先比较本地 markdown 和飞书在线文档哪里不一致

PM 说“我在飞书 review / 改过 / 批注了，按这些更新规格和原型”时，不走本 skill 的普通回拉，转 `/pmai-lark-review`。

本 skill 是 PMAI 层的飞书规格同步编排入口。它不替代底层飞书能力：

- 整篇发布 / 覆盖：调用 `/pmai-publish-to-lark`
- 精细编辑飞书：复用 `lark-doc-edit` 的 `str_replace` / `block_*` / 回读验证方法
- 飞书回拉本地、只 diff：由本 skill 定义 PMAI 项目语境下的流程
- 评审正文 + 评论的语义理解和生命周期分流：调用 `/pmai-lark-review`

## Required Inputs

1. `markdown_path` 或飞书文档 URL / token：至少给一个
2. 用户意图：如果输入里已能判断同步方向，按意图分流；判断不出时先问 PM
3. 项目真相源：涉及规格口径时，优先读取目标模块 `spec.md`、`decisions.md` 和 PM 当前确认内容

## 必读 References

按模式读取对应 reference；通用安全边界和验收必须始终读取：

- `references/intent-routing.md`
- `references/verification.md`
- 模式 A 读取 `references/fine-edit-to-lark.md`
- 模式 C 读取 `references/pull-from-lark.md`
- 模式 D 读取 `references/diff-only.md`

## Workflow

### 步骤 0：保护现场

1. 先确认 `git status --short --branch`
2. 本地有脏改时，只允许碰本次目标 markdown 文件；不要顺手整理其它文件
3. 临时内容文件只放当前 cwd 下，用完清理
4. 若目标 markdown 有未提交正文改动，而本次要用飞书覆盖本地正文，先向 PM 说明风险并等待确认

### 步骤 1：判定同步方向

先按 `references/intent-routing.md` 判断模式，不允许直接写飞书或改本地文件。

如果意图是“回收飞书评审并更新规格 / 决定 / 原型”，立即转 `/pmai-lark-review`，不要把它降级成模式 C 整篇回拉。

| 用户意图 | 真相源 | 模式 | 动作 |
|---|---|---|---|
| "更新飞书" / "同步到飞书" / "发布到飞书，但不要覆盖" | 本地 markdown | A | 精细修改飞书 |
| "重新发布" / "覆盖发布" / "整篇更新" | 本地 markdown | B | 调 `/pmai-publish-to-lark` overwrite |
| "整篇以飞书为最终版，只替换本地正文，不联动决定和实现" / "拉取飞书作为最终版" | 飞书 | C | 拉取飞书，覆盖本地正文 |
| "看哪里不一致" / "比一下" | 双方 | D | 只 diff，不改 |

如果用户只说"更新一下"，且上下文不能判断更新哪边，必须问：

```text
这次是把本地同步到飞书，还是把飞书同步回本地？
```

### 步骤 2：执行对应模式

- **模式 A：本地 -> 飞书精细同步**
  按 `references/fine-edit-to-lark.md` 执行。核心是先拉飞书当前内容，按章节 diff，再按每处差异选择最小动作。

- **模式 B：本地 -> 飞书整篇覆盖**
  只有 PM 明确说"覆盖 / 重新发布 / 整篇更新"才允许。调用 `/pmai-publish-to-lark <markdown_path>`，并在发布后按 `references/verification.md` 做关键内容回读。

- **模式 C：飞书 -> 本地回拉最终版**
  按 `references/pull-from-lark.md` 执行。本地正文完全采用飞书内容，保留 PMAI 飞书追踪字段，并把回拉完成点刷新为下一轮评审基线。

- **模式 D：只 diff，不修改**
  按 `references/diff-only.md` 执行。输出章节级差异和建议动作，不写飞书、不改本地。

### 步骤 3：验收与输出

所有写入路径都必须按 `references/verification.md` 验收。最终输出给 PM：

```text
同步结果：<已把本地内容更新到飞书 / 已把飞书内容更新到本地 / 已完成差异比较>
目标文档：<本地路径或飞书 URL>
内容变化：<本轮同步或发现了什么>
校验结果：<正文已回读一致；图片、附件和白板未丢失 / 未修改任何内容>
需要你处理：<无需处理 / 仍需 PM 判断的具体差异>
```

同步方向、在线版本和本地追踪字段继续作为内部校验依据保存；正常回执不让 PM 管理这些执行细节。只有出现并发冲突或校验失败时，才说明具体受阻内容和 PM 真正需要决定的事项。

## Rules

- **不能默认 overwrite**：只有 PM 明确说"覆盖 / 重新发布 / 整篇更新"才允许整篇覆盖
- **不能只看 update success**：每次写飞书后必须 fetch 回读
- **不能使用隐式 latest 写入**：每笔更新携带写前 revision，并把返回 revision 传给下一笔
- **不能没判方向就动手**："更新一下"不等于"本地覆盖飞书"
- **不能从原型反推规格**：规格口径以模块 `spec.md`、`decisions.md` 和 PM 当前确认内容为准
- **不能把过程变更写成产品事实**：已被 PM 删除的旧概念，不能因为旧文档里存在就补回来
- **不能破坏飞书富内容**：图片、评论、白板、附件、复杂表格附近默认保守处理
- **本地脏树只碰目标文件**：不要整理无关文件、不要跑会重写全仓的格式化
- **临时文件只放 cwd 下**：`lark-cli docs +update --content @file` 只接受相对路径；完成后清理
- **评审不走普通回拉**：正文修改和批注需要更新产品上下文或原型时，转 `/pmai-lark-review`
- **“我在飞书改了”默认是评审意图**：有发布基线且用户没有明确要求整篇回拉时转 `/pmai-lark-review`；是否联动规格 / 决定 / 实现仍有歧义时只问这一题

## Failure Handling

| 情况 | 处理 |
|---|---|
| 无法判断同步方向 | 停止，问 PM 是本地到飞书、飞书到本地、覆盖发布还是只 diff |
| 本地 markdown 缺 `lark_doc_id` 且未给飞书 URL | 若是首次发布，转模式 B；若是精细同步 / 回拉，先问 PM 提供 URL |
| 飞书 fetch 失败 | 停止，提示检查 token、权限和登录态 |
| 文本 pattern 不唯一 | 停止，改用 block id 或让 PM 确认锚点 |
| block id 过期 | 重新 fetch with ids，不继续用旧 id |
| 回读验证失败 | 说明失败项，停止扩大修改范围 |
