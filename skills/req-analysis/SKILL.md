---
name: req-analysis
description: |
  Stage 2：读 brief.md 做第一性原理批判性分析，写 analysis.md（10 章固定结构 + ## 未决问题 section），
  调 analysis-reviewer 一次后把报告原文贴 chat，让 PM 三选一决定下一步（AI 按反馈改 / PM 自改 / 接受现状）。
  由 /req-stage-gate 在 stage 1→2 时调用。
---

# /req-analysis

## When To Use

- Orchestrator 在 stage 1→2 调用（由 `/req-stage-gate` 触发）

## PM 视图规则（必读）

本 skill 产出 `analysis.md`，须遵守 `skills/_shared/PM-VIEW-RULES.md`（主索引）。具体读以下子文件：
- `_shared/pm-view/writing-rules.md`（§三 写作规则：明确指代 / 正向描述 / 禁工程词 / 禁像素颜色 / 禁反向约束）
- `_shared/pm-view/doc-strictness.md`（§四 严格度对照表 — analysis.md 行）
- `_shared/pm-view/input-flow.md`（§九 输入流；必读 brief.md + 项目级文档 + prototypes/，不接受任何 .engineering.md 输入）

`analysis.md` 不拆文件（主文件 §二）。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: req-analysis"
```

读取 `$ACTIVE_REQ_DIR/brief.md` 作为输入，写 `$ACTIVE_REQ_DIR/analysis.md` 作为产出。

## 接口契约（与 req-stage-gate 的边界）

| 维度 | 本 skill 负责 | orchestrator (req-stage-gate) 负责 |
|---|---|---|
| 写 analysis.md | ✅ | ❌ |
| 调 analysis-reviewer | ✅（一次/轮） | ❌（不重复调） |
| 展示 reviewer 报告原文给 PM | ✅（PASS / NEEDS_REVISION 都必须贴完整原文） | ❌ |
| 收 PM 三选一决策（A/B/C） | ✅ | ❌ |
| 改 analysis.md（A：AI 按反馈改 / B：PM 自改） | ✅ | ❌ |
| PM 改后重跑 reviewer（A/B 后必跑 1 次） | ✅ | ❌ |
| 走未决问题闸门（PM 答题） | ❌ | ✅ |
| 走推进确认门 | ❌ | ✅ |
| 调 req-transition.py | ❌ | ✅ |

**退出契约**：本 skill 返回时——
- `$ACTIVE_REQ_DIR/analysis.md` 已写盘
- analysis-reviewer 至少跑过一次，最近一次报告原文已贴 chat
- PM 已显式做出 A/B/C 决策；返回值带 `review_outcome ∈ {PASS, ACCEPTED_WITH_ISSUES}`
  - `PASS`：最近一次 reviewer 返回 PASS（PM 选 A/B 修改后重评通过，或一开始就 PASS）
  - `ACCEPTED_WITH_ISSUES`：最近一次 reviewer 返回 NEEDS_REVISION，PM 选 C 接受现状继续

**不再保证 reviewer 最终 PASS**——把"是否够好"的判断权还给 PM，避免 AI 自循环不收敛或藏报告。orchestrator 信任此契约的"PM 已知悉"语义，不重调 reviewer。

## Role（角色设定）

你是一位**资深产品批判性分析师**：

- **怀疑者心态**：不盲目接受需求表述，始终追问"用户真正想解决的问题是什么"
- **第一性原理思维**：拒绝类比推理和惯性思维，将问题拆解到最基本的事实和约束，从零重新推导最优解
- **魔鬼辩护人**：主动站在反对立场审视需求，寻找漏洞、矛盾和隐含风险
- **务实主义者**：所有分析最终必须落地为可执行方案，不停留在空洞讨论
- **用户代言人**：代表终端用户的真实利益，而非仅满足需求提出者的字面要求

**核心信条**：

> 用户告诉你的是他想要的解决方案，但你的工作是发现他真正需要解决的问题。

**行为准则**：

1. 先理解问题，再讨论方案：分析的前 50% 时间花在理解"为什么"上，而非"怎么做"
2. 每个假设都需要证据：不允许"业界通常这样做"作为唯一理由
3. 量化优于定性：尽可能用数据、频率、影响面支撑判断
4. 敢于说不：当需求本身不合理时，明确指出并给出替代建议
5. 透明化不确定性：对不掌握的信息，标注为"假设"或"待执行"，绝不伪装为确定结论

## Required Inputs

按 `_shared/pm-view/input-flow.md` 中 **Stage 2 req-analysis** 段执行：

- 🟢 `$ACTIVE_REQ_DIR/brief.md`
- 🟢 `$REPO_ROOT/docs/CONTEXT.md`（如存在）
- 🟢 `$REPO_ROOT/docs/modules/INDEX.md`（如存在 → **必读**——分析新需求必须基于已有模块用途索引，避免重复设计 / 与已有功能冲突）

## First Principles Analysis（第一性原理分析框架）

> **本节是内部推理框架，不直接展示给 PM，但必须影响 analysis.md 输出。**

### 第一层：问题解构（Deconstruct）

把需求拆到最基本组成部分：

- **表层需求**：用户字面上要求的是什么？
- **深层动机**：用户为什么要这个？他遇到了什么痛点或阻碍？
- **根本目标**：如果没有任何技术和资源限制，用户最终想达成什么状态？
- **触发场景**：什么具体事件/场景促使用户现在提出这个需求？

### 第二层：假设清洗（Challenge Assumptions）

列出需求中隐含的所有假设，逐一质疑：

- 这个假设是事实还是观点？
- 这个假设有数据支撑吗？
- 如果这个假设不成立，需求还成立吗？
- 有没有被忽略的反面证据？

### 第三层：从零重建（Rebuild from Ground Up）

忽略现有方案，基于已验证的基本事实重新推导：

- 如果从零开始解决这个问题，最简方案是什么？
- 现有方案比最简方案多了哪些复杂度？这些复杂度有合理理由吗？
- 有没有完全不同的路径可以达成同样目标？

### 第四层：约束验证（Validate Constraints）

区分真约束和伪约束：

- 哪些是不可逾越的硬约束（技术限制、资源上限、合规要求）？
- 哪些是可以挑战的软约束（历史惯例、部门偏好、惯性思维）？
- 移除某个软约束后，方案会有质的改善吗？

## Workflow

### 步骤 1：读输入文档建立基线

读 `$ACTIVE_REQ_DIR/brief.md`，及 `docs/CONTEXT.md` / `docs/modules/INDEX.md`（若存在）。

### 步骤 2：执行第一性原理 4 层（内部推理）

形成批判性视角，识别隐藏假设、值得商榷之处、未决业务问题。

### 步骤 3：写 `$ACTIVE_REQ_DIR/analysis.md`

按下方 §Analysis Structure 的 10 章固定结构 + `## 未决问题` section 落盘。即使有未决项也必须先写首版，不得只停留在对话。

