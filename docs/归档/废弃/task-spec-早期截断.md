# 设计：task-003 双轮废根因分析（原文件名「task-spec 早期截断」是错诊断遗留）

> 状态：设计中（PM 走查后决定实施方向）
> 创建：2026-05-09 / 重写：2026-05-09（错诊断纠偏后）
> 触发：DX 审计 P0-7（活体证据：req-001 task-003 v1+v2 双轮废）

## 历史：第一版错诊断（2026-05-09 上午）

第一版本设计（commit `f5ff128`）把根因诊断为「task-plan 拆分粒度过粗（task-003 v2 含 6 段独立可 demo 业务流）」，推荐方向 A 加 task-plan 反模式 F。

**错在哪**：
- 我看 GSTACK Eng 8/10 + Design 9/10 PASS 误以为 review 完整 → 其实那是 **plan 阶段** review（task-spec 之前），不是 **实施完之后** 的 review
- task-003 v1 PM 反馈第一条原话："`/qa` 是否完整走了流程；页面看到很多问题 + 一个报错"——明明白白告诉了我"实施后 review 缩水"，我读到了字面但没读懂语义
- 跳过了"原型结构"这条线索（PROTOTYPE_CLEANUP.md 在仓库根目录就摆着）

**保留这一段** 作错误诊断复盘档案——后续 AI / PM 复盘时能看到这种错路是怎么走的。**不应再按方向 A（反模式 F）实施**。

PM 在 chat 给的纠偏：
> 单 task 拆得粗我不认同，更重要的原因是最后的原型实现质量很差，我觉得有两个原因：第一是之前的原型结构太复杂，第二是当时原型开发完，AI 走 review 的时候，没有用完整 skill。

---

## 一、真根因（基于 PM 纠偏 + 活体证据）

### 1.1 根因一：原型结构太复杂（task-execute 在乱原型上学错样）

**时间线证据**：
- task-003 v1：2026-04-28 实施（v1 废）
- task-003 v2：2026-05-06 实施（v2 废）
- PROTOTYPE_CLEANUP B1：在 v2 之后开始（commit `d044c13` 起；最终 B8 在 commit `125e6a6` 标 2026-05-01 大清理收尾）
- 也就是 task-003 v1 + v2 跑的时候，**原型还是没清理的老结构**

**老原型结构**（PROTOTYPE_CLEANUP.md §砍 列出来的）：
- `framework/page/` 的 Template 系（ListPageTemplate / FormPageTemplate / DetailPageTemplate / SettingsPageTemplate / AuthPageTemplate / PlaceholderPage / PageHeader / PageSection）
- `framework/hooks/`（useListPage / useFormSubmit / useConfirmDialog）
- `framework/context/`（TenantContext / AppContext）
- `framework/utils/form-utils.ts`
- `modules/*/pages/`（业务功能拆到模块层）
- `modules/*/lib/`（store / permission / scope-utils 业务逻辑）
- `modules/*/mock/` 多版本残留

**为什么导致实现质量差**：
- task-execute 步骤 2.1 prototype 是 **全文 Read 实现参考**（写新页面"长一样"），AI 学的是当时的样
- 老结构是 framework template / hooks / context 多层抽象串数据；AI 在多层抽象上写代码 → 不一致命名 / 死代码 / 多版本残留 / "改一页要动多个文件" 的耦合 → 原型 demo 出来质量低
- 拍平后规则："**self-contained**：所有 UI、状态、假数据都在 page.tsx 一个文件里 / 不靠 framework hooks/context/store/template 串数据"——B1-B8 拍平后 −25,123 行净删

### 1.2 根因二：原型实施完，AI 走 review 时 skill 缩水（没像真用户操作）

**v1 task-003 PM 反馈第一条（2026-04-28）**：

> **问题描述：** /qa 是否完整走了流程；页面看到很多问题 + 一个报错
>
> **处理结果：** 已处理 — orchestrator 自审 2/3 实际只跑了简化版 smoke + 截图，**没像真用户一样填表提交**。立即补跑 /qa（自审 4），找到 2 个 CRITICAL bugs（CR-001 mock invariant 沉默 rollback / CR-002 Tab 3 全白）+ 4 个 deferred findings (F-008/9/10/11)，CR-001/CR-002 已 auto-fix，待第二轮 commit。

