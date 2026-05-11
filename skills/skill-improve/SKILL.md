---
name: skill-improve
description: |
  把 PM 写的 skill 反馈消化到对应 skill 的 SKILL.md / references。流程化执行：读反馈 + 对账现状 + PM 逐条决策 + 改 SKILL + 归档反馈到 skill-feedback/。
---

# /skill-improve

## When To Use

**模式 A（显式反馈文件）**：PM 已写好反馈文件，显式调用：
- `/skill-improve prd-writing skill-feedback/prd-writing-2026-04-27.md`
- 或反馈文件在业务仓（如 `ExampleConsumerApp/<skill>-skill-feedback.md`），参数给路径，本 skill 自动归档

**模式 B（会话内直接反馈）**：PM 在会话里直接说某 skill 有问题（"这里不对"、"这个 skill 应该…"、"每次跑 X skill 都会出现…"），AI 主动识别并走本 skill 流程，无需 PM 先写反馈文件。

> AI 触发判据：PM 指出的问题明确指向某个 skill 的行为 / 输出 / 流程设计，且不是当前 task 的 ad-hoc 修复。

## 关键设计

**消化 ≠ 照单全收。** PM 反馈是经验素材，不是 skill 改动指令。AI 必须先读现状（SKILL.md + references/）再对账：很多反馈点已被 skill 部分或全部落地，逐条改会重复或冲突。

**PM 逐条决策不可替代。** AI 出对账表，PM 拍板"采纳/不采纳"。AI 不替 PM 决"这条反馈合理与否"。

**反馈归档不是仪式。** 归档时**带消化结果对账表**，让未来回查的人 30 秒看清"反馈 → 落地位置"。光复制原文等于没归档。

## Workflow

### 步骤 1：接收反馈源 + 定位目标 skill

**模式 A**（有反馈文件）：
- 第一参数：skill 名 → 定位 `skills/<skill-name>/`
- 第二参数：反馈文件路径 → 全文 Read
- 如果反馈文件不在生成器仓 `skill-feedback/` 下，先复制到 `skill-feedback/<skill-name>-<反馈日期>.md`

**模式 B**（会话内直接反馈）：
1. AI 先从会话上下文里提取 PM 反馈，整理成结构化条目，向 PM 确认：

   ```
   我识别到以下 [skill-name] 反馈，走 /skill-improve 消化，请确认：
   1. [反馈条目一]
   2. [反馈条目二]
   （如有遗漏或理解偏差请补充）
   ```

2. PM 确认后，以此为反馈内容走步骤 2-7；归档时 AI 用整理的条目生成反馈文件（不要求 PM 事先手写）。

### 步骤 2：读 skill 现状（SKILL.md + 全部 references）

```bash
SKILL_DIR="skills/<skill-name>"
# 主 SKILL.md
cat "$SKILL_DIR/SKILL.md"
# 全部 references（如有）
ls "$SKILL_DIR/references/" 2>/dev/null && cat "$SKILL_DIR/references/"*.md
```

**强约束**：必须读完整 references/ 子文件。很多 v3.5 拆分后写作规则 / 输入流细则不在 SKILL.md 主文件，只在 references/ 里。光读主文件会漏判"已落地"。

### 步骤 3：对账（反馈逐条 vs 现状）

把反馈文件按节标题（`^## ` / `^### `）拆条目，对每条问：

1. **现状是否已落地这条？** grep 现状里的关键句 / 反例 / 正例。命中 → 已落地。
2. **如果落地了，落地位置是哪个文件 / 哪一节？** 写明路径（`SKILL.md §X.Y` 或 `references/<file>.md §X`）。
3. **如果部分落地，gap 是什么？** 写明缺什么。
4. **如果未落地，反馈要的是什么？** 一句话。

输出对账表（chat 里给 PM 看）：

```markdown
| # | 反馈类目 | 落地状态 | 现状位置 | 剩余 gap |
|---|---|---|---|---|
| 1.1 | [反馈节标题] | ✅ 已落地 | SKILL.md §4.1 | — |
| 1.3 | [反馈节标题] | ⚠️ 部分 | SKILL.md §4.3 已禁 X 但未明示 Y | 加一行 Y |
| 二 | [反馈节标题] | ❌ 未落地 | — | [反馈要点一句话] |
```

**反模式**：
- 不读现状直接对照反馈逐条改（会重复、会冲突）
- 把"部分落地"按"已落地"写过去 → 漏 gap
- 把"已落地"按"未落地"写过去 → 重复改 / 文档膨胀

### 步骤 4：PM 决策（不可替代）

向 PM 输出对账表 + 用 AskUserQuestion 让 PM 多选哪些 gap 落地：

- 如果剩余 gap ≤ 3 项：单题 multiSelect，每项给 1-2 行描述 + 落地成本估算
- 如果 gap > 3 项：分组成 2-4 题（按反馈大类拆）