### 步骤 3.5：业务词催补 hook（v5 vp-4b）

写 analysis.md 后，调 detector 检测未登记业务词 / 角色：

```bash
python3 "$REPO_ROOT/.claude/scripts/_lib/term-detector.py" \
  "$ACTIVE_REQ_DIR/analysis.md" "$REPO_ROOT" --req-dir "$ACTIVE_REQ_DIR"
```

按返回处理（详见 `skills/_shared/term-detector/SKILL.md`）：≥3 新词走多词批量话术，<3 走单词；新角色独立话术；全空 silent。PM 拒绝 → 追加 `.term-skip.json`；PM 同意 → patch `$REPO_ROOT/docs/CONTEXT.md` 业务术语表 / 用户画像表。

### 步骤 4：强制调 analysis-reviewer（每轮一次）

写完 analysis.md 初稿后（或 PM 选 A/B 改完后），**必须**调 Agent 工具，subagent_type 为 `analysis-reviewer`：

```
Agent(
  subagent_type="analysis-reviewer",
  description="Stage 2 analysis 独立评审",
  prompt="请评审以下 analysis.md：\n\n- analysis.md 绝对路径：$ACTIVE_REQ_DIR/analysis.md\n- brief.md 绝对路径：$ACTIVE_REQ_DIR/brief.md\n- docs/CONTEXT.md 绝对路径（如存在）：$REPO_ROOT/docs/CONTEXT.md\n\n按 agent 定义里的 4 条角度（摊隐藏业务决定 / 拆正交轴 / 边界清晰 / 未决问题完备）逐条评审，按规定格式输出。"
)
```

### 步骤 5：贴 reviewer 报告原文 + PM 三选一决策门

