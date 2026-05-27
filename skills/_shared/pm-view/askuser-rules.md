# askuser-rules：AskUserQuestion 答题规则（M4 单一真相源）

> **职责**：PM 答题门规则的**单一真相源**，gsd `#3018 failure mode` 照搬。
> **调用方**：所有用 AskUserQuestion 的 skill（req-stage-gate / init-project / project-solution / new-req / task-confirm / task-execute / close-task / close-req）。
> **设计来源**：gsd `discuss-phase.md:95-102` + `gsd-discuss-phase/SKILL.md:29-35` 的 `#3018 failure mode` + 仓库 memory `feedback_open_questions_gate.md` + `feedback_close_default_flow.md` + commit 07a3a09。

---

## §1 4 条硬规则

### §1.1 规则 1：空答 / 没答 → STOP wait next message

**触发**：AskUserQuestion 调用后，PM 答 ——
- 空字符串 / 空白
- 选了「其他」但没填自由文本
- runtime 没返回答案（超时 / 中断）

**AI 行为**：

- ✅ 输出一句"我需要你回答上一题再继续"，STOP generating
- ✅ wait for next user message
- ✅ PM 下次发任何 message 时，再处理（可能是答原题，或转去别的事）
- ❌ **禁止**重试 AskUserQuestion（PM 没答=PM 还在想，再问一次不解决问题）
- ❌ **禁止**默认走 recommend 选项（PM 没说同意推进，AI 不能假定）
- ❌ **禁止**默认 No-op 静默继续（让 PM 看不见自己刚跳过了一个决策）

### §1.2 规则 2：没拿到答案前禁止落盘 artifact

**适用**：闸门类 AskUserQuestion（Decision gate / 未决问题闸门 / 执行前确认 / 验收呈交 / PM 定稿）。

**AI 行为**：

- ✅ **PM 答完后再写文件 / commit**
- ❌ PM 没答之前 **不能** ：
  - 写 PROJECT.md / ROADMAP.md / prd.md / task.md 等 PM 视图文件
  - git commit / git push
  - 调用 `req-transition.py --to N+1`（stage 推进）
  - 调用 `task-transition.py --status 已完成`（task 状态切换）

**历史教训**：commit `07a3a09` 处理过"PM 没答 AI 默认走通过分支导致 task 跳过验收"事故（memory `feedback_close_default_flow.md`）；commit `feedback_pm_decision_is_binding_contract.md` 强调"PM 决策 = binding contract，没答前 AI 不能假定"。

### §1.3 规则 3：runtime 不支持 AskUserQuestion 时退化为编号列表，仍 wait

**适用**：跨 runtime 兼容（Claude Code 原生支持 AskUserQuestion；Codex CLI / Gemini CLI 等不支持）。

**AI 行为**：

- runtime 不支持 → 输出编号列表（"1. xxx 2. yyy"）+ "请回复编号"
- **仍 wait**（不默认选第一个）
- PM 答编号 / 自由文本 → 按规则 1+2 处理

**编号规则**：
- ✅ **AskUserQuestion picker label 不带数字前缀**（picker UI 本身是按钮，加 "1." / "2." 干扰视觉）
- ✅ **只有退化模式才加编号**（PM 没 picker UI 时，输数字回复是最快路径）
- ✅ **退化模式必须加 "请回复编号（或自由文本说明）" 收尾**（提示 PM 怎么回话）

```
（runtime 不支持 AskUserQuestion 时的退化形态）

请选择：

1. 创建 PROJECT.md
   我会开始写 PROJECT.md，进入下一步

2. 继续探索
   你还想补充行业 / 用户 / 流程

请回复编号（或自由文本说明）：
```

### §1.4 规则 4：多决策必须拆开顺序问，禁止一次 AskUser 塞多个问题

**适用**：AI 准备问 PM 多个决策点。典型场景 —— review 结论的多条 finding 待拍 / autoplan 多决策点 / stage 闸门同时拍多件事 / 设计方案多个 open question。

**AI 行为**：