**禁止**：
- AI 替决"这条反馈不合理，跳过" — 反馈是 PM 经验，AI 不能替决
- 把所有 gap 默认全做 — 部分 gap 可能跟其它 skill / 工具职责重叠（如 prd-writing 反馈四里"AI 自动合并表格 cell"实际归 publish-to-lark），PM 决定归位

### 步骤 5：改 SKILL.md / references

PM 决策后逐条改：

- **修主文件**（小补丁，1-3 行）：直接 Edit 主 SKILL.md
- **加新规则块**（>5 行的子节）：判断是否抽到 references/——主文件超过 ~400 行 + 子节自包含 → 进 references/
- **跨 skill 改动**（如反馈四 → publish-to-lark）：明示要修哪个 skill；改动到该 skill 的 SKILL.md

每改一处给 PM 一行确认（Edit 工具调用 + git diff 自动展示已经够，PM 可以在 IDE 看）。

### 步骤 6：归档反馈到 skill-feedback/

把反馈文件归档到生成器仓 `skill-feedback/<skill-name>-<YYYY-MM-DD>.md`：

1. 复制原文（步骤 1 已经做了；如果 PM 决策过程中改了反馈文件，重新拷一份）
2. **在反馈文件顶部 frontmatter 后追加「消化结果对账表」**（即步骤 3 的对账表，更新到反映 PM 决策结果）
3. 状态注释：`<!-- 状态：已消化（YYYY-MM-DD <commit-hash>）；保留作历史档案 -->`
4. 删除业务仓的原反馈文件（如反馈源在业务仓）—— 防止源文件继续被 PM 编辑造成两份脱节版本

如果 PM 决策"部分 gap 不落地"：在对账表里标明「不采纳 — PM 理由：[一句话]」，让未来回看时不会以为是漏掉。

### 步骤 7：commit

按生成器仓 commit 风格：

```
refactor(skills): <skill-name> 消化 PM 反馈 N 项 + 反馈归档

PM 反馈来源：skill-feedback/<skill-name>-<YYYY-MM-DD>.md
落地范围：
- <落地点 1>（反馈类目 X.Y）
- <落地点 2>（反馈类目 X.Z）
- <跨 skill 落地点>（反馈类目 X.W → <other-skill>）

未采纳：<标注未采纳项 + 一句话理由>（如有）
```

如果改动跨多个 skill：默认单 commit（除非改动相互冲突或 PM 明确要求拆）。

## 反模式（不要做）

1. **AI 替决** —— "这条反馈说得有道理，我直接改" / "这条反馈意义不大，跳过"。所有采纳/不采纳判断由 PM 给。AI 只出对账 + 改动建议，不下采纳判断。

2. **照单全收** —— PM 反馈 9 大类 → AI 改 9 处 → 与现状重复 5 处。**对账永远先于改动**。

3. **跨 skill 改动不归位** —— 反馈写"prd-writing 应该自动合并表格 cell"，但实际能力归 publish-to-lark。AI 应识别归位，不硬塞 prd-writing。

4. **归档不带对账** —— 光把反馈文件复制到 `skill-feedback/`、不在文件顶部加消化对账表。未来回看的人 → 重新做对账。

5. **改动不留 commit hash 在归档文件里** —— 归档文件状态注释要写 commit hash（消化时可能跨多个 commit，写主 commit hash 即可）。

6. **不读 references/** —— v3.5 后大量 skill 拆了 references 子文件，光读主 SKILL.md 会漏判落地状态。

## 反馈文件命名约定

- 业务仓写的反馈：`ExampleConsumerApp/<skill-name>-skill-feedback.md`（业务仓自己定，本 skill 不约束）
- 归档到生成器仓：`skill-feedback/<skill-name>-<YYYY-MM-DD>.md`（YYYY-MM-DD 取反馈创建时间，不是归档时间）
- 同一 skill 多次反馈：日期不同自然分文件，不合并

## 与其它 skill 的关系

- **不替代 task PM 反馈循环**（task-execute / task-submit 反馈循环只动当前 task 的代码，不沉淀到 skill 层）
- **下游接 close-task §1.5 视觉规范反馈反推 DESIGN.md** 的逻辑等价 —— 都是"PM 反馈 → 沉淀到长期约束源"，但各自归不同沉淀点（DESIGN.md 是项目级视觉规范单一来源；skill SKILL.md 是 skill 行为约束单一来源）

## Rules

- 反馈逐条对账，禁止照单全收
- PM 决策不可替代；AI 出对账，不下采纳判断
- references/ 必读，不只读主 SKILL.md
- 归档文件必须带消化对账表 + commit hash 状态注释
- 跨 skill 反馈识别归位，不硬塞错误 skill
- 模式 B：AI 必须先整理反馈条目向 PM 确认，不能直接跳到步骤 2（防止 AI 误读会话上下文）