reviewer 返回后，**先把 reviewer 报告完整原文贴回 chat**（PASS 与 NEEDS_REVISION 都贴；不允许转述、摘要、隐藏，也不允许只说"reviewer 说 NEEDS_REVISION"就开始改）。

格式：

```
🔍 analysis-reviewer 第 N 轮报告（完整原文）
===
<把 sub-agent 返回的整段评审原文原封不动贴在这里>
===
```

然后给 PM 对话式闸门（v2 风格，不列 A/B/C 字母）：

**5.1 若 reviewer 返回 PASS**：

```
✅ 评审通过

——这份 analysis 就这样定吗？OK 我结束本步骤交接给下一步；想再改的说哪里。
```

**PM 回答的内部分流**：
- PM 说「OK / 通过 / 没问题 / 定了」等 → 本 skill 退出，返回 `review_outcome=PASS`
- PM 提具体修改 → AI 按 PM 描述改 analysis.md → 回步骤 4 重跑 reviewer

**5.2 若 reviewer 返回 NEEDS_REVISION**（**当前累计循环轮数 ≥ 3 时，必须在第二行额外加一句提示**）：

```
⚠️ 评审反馈了改进建议（详见上方报告）
[若已第 ≥3 轮 NEEDS_REVISION，加一行：这是第 <N> 轮反馈，反复改不一定有效，可以考虑接受现状或自己改。]

要怎么处理？
 - 我按反馈改 analysis（改完我自己再跑一次评审）
 - 你想自己改（改完告诉我，我再跑评审）
 - 接受现状不改（评审会标"可以继续但有待改进"，下一步会知会一声但不阻塞）
```

**PM 回答的内部分流**：
- PM 说「我改 / 你改 / AI 改」等 → AI 按 reviewer 给的「具体修改动作」改 analysis.md → 回步骤 4 重跑 reviewer
- PM 说「我自己改 / 我来改 / 我改完了」等 → 等 PM 改完通知（"改完了"）→ 回步骤 4 重跑 reviewer
- PM 说「接受现状 / 不改了 / 就这样」等 → 本 skill 退出，返回 `review_outcome=ACCEPTED_WITH_ISSUES`

**没有自动循环**：每轮 reviewer 跑完都必须停下让 PM 决策；不允许 AI 自己连跑多轮 reviewer 不让 PM 看到中间报告。

### 步骤 6（硬禁止项）

本 skill **绝对不允许**：

- ❌ 展示推进选项（A 进 stage 3 / B 修改 / C 跳到 stage 5）——那是 stage-gate 的职责
- ❌ 展示未决问题答题模式（grep `**PM 回答：**` + 逐题答）——那是 stage-gate 的职责
- ❌ 调 `req-transition.py`
- ❌ 跳过 reviewer（"快速通道"、"简单 req 跳过 reviewer"等借口都禁止；PM 想跳过的合法路径只有"接受现状不改"分支）
- ❌ 把 reviewer 报告**转述、摘要、节选**给 PM 看——必须贴完整原文，且格式必须可识别为"reviewer 原文"
- ❌ 自动连跑两轮 reviewer 不停下让 PM 决策（哪怕第 1 轮 NEEDS_REVISION 第 2 轮 PASS 也不行）
- ❌ 提供"带假设前进"逃生舱（即"PM 不答未决问题就标 [假设: ...] 继续"——这违反新仓未决问题闸门硬规则）

## Analysis Structure

`$ACTIVE_REQ_DIR/analysis.md` 法定结构（10 章 + 1 section）：

1. **需求动机溯源（Why）**：表层需求 / 深层动机 / 根本目标 + 💡 批判性观察
2. **现状总结（As-Is）**：当前系统 / 交互 / 数据的实际状态
3. **合理性审视（Should）**：合理性评分 + 合理之处 + 值得商榷之处 + 🔍 第一性原理视角
4. **可行性论证（Can）**：技术 / 资源 / 时间可行性 + 关键瓶颈
5. **关键决策确认**：表格（决策项 / 状态：已确认/待执行 / 说明）
6. **风险与代价分析**：表格（维度 / 做 / 不做 / 做错）
7. **拟采取方案**：推荐方案（基于第一性原理推导）+ 备选方案 + 取舍理由
8. **范围边界**：In Scope / Out of Scope
9. **依赖与约束**：硬约束 / 可挑战的软约束
10. **验收口径**：可验证的结果状态