也就是说 task-execute 阶段 agent 跑的"/qa 自审"是"简化版 smoke + 截图"，跑了等于没跑。补跑完整 /qa 立刻找出 2 个 CRITICAL bug。

**v3.5 后变化**（I-RV1 / I-RV2 / I-RV3 invariants）：
- I-RV1：AI 不得自动调任何 review skill（防止 task-003 v1 那种 "orchestrator 自审跑 /qa 但缩水" 反模式）
- I-RV2：事件流缺 review_completed 不阻止「执行中→已完成」转换（PM 自跑结论自决）
- I-RV3：PM 报告 review 结论后才 append 事件，禁止 AI 替 PM 跑或凭记忆模拟

I-RV1 关掉了 AI 自跑路径——但**没救** PM 自跑时跑得不完整的情况：
- task-execute 步骤 11 验收信息块末尾「⚙️ 可选深度审查」是辅助提示，PM 自取所需
- PM 自己跑 /qa 时若没认真填表，只跑简化 smoke，AI 不知道
- 「PM 跑了 /qa 报 PASS」≠「PM 完整跑了 /qa」——后者要求真用户多步流操作 / 填表提交

### 1.3 两条根因如何串联到 task-003 实现质量差

```
原型结构复杂（framework template / hooks / context 多层抽象）
   ↓
task-execute 全文 Read 学错样 → 实现耦合多层 → 多页改才能动一个功能
   ↓
原型 demo 出来质量低（AI 不一致命名 / 死代码残留 / 流断点）
   ↓
review 阶段 PM 自跑 /qa 但缩水（简化 smoke）→ 没找出问题
   ↓
PM 验收时才发现"质量很差"→ 打回 → AI 改 → 再打回 → ...
   ↓
task-003 v1 全废 → v2 重做 → 仍废
```

两条根因独立但叠加：
- 原型结构复杂 → 输入污染 → 实现质量先天受限
- review skill 缩水 → 检查滤网漏洞大 → 质量问题没在 review 阶段被截住

---

## 二、方向 1：防原型结构污染（根因一）

### 2.1 现状能力

`init-project` + 4.5d 改造已落地：
- `CLAUDE.md` 「## 工程结构约束」段（init-project 注入 prototype / system / custom 三档）
- prototype 档明文："self-contained / 改一页只动一个文件 / 加一页 = 复制一个旧页"
- task-spec 步骤 9 §5 实现指引由 A 层（项目级 CLAUDE.md）+ B 层（req 级 solution「本轮实现深度变更」）prose 合并

**漏洞**：CLAUDE.md 注入是 init-project 时一次性的；如果 PM 后续手动建了新 framework 抽象层，框架不知道。task-003 时期是不是 CLAUDE.md 已注入还是未注入需要查 git log；即使注入了，也没机制阻止原型回到老结构。

### 2.2 方向 1A：task-execute 步骤 2.1 prototype 污染检测（推荐）

**做什么**：
- 在 task-execute 步骤 2.1 全文 Read prototype 时，AI **机械跑**一次结构启发式：

```bash
# 启发式检测原型结构污染
PROTOTYPE_ROOT="$(grep -A1 '^## 工程结构约束' CLAUDE.md | grep -oE 'prototype-root: \K\S+' | head -1)"
[ -z "$PROTOTYPE_ROOT" ] && PROTOTYPE_ROOT="prototypes"

WARN=()
[ -d "$PROTOTYPE_ROOT/framework/page" ] && \
  ls "$PROTOTYPE_ROOT/framework/page" | grep -qE 'Template|PageHeader|PageSection|Placeholder' \
  && WARN+=("framework/page/ 含 Template 系（建议 self-contained）")
[ -d "$PROTOTYPE_ROOT/framework/hooks" ] && WARN+=("framework/hooks/ 存在（pages 不应靠 hooks 串数据）")
[ -d "$PROTOTYPE_ROOT/framework/context" ] && WARN+=("framework/context/ 存在（pages 不应靠 context 串数据）")
find "$PROTOTYPE_ROOT/modules" -type d -name "pages" 2>/dev/null | head -1 | grep -q . \
  && WARN+=("modules/*/pages/ 存在（pages 应在 app/ 不在 modules/）")
find "$PROTOTYPE_ROOT/modules" -type d -name "lib" 2>/dev/null | head -1 | grep -q . \
  && WARN+=("modules/*/lib/ 存在（业务逻辑串到 lib，pages 难自包含）")
```