- ✅ **一次只问一个决策**：一个 AskUserQuestion 调用只放 1 个 `question` 字段（即使 runtime 允许 1-4 题）
- ✅ **业务大白话描述**：先讲屏幕上的真实样子 / 数据真实长相 / 用户路径，再问选项。例：「管理员页面这一列真实值长这样：`全租户 / 技术部 / 北京分公司`。评审觉得"数据范围"这个叫法 PM 不够直观。A. 保持原叫法 B. 改成"管的范围"」
- ✅ **顺序推进**：PM 答完一条 → AI 再问下一条；多决策之间不并行
- ✅ **总量预览**：开头一句话给 PM 总量心智模型，例「评审找了 3 件事要拍，逐条过」
- ❌ **禁止**一个 AskUserQuestion 塞 ≥2 个 `question`（即使 runtime 支持 1-4 题；塞多题 = 批量打包反模式）
- ❌ **禁止**术语密集：`combobox / scope / IA / 5/6 模型 / vp-N / I-XX5 / RBAC / ABAC` 等工程黑话直接用进 question 文本（→ 命中 `_shared/term-detector` 黑名单 + `pm-view/writing-rules.md §3.12 禁工程黑话`）
- ❌ **禁止**把 review/autoplan 整份结论打包成一个 AskUser 问"按你看怎么办"（review 找了 N 条 finding → 要 N 次 sequential 拍板）

**反例**（PM 已驳回过的写法）：
```
[AskUserQuestion]
question 1: req-005 角色模型用三元组还是二维分离？
question 2: scope 字段命名叫 scope 还是 range？
question 3:   要不要先做？
```
→ PM 反馈"没看明白问题"。原因：术语密集 + 多决策并列 + 无屏幕例子。

**正例**：
```
评审找了 3 件事要拍，逐条过。第 1 件：

当前管理员页面这一列真实值长这样：「全租户 / 技术部 / 北京分公司」。
评审觉得列头"数据范围"对 PM 不够直观。

[AskUserQuestion 单题]
A. 保持"数据范围"叫法不变
B. 改成"管的范围"
```
→ PM 答 A，AI 再进入第 2 件。

**Why**：PM 不读工程术语；多决策并列让 PM 无法逐个消化；批量打包 = AI 把"消化决策"成本推给 PM。出处：消费仓 memory `pm-plain-language-one-decision-at-a-time.md`（PM 在 req-006 多次驳回术语密集 / 批量 AskUser，明确说"没看明白问题"）。

**How to apply**：

- review / autoplan / 多 finding 结论 → 写完后**按 PM 大白话视角重排成 sequential 列表**，再逐条 AskUser
- 重的评审结论（如 [[autoplan]]）开头先给关键发现预览（"评审找了 N 件事，逐条过"），让 PM 知道总量
- AskUserQuestion 的 `question` 字段永远 = 1 个具体决策点
- 写完 question 文本自检：屏幕上的具体例子有吗？工程黑话扫掉了吗？

---

## §2 不在 scope（设计上不解决）

| # | 场景 | 为什么不解决 |
|---|---|---|
| M4.1 | 把所有 AskUserQuestion 改成相同 UI 模板 | 不同场景需要不同选项数 / 措辞；M4 只规范"答题规则约束"，不强制 UI 模板 |
| M4.2 | AskUserQuestion 答案做 LLM 校验（PM 答案是否"合理"）| 过度工程；PM 答案 binding，AI 不评判合理性 |
| **M4.3** | "暂跳过 / 以后再说 / 带假设前进"逃生舱 | 未决问题闸门必须 PM 答完才能过；逃生舱让 PM 不答也能推进 = 规则形同虚设。memory `feedback_open_questions_gate.md` 已禁。 |

---

## §3 实施指南

### §3.1 SKILL 顶部加引用

每个用 AskUser 的 skill 顶部加：

```markdown
> **PM 答题规则（M4）**：本 skill 所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 3 硬规则走（空答 STOP / 没拿到答案禁止落盘 / runtime 退化保留 wait）。**禁止默认走 recommend 分支 / 禁止逃生舱**。
```

### §3.2 闸门类 AskUser 模板（结合 banner-rules.md §3 Decision gate）

闸门 AskUser 同时遵守两份规则：
- **askuser-rules.md §1**：答题行为（空答 / 落盘 / runtime）
- **banner-rules.md §3**：选项 label / description / Loop 3 硬规则

两者**互补不冲突**：banner-rules 管"问什么"，askuser-rules 管"答什么时做什么"。

### §3.3 未决问题闸门特殊约束

未决问题闸门（_shared/project-questioning.md §4）= AskUser 的一种 + 暂存文件 + 闸门脚本三层防守。**askuser-rules §1.2 落盘禁止**对它仍然生效（PM 没答完所有未决问题前，不能写 PROJECT.md / prd.md）。

---

**End of askuser-rules.md**（M4 单一真相源； 实施）