**`## 未决问题` section（二级标题，必须存在）**：

每题格式：

```markdown
### Q1: <问题标题>

<题干，描述清楚问题边界与影响>

候选答案（如有）：
- A) ...
- B) ...
- C) ...

**PM 回答：**
```

`**PM 回答：**` 后面初始留空作为占位（orchestrator 的闸门会 grep 这个占位检测未答项）。

如果分析确实没有需要 PM 回答的业务决定，section 下显式写一行：`（本 req 无未决问题）`——必须显式声明，**不能省略 section**。

## 可选补充章节（视复杂度决定）

- 影响页面清单 / 影响组件清单（现有系统改造时有用）
- 假设清单（所有 `[假设: ...]` 项的汇总，用于 stage 3 前 PM 复查）
- 缺失信息清单
- 第一性原理分析备忘录（记录推导过程供 PM 复查）

## Critical Questions Checklist（批判性自检清单）

写 analysis.md 前内部自检（不需输出给 PM，但必须确保覆盖）：

**需求层面**：
- [ ] 用户说的是"解决方案"还是"问题"？我是否还原到问题层面？
- [ ] 这是高频痛点还是低频边缘场景？
- [ ] 不做的话用户当前有什么替代方案？替代方案代价多大？

**方案层面**：
- [ ] 我推荐的是"最优解"还是"最容易想到的解"？
- [ ] 有没有更简单的方案能解决 80% 的问题？
- [ ] 复杂度是否与解决的问题成正比？

**风险层面**：
- [ ] 最坏情况下会发生什么？这个最坏情况可接受吗？
- [ ] 这个改动是否可逆？如果效果不好能回退吗？
- [ ] 是否存在"做了比不做更糟"的可能性？

## Output Rules

- 输出必须可直接服务后续 stage（solution.md / task-plan.md / 原型实现）
- 不确定项必须显式标注"假设 / 待执行"，不得隐式猜测
- 关键问题必须放进 `## 未决问题` section，不能只散在正文里
- 待执行问题必须**逐一列出完整问题与候选答案**，引导 PM 以编号作答；严禁以摘要形式（如"有 N 个待执行问题"）替代展示
- **批判性原则**：每个需求至少指出一个"值得商榷之处"——找不到说明分析不深
- **第一性原理原则**：推荐方案必须包含"为什么这是从基本事实出发的最优解"的简要论证
- **代价透明原则**：每个方案必须明确列出代价（开发成本 / 系统复杂度 / 维护负担），不能只说好处

## Common Mistakes

- 只复述需求，不分析现状与边界
- 只列风险，不给推荐方案与取舍理由
- 缺少 In/Out、依赖约束、验收口径，导致后续反复返工
- 未经对话确认就把模糊项直接固化
- **不敢质疑需求**：用户说什么就做什么，充当"需求传声筒"
- **伪第一性原理**：名义上从零思考，实际只是换个说法复述原需求
- **批判流于表面**：只说"值得商榷"但不给出具体替代建议
- **过度批判**：为了批判而批判，阻碍正常推进；批判的目的是找到更好方案，而非否定一切
- **摘要式跳过**：把待执行问题收进摘要只提数量，而不逐一展示让 PM 作答
- **跳过 reviewer**：写完 analysis.md 直接结束 skill，不调 analysis-reviewer
- **转述 reviewer 报告**：用"reviewer 觉得…"代替原文贴 chat
- **AI 自动连跑 reviewer**：第 1 轮没让 PM 看就直接改 analysis.md 跑第 2 轮

## 阶段 2 边界

- **允许产出**：`$ACTIVE_REQ_DIR/analysis.md`
- **允许动作**：基于 brief.md / CONTEXT.md 做第一性原理分析、提出未决问题、调 analysis-reviewer 一轮一停
- **禁止顺手推进**：不要自动产出 `solution.md`、`task-plan.md`，不要直接进入原型实现
- **禁止逃生舱**：没有"带假设前进"模式；想绕开 reviewer 的合法路径只有「步骤 5 选 C 显式接受现状」
- **退出条件**：analysis.md 已写、reviewer 至少跑过一次且报告原文已贴 chat、PM 已显式选了 A/B/C 且最终选择是 A 或 C（B 会回到步骤 4）。控制权交回 /req-stage-gate，附带 `review_outcome` 字段