**触发条件**：任一 WARN 命中 → AI 在步骤 2.1 末尾输出告知 PM：

```
⚠️ 原型结构污染检测命中 N 条：
- framework/page/ 含 Template 系
- modules/*/lib/ 存在
- ...

历史教训（req-001 task-003 v1+v2 双废）：原型结构有多层抽象时，task-execute
学错样、实现耦合、demo 质量低；建议先跑原型清理（参考 PROTOTYPE_CLEANUP.md
拍平规则）再继续 task-execute；或 PM 显式接受现状（写到 chat），AI 继续。
```

**PM 决策（不机械阻断）**：PM 选「先清理」→ task 暂停，提示 PM 跑清理后回来；PM 选「接受现状」→ task-execute 继续。

**为什么不机械阻断**：原型结构污染是**项目运营**问题，不是 task 级问题；PM 可能有自己的清理节奏，框架不替决。但 AI 必须**主动告知**——这是 v3.5 没做的。

### 2.3 方向 1B：依赖 init-project + 不加新机制（不推荐）

- 现有 CLAUDE.md prototype 档已经把规则写在那
- 让 PM 自己运营原型清理（如 req-001 close 后跑 PROTOTYPE_CLEANUP）
- 不加机制 → 下次再发生原型污染 → 再次 task-003 type 事故

**风险**：N=1 已经 8 天浪费 + 1 个 req 跳 prd-writing。N=2 不可承受。

### 2.4 方向 1A 实施细节

文件位置：`skills/task-execute/SKILL.md` 步骤 2.1 后追加 §2.1.1「原型结构污染检测」。

启发式实现：抽到 `scripts/check-prototype-structure.py`（参考现有 `scripts/check-doc-pm-view.py` 模式），由 task-execute SKILL 步骤 2.1.1 mechanically 调用。

测试：`tests/test-check-prototype-structure.sh` + `tests/e2e/test-prototype-pollution-warn.sh`。

---

## 三、方向 2：防 review skill 缩水（根因二）

### 3.1 现状能力

- I-RV1 / I-RV2 / I-RV3：AI 不得自动调 review / PM 自跑 / 事件 append 仅在 PM 报告后做
- task-execute 步骤 11 验收信息块末尾「⚙️ 可选深度审查」列了 `/review` `/qa` `/design-review`
- 步骤 11.1 PM 跑完 review 后 AI 调 `task-events.py append` 机械记录

**漏洞**：
- 「PM 跑了 /qa」→ 「PM **完整跑了** /qa」之间没有判别
- task-003 v1 时期"orchestrator 自审跑了简化版 smoke + 截图"——orchestrator 自跑现已被 I-RV1 禁；但 PM 自跑时若 PM 没像真用户操作，AI 不知道、不提醒
- 现行 I-RV3 禁止 AI 替 PM 跑或凭记忆模拟——但**没规定 AI 在 PM 报结论时追问完整性**

### 3.2 方向 2A：步骤 11 验收信息块加 review 完整性判别标志（推荐）

在 task-execute 步骤 11.2 输出验收信息块的「⚙️ 可选深度审查」段，每个 review 工具旁边加完整性提示：

```
⚙️ 可选深度审查（PM 自取所需，非必跑）：
  /review              — 代码审查 task 分支 vs req 分支的 diff
                         ✓ 完整跑：覆盖所有变更文件 / 标 P0-P2 finding / 给修复建议
  /qa                  — 功能测试 dev server（需 browse；UI task 推荐）
                         ✓ 完整跑：以真用户视角操作；填表/提交/多步流；含错误状态触发；
                                  不仅 smoke + 截图；可被 PM 复盘"我刚刚操作了 N 步"
  /design-review       — 对照 DESIGN.md 检查视觉一致性（需 browse；UI task 推荐）
                         ✓ 完整跑：覆盖所有 task 涉及页面 / 状态（含 hover / focus /
                                  disabled / loading / error）；按 DESIGN.md 章节逐条对照
跑完贴结论我会机械追加自审记录 + append 事件（I-RV3）。
```

