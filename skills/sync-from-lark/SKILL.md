---
name: pmai-sync-from-lark
description: 将飞书 Docx 正文机械同步回本地 Markdown。只在 PM 已明确“以飞书为准、不需要判断”时使用；它不分析正文或批注对产品决定、规格、原型和实现的影响，需要判断时改用 pmai-lark-review。
---

# /pmai-sync-from-lark

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要读取飞书内容或改写本地文档。

## When To Use

- PM 明确说“以飞书为准”“飞书是最终版”“直接同步回来，不需要判断”。
- PM 只想预览飞书正文同步回本地会产生哪些差异。

以下情况不用本 skill：

- 把本地文档发布或更新到飞书：用 `/pmai-publish-to-lark`。
- PM 在飞书 review、修改正文或添加批注，并希望影响规格、决定、原型或实现：用 `/pmai-lark-review`。
- 只是说“我在飞书改了”，但没有明确放弃产品影响判断：默认进入 `/pmai-lark-review`。

本 skill 不猜真相源、不判断产品影响，也不调用其它公开 Skill。它只执行 PM 已明确方向的飞书到本地机械同步。

## Required Inputs

1. `markdown_path` 或飞书 Docx URL / token，至少提供一个。
2. 明确的“以飞书为准、不需要判断”意图；缺失时停止并转 `/pmai-lark-review`。
3. 若实际写入本地，需要唯一、安全的目标 Markdown 路径。

## 必读 References

- `references/pull-from-lark.md`
- `references/diff-only.md`
- `skills/_shared/lark-document-verification.md`

## Workflow

### 步骤 0：保护现场

1. 确认 `git status --short --branch`。
2. 若目标 Markdown 有未提交正文变化，停止并说明覆盖风险；未获得 PM 对当前现场的再次确认前不写入。
3. 若目标模块存在 `building / iterating / final_check` 的 active build，停止机械回拉。规格变化需要先进入 `/pmai-lark-review` 判断并接回现有生命周期。
4. 只允许修改目标 Markdown；不整理其它文件，不更新决定、原型或实现。

### 步骤 1：只读预览或执行回拉

- PM 要“先看看差异”时，按 `references/diff-only.md` 只读比较，不修改任何一侧。
- PM 已明确直接同步时，按 `references/pull-from-lark.md` 只替换本地正文，完整保留原 frontmatter 和未知字段。

### 步骤 2：验收

按 `skills/_shared/lark-document-verification.md` 检查本地正文、目标范围和对齐基线。任何检查失败都停止，不修改其它产品资产补救。

### 步骤 3：回执

```text
处理结果：<已按飞书更新本地 / 已完成差异比较>
目标文档：<本地路径>
内容变化：<采用或发现了哪些飞书正文变化>
校验结果：<通过 / 未通过及原因>
需要你处理：<无需处理 / 仍需 PM 判断的具体问题>
```

## Rules

- 只有 PM 已明确“以飞书为准、不需要判断”才能写本地。
- 不读取或处理飞书评论来推断产品结论。
- 不修改 `decisions.md`、Proposal、原型或实现。
- 不从旧本地正文补回飞书已经删除的概念。
- 不在本地脏改或 active build 上机械覆盖规格。
- 不把 revision、hash、frontmatter 等内部协议放进正常 PM 回执。

## Failure Handling

| 情况 | 处理 |
|---|---|
| 用户意图仍需要判断 | 停止机械同步，转 `/pmai-lark-review` |
| 目标 Markdown 有未提交正文变化 | 停止并说明会覆盖的具体文件 |
| 目标模块有 active build | 停止，转 `/pmai-lark-review` 接回当前生命周期 |
| 飞书 fetch、身份或 revision 校验失败 | 零写入，提示检查文档、权限和登录态 |
| 本地安全写入失败 | 保留现场，不修改其它文件 |
| 回读或基线刷新失败 | 报告未对齐，不声称同步完成 |