**为什么是提示而不是强制**：
- I-RV1/2/3 把决策权留给 PM；强制完整性 = AI 替决，违背 invariant
- 提示让 PM 知道"完整跑"长什么样，PM 自己决定走简化版还是完整版（如果是 hotfix 缩水可接受、如果是大改必须完整）

### 3.3 方向 2B：步骤 11.1 AI 追问 review 强度（半推荐，需权衡）

PM 报告 review 结论后，AI 在 append 事件前**追问一句**：

```
PM 您说 /qa pass，是否完整跑（真用户操作 / 填表提交 / 多步流）？
- A 完整跑了 → AI append 事件（result=pass，coverage=full）
- B 简化跑了（smoke + 截图）→ AI append 事件（result=pass，coverage=smoke），
  并提醒「historical evidence req-001 task-003 v1：smoke 漏掉 2 CRITICAL bugs」
- C 我重新跑一下完整版 → AI 等 PM 跑完再 append
```

**收益**：把 task-003 v1 那种"AI 知道 PM 跑了简化版但没纠正"的盲区填掉。

**风险**：可能踩 invariant memory feedback「skill 必须实际调用，不能凭记忆模拟」边界——AI 在追问完整性时若 PM 答 "完整" 但实际不完整，AI 仍 append `coverage=full`，等于 AI 替 PM 担保 review 完整性。这违背 I-RV3 精神（PM 自负 review 结论）。

**化解**：把 coverage 字段定义为 **PM 自报告，AI 不验证**；append 事件如实记录 PM 自报值；后续若再出 task-003 type 事故，事件流可追溯到"PM 自报 full 但实际 smoke"。

### 3.4 方向 2C：增 I-RV4「完整性提示但不监督」（最轻量）

I-RV4：AI 在 task-execute 步骤 11.2 输出完整性判别标志（方向 2A），不在步骤 11.1 追问（不做方向 2B），不替 PM 验证 review 完整性。

PM 自负 review 完整性。AI 只承担"提示 PM 完整跑长什么样"职责。

**收益**：最轻；方向 2A + 加一条 invariant 把"AI 不监督"显式化（防止未来 AI 自动加监督逻辑反向打破 I-RV1）。

**成本**：约 0.5 天（只改 SKILL.md + 加 invariant 描述 + 测试）。

---

## 四、综合方向对比

| 方向 | 根因 1 防御 | 根因 2 防御 | 成本估计 | 推荐度 |
|---|---|---|---|---|
| 1A + 2A + 2C | ✅ 检测告知 | ✅ 完整性提示 | 1.5 天 | 🌟🌟🌟 推荐 |
| 1A + 2B | ✅ 检测告知 | ✅ AI 追问 | 1.5 天 | 🌟🌟（追问可能踩 I-RV3 边界）|
| 1A 单做 | ✅ 检测告知 | ❌ 不动 | 1 天 | 🌟（只填一半根因）|
| 2A 单做 | ❌ 不动 | ✅ 完整性提示 | 0.5 天 | 🌟（只填一半根因）|
| 不实施 | ❌ | ❌ | 0 | 0（N=1 实证不可承受 N=2）|

**推荐 1A + 2A + 2C**：
- 1A 命中根因一（输入污染检测）
- 2A 命中根因二（review 完整性判别标志）
- 2C 把"AI 不监督"显式化为 invariant，闭环保护 I-RV1
- 总成本 1.5 天，对齐续接 doc 给 P0-7 的 1-2 天预算

---

## 五、实施细节（PM 选 1A + 2A + 2C 后展开）

### 5.1 方向 1A 落地

- 新建 `scripts/check-prototype-structure.py`：启发式扫 framework/page Template / framework/hooks / framework/context / modules/*/pages / modules/*/lib，输出 WARN 行
- `skills/task-execute/SKILL.md` 步骤 2.1 后追加 §2.1.1「原型结构污染检测」：调脚本 + 告知 PM + PM 决策门
- `tests/test-check-prototype-structure.sh`：用 fixture 跑 happy path（无污染）/ 全命中（5 类污染）
- `tests/e2e/test-prototype-pollution-warn.sh`：模拟 task-execute 调用，验证 WARN 输出 + PM 决策路径

### 5.2 方向 2A 落地

- `skills/task-execute/references/acceptance-handoff.md` 步骤 11.2 输出模板加完整性判别标志行
- `skills/task-execute/SKILL.md` Rules 段加 I-RV4 引用
- `tests/test-task-execute.sh`（如有）加 assertion：步骤 11.2 模板含「完整跑」字样 + 历史教训引用

### 5.3 方向 2C 落地

- 在 `skills/task-execute/SKILL.md` Rules 段或单独 invariants 节定义 I-RV4：
  - "AI 在 task-execute 步骤 11.2 输出 review 完整性判别标志（提示 PM 完整跑长什么样），不在步骤 11.1 追问，不替 PM 验证 review 完整性。PM 自负 review 完整性结论。"
- 同步 INVARIANTS.md 主索引（如果有 I-RV 集中定义页）

### 5.4 文档更新

- 续接 doc 标 P0-7 完成 + commit hash
- skill-feedback/task-plan-2026-05-09.md（可选）：复盘"我把根因诊断错了，PM 纠偏后重新挖"——给未来 AI 一个反例（防止再犯"看 GSTACK PASS 就以为 review 完整"错路）

### 5.5 不在本设计范围

- gstack `/qa` skill 自身的执行强度（外部 skill，不在本框架职责）
- prototype 清理本身（PM 运营动作，PROTOTYPE_CLEANUP.md 已经留下经验档案）
- task 拆分粒度（第一版错诊断方向，已撤回；现有反模式 A-E + 启发式启发足够）

---

## 六、PM 决策表

| 决策项 | 选项 |
|---|---|
| **方向选择** | 1A + 2A + 2C（推荐）/ 1A + 2B / 1A 单做 / 2A 单做 / 不实施 |
| **如选 1A**：污染检测启发式列哪几类？| 默认 5 类（framework/page Template / framework/hooks / framework/context / modules/*/pages / modules/*/lib）/ 可补 modules/*/mock 多版本 / 可减|
| **如选 1A**：检测命中后是 WARN 还是阻断？| WARN 告知 PM + 决策门（推荐，不阻断）/ 阻断 task-execute（PM 必须先清理）|
| **如选 2A**：完整性提示是写在 acceptance-handoff.md 还是另开文件？| 写到 acceptance-handoff.md 步骤 11.2（推荐，与现有结构一致）/ 抽到 references/review-completeness.md|
| **如选 2C**：I-RV4 写到哪？| `skills/task-execute/SKILL.md` Rules 段（推荐）/ 抽到独立 invariants 文档|
| **是否补 skill-feedback/task-plan-2026-05-09.md 复盘？** | 写（推荐，给未来 AI 反例）/ 不写|
| **commit 切分** | 单 commit（推荐，三方向耦合度高）/ 拆 1A / 2A / 2C 三 commit|

---

## 七、错误诊断复盘（不要删，AI 反例档案）

第一版本（commit `f5ff128`）方向 A「task-plan 反模式 F 扩容」错路总结：

| 错路环节 | 错在哪 | 应该怎么做 |
|---|---|---|
| 看 GSTACK 8-9/10 PASS | 误以为 review 完整 | 区分 plan 阶段 review vs 实施后 review；GSTACK Eng/Design 是前者 |
| 读 task-003 v1 PM 反馈 | "/qa 没完整跑"读到字面没读懂语义 | PM 反馈第一条是 highest signal，逐字读懂 |
| 跳过 PROTOTYPE_CLEANUP.md | 仓库根目录就摆着，没注意 | task 双轮废诊断必须扫仓库根目录所有 *.md（特别是 CLEANUP / TODO / DECISION 类）|
| 推荐方向 A 反模式 F | 把症状（demo 多段）当根因 | PM 第一次说"不合理"立即停止当前方向重新挖（memory feedback "根因优先"）|

PM 在 chat 反驳后 30 秒内承认错诊断 + 重新挖证据 = 正确响应；不要找补、不要"我看一下"绕弯子。
