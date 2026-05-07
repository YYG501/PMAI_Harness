<!-- 状态：讨论中 | 未定稿 | 创建时间：2026-04-25 -->

> ⚠️ **历史设计备忘 — 部分内容已被 §5.1 当前格式替代**
>
> 本文档中描述的「三级功能块 = `### N` + 3 列表（二级 / 三级 / 使用角色）+ 表外编号需求列表」格式，已被 commit `d4024eb`（2026-04-28）废弃。
>
> 当前正解在 `skills/_shared/PM-VIEW-RULES.md` §5.1：
> 「N · 功能名 + 可选 `> **使用角色**：` blockquote + 4 列表格（二级 / 三级 / 使用角色 / 需求描述）+ 续行 rowspan + 需求描述列内联编号」。
>
> 3 列表相关章节（§423–432 的 task 模板示例 / §470 doc-update 沉淀格式）保留作为历史记录；与 task-plan / task-spec / doc-update 实际行为对照请以 `skills/_shared/PM-VIEW-RULES.md` 为准。

# Stage 5 / 6 重设计：task 循环 + 模块规格 living doc

## 背景

req-001 实操暴露出当前 stage 5（`/task-plan`）的两个根本问题：

1. **模块规格被设计为事前对账层，但 PM 看不进去也对不上**
   - 当前 SKILL.md 要求 stage 5 step 2/2.5 先按 `module.md.tmpl` 生成 `docs/modules/<module>.md` 作为 task 拆分前的中间层
   - req-001 实际跳过了这步，直接从 solution.md 拆 task → task 与 solution 之间没有对账层 → task-003 V2/V3/V4 反复偏差只能靠人肉验收时撞出来
   - 即使按规范做，PM 在还没有原型可对照时也不会真正认真审模块规格

2. **task-plan 一次生成所有 task 文件不可靠**
   - 单会话窗口同时考虑 10 个 task → 注意力分散、每个 task 半成品
   - 实际产出格式漂移，没按 template 走
   - 单 task 生成时拉的上下文不足

## 核心设计原则

**模块规格不是事前对账层，是 task 验收后的累积产物（living doc）。**

PM 真实的工作方式：
1. 看 task 文档（含所属模块、功能清单、user story）确认要做什么
2. task 执行 → 看原型验收
3. 不通过 → 改 task 文档（功能清单 / user story）+ 改原型 → 再验收
4. 通过 → 该 task 的功能清单沉淀进 `docs/modules/<module>.md`，作为模块规格的一部分
5. 所有相关 task 完成后，模块规格自然长齐

**task 是 PM 的主交互单元**——所以 task 文件本身要 PM 看得懂；模块规格随 task 验收增量累积。

## 已确认的设计决定

### 1. 模块规格定位

- **从**：stage 5 事前生成的对账层
- **到**：stage 6 task 验收完成后增量累积的 living doc
- **merge 时机**：每个 task 验收通过的瞬间
- **merge 分支**：当前 req 的 worktree 分支（A 方案）。req 整个完成、PR 合回 main 时模块规格才进主线。多 req 并行 → 后合的解冲突（git 标准模式）。req 中途废弃的丢失风险用"废弃前必须显式收尾"兜，不靠分支策略兜。

### 2. task 文件结构（PM 看得懂的版本）

每个 task 文件至少包含：

- 所属模块（一个或多个）
- 该 task 涉及的功能清单
- user story
- 原型验收点
- 启动前必读 / 实现指引（保留现有机制）

### 3. stage 5 / 6 职责重新划分

**stage 5 = `/task-plan`**

- 输出：`task-plan.md`（总览 + task 标题列表【含 id / 标题 / 所属模块 / 一句简述】+ 执行顺序 + 风险）
- PM 确认门：颗粒度、顺序、是否漏掉模块
- **不**生成任何具体 task 文件

**stage 6 = 每个 task 一个完整子循环**

1. 读 task-plan.md 取下一个 task
2. `/task-spec <task-id>` 生成详细 task 文档
   - 拉相关 solution 节
   - 拉所属模块当前 `docs/modules/<module>.md` 状态
   - 拉已完成的上游 task
   - 按 `task.md.tmpl` 写：所属模块 / 功能清单 / user story / 原型验收点 / 启动前必读
3. PM 确认 task 文档
4. 执行（代码 + 原型）
5. PM 看原型验收
   - 不通过 → 改 task 文件的功能清单/user story + 改原型 → 回到 5
   - 通过 → 进入 6
6. merge 该 task 的功能清单进当前 worktree 分支的 `docs/modules/<module>.md`
7. 回到 1，直到所有 task 完成

**额外好处**：第 N 个 task 的详细文档生成时，能看到第 1～N-1 个 task 已沉淀进模块规格的内容——上下文是渐进的、最新的，天然规避"前面 task 改了模块、后面 task 还按旧设想拆"的偏差。

## 改动清单

> 重要：现状 stage 6 已经有完整的 5 个 skill 闭环（`/task-confirm` → `/task-execute` → `/task-submit` → `/doc-update` → `/close-task`），不需要新拆 skill。新设计**只需要新增 1 个 + 修改 1 个**，其他全部复用。

1. `.claude/skills/task-plan/SKILL.md`
   - 删 step 2 / 2.5（事前模块规格）
   - 删 step 5（不再批量生成 task 文件）
   - 改成：solution → task-plan.md（含 task 标题列表）→ PM 确认推 stage 6

2. **新增** `.claude/skills/task-spec/SKILL.md`
   - 单 task 详细文档生成器
   - 输入：`<task-id>`
   - 输出：`tasks/task-NNN-*.md`
   - 拉相关 solution 节 + 所属模块当前 `docs/modules/<module>.md` 状态 + 已完成的上游 task → 按 `task.md.tmpl` 写

3. `.claude/templates/task.md.tmpl`（详见 Q6 决议）
   - 顶部加字段：所属模块 / 所属模块章节
   - 新增 section：用户使用流程 / 功能清单（三级功能块格式）/ 实现指引
   - 调整 section：验收标准（业务 task 可省，基础设施 task 必填）
   - 功能清单格式对齐参考文档 `Admin Console3/docs/功能规格文档/.../functions-v4.1.md`

4. `.claude/templates/module.md.tmpl`
   - 功能清单部分改用三级功能块格式（一级章节 + 表格 3 列 + 编号需求列表），对齐 task.md.tmpl
   - 确认结构能接收 task 功能清单**从无到有**累积写入
   - **不**维护实现指引 section（跟 `设计-功能规格文档增强.md` §8 不同，按本次决议简化）
   - 加填写规则：禁视觉细节、引向 DESIGN.md（同 task.md.tmpl）

5. **新增 `templates/DESIGN.md.tmpl` 的 §创意自由度 section**
   - 沿用旧仓 `pm-ai-workflow-template/docs/DESIGN.md` §创意自由度 写法
   - 三类清单：高自由度区域 / 低自由度区域 / 不可偏离

6. **改 `.claude/skills/doc-update/SKILL.md`**
   - 现状步骤 1.5/1.6 是"对照已存在的模块规格找偏差并回写"
   - 新设计扩展为"沉淀"：模块规格不存在时**新建**、存在时**累积写入功能清单**
   - 用 "所属模块章节 + 三级功能名" 作为复合 key 匹配（Q5）
   - 区分新增/修改/跳过/不动四种情况（Q5）
   - **多模块 task atomic merge**（A3 决议）：用 git 临时分支收集所有 module merge，任一失败 rollback 整个 commit
   - 失败一律阻塞 close-task（DB2）
   - 状态机不动，仍由 `/close-task` 内部触发 `/doc-update`

7. **改 `.claude/skills/req-stage-gate/SKILL.md` 的 stage 6 → 7 判定**（Q4）
   - task 列表以 task-plan.md 为准
   - 校验 "已 close"（隐含校验功能清单已 merge）

8. **改 `.claude/skills/task-plan/SKILL.md` 步骤 3 拆分逻辑**（Q1 衍生）
   - 3.1 加 "可归属" 原则
   - 3.2 加反模式 E
   - 3.3 加单模块软上限 3
   - 3.4 加自检第 5 条
   - 步骤 3 开头加颗粒度核心判定 + 端到端切片原则

9. **改 `.claude/skills/task-execute/SKILL.md`**（DX RU3）
   - PM 反馈处理分流：行为/规则修订 → 改 task 文档；bug → 只改代码
   - agent 一句话告知判断，PM 可驳回

10. **改 `.claude/skills/task-submit/SKILL.md`**（DX RU3）
    - 配合 task-execute 的 PM 反馈分流逻辑（共享分流策略）

11. **改 `.claude/skills/close-task/SKILL.md`**（DX RU6 + A1）
    - 末尾加轻量 auto-chain：完成后自动提示"下一个 task X，继续 (Y/n)"
    - 加 `--skip-doc-update` flag（A1 决议）：PM 可在 doc-update 永久失败时紧急 skip，必须写 reason 进 task 文档偏差 section，自动生成人工 cleanup TODO

### 落地节奏（plan-eng-review 决议）

分 3 批 PR 落地，每批独立 dogfood 验证：

| Batch | 内容 | 文件 | 落地后效果 |
|------|------|------|------------|
| 1（基础）| 模板改动 + 新 skill | 改动 #2/#3/#4/#5 | 新流程"形式上可跑"，旧 task-plan 步骤 2/2.5 还在（无副作用） |
| 2（流程切换）| 改核心 skill | 改动 #1/#6/#7/#8 | 新流程正式接管，breaking change |
| 3（DX polish）| DX 决议落地 | 改动 #9/#10/#11 | DX RU3/RU6 + A1 逃生舱落地 |

## 待确认的点

按讨论顺序，PM 逐个确认：

### Q1：横切性 task（脚手架 / 共用组件 / 跨模块重构）怎么处理？✅ 已确认

**采用 (a) 方案**：允许 task 标 `所属模块: 基础设施`，验收通过后**不**沉淀进任何 module 规格。

**判定"基础设施 task"的硬规则**：产出**不在任何业务页面/流程上直接可见**才算。

- ✅ 例：项目脚手架、共用 Button/Modal 组件库、API client、auth context、构建配置
- ❌ 例：登录页的"会话管理 hook"——服务于登录流程，归"登录页"模块，不是横切

基础设施 task 的事实如果需要长期沉淀，PM 自己决定要不要回写 `docs/CONTEXT.md` / `docs/DESIGN.md`，不强制。

#### Q1 衍生：task 拆分逻辑改造

当前 `task-plan` 步骤 3 的拆分原则没有"模块"维度，需要补三块：

**(1) 步骤 3.1 基本原则增加第 4 条**：

> **可归属**：每个 task 必须显式声明 `所属模块`，二选一：
> - 一个或多个业务模块（对应 `docs/modules/<module>.md`）
> - `基础设施`（按上面硬规则判定）

**(2) 步骤 3.2 增加反模式 E**：

> **反模式 E：业务功能 task 没有归属**
>
> - 例：task "实现产品访问管理列表页" 标 `所属模块: 基础设施`
> - 问题：业务功能不沉淀进 module 规格 → living doc 残缺
> - 判断：产出在任何业务页面/流程上**直接可见** → 必须归到对应业务模块；标"基础设施"只能用于真正横切（脚手架 / 共用组件库 / 构建配置 / API client / auth context 等）

**(3) 步骤 3.4 自检增加第 5 条**：

> 5. [ ] 这个 task 标的所属模块是否符合硬规则？业务功能 task 是否真的归到了业务模块（不是图省事标"基础设施"）？

#### Q1 衍生：task 颗粒度规则

**核心判定**：一个 task = PM 能在**一次原型 demo 里完整验收**的功能单元。

**业务模块 task 颗粒度**：

> 一个 task 对应 1-N 条**紧密相关**的功能清单条目。"紧密相关"判定：
>
> - 同一个 user story 链条（账号登录是一个链条；找回密码是另一个链条）
> - 或同一个页面区域可一次性 demo
>
> **不同 user story 链条即使在同一页面，也要拆成不同 task**（例：用户管理页的"列表筛选"和"批量导出"是两个 task）

**基础设施 task 颗粒度**：

> 每个 task 对应一类完整可用的基础能力（项目脚手架 / 共用组件库 / auth context / API client 等），不再细分

**端到端切片原则（与反模式 C 一致）**：

> task 必须按 user story **端到端切**（前端 + 后端 + 数据层捆绑），**不允许按技术分层切**（不允许"先 task-A 做数据层，再 task-B 做 UI"）。
>
> 没有 UI 的 task 没法做原型 demo → 自动违反"PM 一次原型验收"的颗粒度判定。

**两个软上限**（触发回头审查）：

| 信号 | 含义 |
|------|------|
| 单 req 总 task 数 > 7 | 沿用现有规则，怀疑踩反模式 |
| **单模块 task 数 > 3** | 新增：怀疑过细，比如把同页面的不同 user story 拆得太散 |

#### Q1 改动落点（覆盖前面 §改动清单 第 1 条）

`.claude/skills/task-plan/SKILL.md` 步骤 3 全面改写：
- 3.1 增加"可归属"
- 3.2 增加反模式 E
- 3.3 增加单模块软上限 3
- 3.4 增加自检第 5 条
- 在步骤 3 开头加颗粒度核心判定 + 端到端切片原则

---

### Q2：stage 6 子循环 skill 怎么组织？✅ 已确认

**复用现有 5 个 skill 闭环 + 只新增 1 个 + 改 1 个。**

#### 现状 stage 6 已有的 skill 闭环

| skill | 状态转换 | 职责 |
|------|----------|------|
| `/task-confirm` | 待确认 → 执行中 | PM 看 task 摘要、起 worktree、spawn suborchestrator |
| `/task-execute` | (执行中持续) | 实际执行 task 工作 |
| `/task-submit` | 执行中 → 已完成 / 回执行中 | 呈交验收信息包，PM 通过/打回 |
| `/doc-update` | (已完成阶段) | 处理文档偏差，**含模块规格对账（步骤 1.5/1.6）** |
| `/close-task` | (已完成阶段) | 调 `/doc-update` + merge 分支 + 清 worktree |

#### 新设计的最小改动

- **新增 1 个 skill**：`/task-spec <task-id>` —— 单 task 详细文档生成器（因为 stage 5 不再批量生成 task 文件，需要在 stage 6 里逐个生成）
- **改 1 个 skill**：`/doc-update` —— 步骤 1.5/1.6 的"对账"逻辑扩展为"沉淀"，支持模块规格从无到有累积写入
- 其他 4 个 skill（`/task-confirm` / `/task-execute` / `/task-submit` / `/close-task`）全部复用，状态机不动

#### 修订后的 stage 6 子循环

```
PM: /task-spec task-001                  ← 新 skill：生成详细 task 文档
PM 看 task 文档 → 确认/打回改

PM: /task-confirm tasks/task-001-...md   ← 现有
spawn suborchestrator 执行

PM: /task-submit                         ← 现有，PM 看原型验收
通过 → 状态转「已完成」

PM: /close-task                          ← 现有，内部调 /doc-update
/doc-update 把 task 的功能清单沉淀进 docs/modules/<module>.md
merge 分支、清 worktree

回到第一步，下一个 task
```

### Q3：task-plan.md 中途调整的口子怎么开？✅ 已确认

**采用 (a) 简化版**：PM 直接编辑 `task-plan.md`，**不强制** `.req-meta.json` 加 audit log，只在 `task-plan.md` 末尾追加"变更记录"段（手写几行）。

理由：单人工作流，audit 的成本不该超过变更本身的成本。`.req-meta.json` 留给机器写入的状态机事件，task-plan.md 本身就是文档，加几行人话变更说明更自然。

#### 场景处理表

| 场景 | 处理 |
|------|------|
| 新加 task（未开始）| PM 在 `task-plan.md` 列表里加一行（id 顺延，所属模块标好），然后 `/task-spec` 走新 task 的子循环 |
| 改未开始 task 的标题/所属模块/简述 | PM 直接编辑 `task-plan.md`，`/task-spec` 时按新版本生成 |
| 删未开始 task | PM 从 `task-plan.md` 列表删掉 + 删除对应 `tasks/task-NNN-*.md`（如果已 spec 过） |
| 删执行中 task | **暂不在 Q3 范围内解决**。需先终止 worktree/suborchestrator，建议未来新增轻量 `/cancel-task` |
| 改已完成 task（功能清单已 merge 进 module 规格）| **并入 Q5 冲突处理讨论**。建议方向：新建覆盖性 task，让新 task 的功能清单 merge 时覆盖/修订前一条 |

#### task-plan.md 的"变更记录"段格式

在 `task-plan.md` 末尾固定加一个段落（不强制写，但有标准位置）：

```markdown
## 变更记录

- 2026-04-25：新增 task-011 "导出功能"，PM 在 task-005 验收后追加
- 2026-04-26：删除 task-007，原计划的"批量导入"已并入 task-006
```

#### 不引入的东西

- ❌ 不新增 `/task-plan-amend` skill
- ❌ 不在 `.req-meta.json` 加 task-level audit log
- ❌ 不引入"退回 stage 5"的机制

### Q4：stage 6 完成判定 ✅ 已确认

把现有 `req-stage-gate` 里 stage 6 → 7 的判定**精确化**。

#### 现状判定（要替换）

```
1. 检查所有 task 状态为「已完成」
2. 如果有未完成的 task，列出并提示 PM
3. 全部完成后，确认门："所有 task 已完成，是否关闭此需求？"
```

问题：
- "所有 task"来源不明（tasks/ 目录扫描 vs task-plan.md 列表 → 中途变更后两者会不同步）
- "已完成"只代表 PM 验收过，但还没跑 `/close-task` → module 规格的功能清单 merge / 分支 merge / worktree 清理都没做

#### 新判定

替换步骤 1-3 为：

```
1. 读 task-plan.md 取出 task id 列表（排除"变更记录"里标注删除的）
2. 对每个 id 校验：
   - 有 tasks/task-NNN-*.md 文件
   - task 状态为「已完成」
   - task 分支已合并到 req 分支（== close-task 跑完）
   - task worktree 已清理
3. 全部满足 → 确认门："所有 task 已完成并关闭，是否关闭此需求？"
4. 不满足 → 列出哪些 task 缺什么（哪一步没跑）
```

**核心简化**：只要校验"task 已 close"，就隐含校验了"功能清单已 merge 进 module 规格"——因为 `/doc-update` 是 `/close-task` 的前置步骤，doc-update 失败 close-task 就不会成功。

#### 边界情况

| 情况 | 处理 |
|------|------|
| task-plan.md 里的 task 还没生成 task 文件 | 判定失败，提示 PM 跑 `/task-spec` 或从列表删掉 |
| 基础设施 task | 同样要求已 close，但 close-task 内部的 doc-update 对基础设施 task 会**跳过** module 规格 merge（按 Q1 决议） |
| **task 用 `--skip-doc-update` close（A1 决议逃生舱）** | **不视为完整 close**——stage 6→7 判定时该 task 算"半 close"，需要等对应人工 cleanup TODO 完成（PM 手工补 doc-update）后才视为完整 close。判定脚本读 task 的"文档偏差"section 是否含 skip-doc-update reason 标记，未清理则阻塞推进 |

#### 不引入的东西

- ❌ 不额外校验 `docs/modules/<module>.md` 内容是否"完整"（无法定义"完整"）
- ❌ 不引入新状态字段（已 close = 分支合并 + worktree 清理，可由 git/文件系统检查推断）

### Q5：task 沉淀 module 规格时的冲突处理 ✅ 已确认

**采用 (b) 智能化版本**：沿用现有 `/doc-update` 步骤 1.6 的"对账后逐条确认"精神，扩展为"沉淀"，区分新增/修改/跳过/不动。

#### 沉淀逻辑（doc-update 新增/扩展）

doc-update 在沉淀 task-N 的功能清单时，逐条对比 module 规格现有内容：

| 情况 | 处理 |
|------|------|
| task 清单里有 / module 里没有 | **新增**（静默执行，PM 在 task 验收时已 OK 过内容） |
| task 清单里有 / module 里也有 + 内容相同 | 跳过（无需写入） |
| task 清单里有 / module 里也有 + 内容不同 | **修改**（展示 diff，PM 逐条确认） |
| module 里有 / task 清单里没有 | **不动**（可能是其他 task 负责的功能） |

新增可一键通过，只有修改才打断 PM 让他决策。

#### 识别"同一条功能"的方式

采用 **方式 2 + 容错**：用 "所属模块章节 + 三级功能名" 作为组合 key 自动匹配（按 Q6 决议精确化）。

- "所属模块章节" 取自 task.md 顶部的 `**所属模块章节：**` 字段
- "三级功能名" 取自功能清单 section 内 `### N · 名称` 的名称部分
- 如果 task-005 改了三级功能名 → 匹配失败 → 当"新增"展示给 PM
- PM 在确认时如果发现"这其实是改名了"，自己手动删旧条目即可

#### 不引入的东西

- ❌ 自动覆盖（怕误删）
- ❌ 历史日志型 module 规格（git 已是版本控制）
- ❌ 功能稳定 id 系统（除非方式 2 实测撞墙太多再说）

#### Q3 衍生场景的归属

> Q3 表里"改已完成 task（功能清单已 merge 进 module 规格）"建议方向：新建覆盖性 task，让新 task 走正常流程。

落到 Q5 机制下：新覆盖性 task 验收通过 → doc-update 自动识别"内容不同" → 展示 diff 让 PM 确认 → 完成覆盖。不需要"修改已完成 task"的特殊机制。

### Q6：task.md.tmpl 字段细节 ✅ 已确认

#### task.md.tmpl 顶部新增字段

```markdown
**所属模块：** [模块名 / 多个模块逗号分隔 / 基础设施]
**所属模块章节：** [一级章节名 / 跨模块时按 "模块A:章节X, 模块B:章节Y" 格式]（业务模块 task 必填，基础设施 task 留空）
```

`所属模块章节` 用于 Q5 doc-update 沉淀时按"所属模块章节 + 三级功能名"复合 key 匹配。

**跨模块 task（plan-eng-review C3 决议）**：当 task 标多个所属模块时，"所属模块章节" 用 `模块A:章节X, 模块B:章节Y` 格式列出每个模块的对应章节。doc-update 沉淀时按列表逐个 merge 进对应 module 规格。

#### task.md.tmpl 新增 / 调整 section

**新增 section（顺序：任务描述之后、执行范围之前）：**

```markdown
## 用户使用流程（业务模块 task 必填，即验收依据）

### 场景 1：[场景名]
1. 用户动作 → 预期反馈
2. ...

### 场景 2：[场景名]
1. ...

## 功能清单（业务模块 task 必填）

> 本 section 为**硬约束**：功能行为、数据规则、角色权限必须严格遵循。
> 视觉 / 布局 / 微交互的发挥空间参见 `docs/DESIGN.md` §创意自由度。
>
> 填写规则（避免过度约束）：
> - 写动作 + 规则 + 限制（"展示 X 字段 / 不允许 Y / 默认 Z"）
> - ❌ 禁止写视觉细节：字号、颜色、间距、像素值
> - ❌ 禁止写微交互细节：动效曲线、过渡时长、悬停效果
> - ❌ 禁止指定具体组件库实例（"用 Tailwind Card"）
> - 如需指定视觉规范：写"参考 DESIGN.md §X"，不复制规则
> - 推荐组件需要时，放到下面"实现指引"section

### [三级功能名 1]

| 二级功能 | 三级功能 | 使用角色 |
|---------|---------|---------|
| ... | ... | ... |

1. [需求条目，动作+规则+限制]
2. ...

### [三级功能名 2]
...

## 实现指引

> 给 agent 实现时的行动指导。不写视觉细节（DESIGN.md 范畴），不重复"启动前必读"。
> 基础设施 task 简述脚手架要点；业务 task 按下方四条 bullet 填，没内容的 bullet 直接省略整条。

- **组件复用**：[UI 区域 → 复用/参考哪个已有组件，引文件路径不引代码]
- **状态覆盖**：[本 task 涉及的 Loading / Empty / Error 怎么处理]
- **关键逻辑**：[复杂或特殊的实现要点：异步、跨组件通信、状态机等]
- **易错点 / 禁止项**：[历史踩坑、明确禁止的实现方式]
```

**调整 section：**

| section | 调整 |
|------|------|
| 验收标准 | **业务模块 task 可省略**（用户使用流程已是验收依据）；**基础设施 task 必填**（写测试通过条件，如脚手架可启动 / API 端点可调通） |
| 启动前必读 | 不动，沿用现有机制 |
| 任务描述 | 不动 |
| 执行范围 / 执行日志 / 文档偏差 / 自审记录 / PM 反馈 | 全部不动 |

#### 三层 section 分工（防重复）

| 层级 | section | 维护谁 |
|------|---------|--------|
| 项目级 | DESIGN.md §创意自由度 + §共享组件清单 | 项目初始化 + doc-update 增量 |
| 模块级 | module.md 功能清单（累积） | task 验收后 doc-update 沉淀 |
| task 级 | task.md 用户使用流程 / 功能清单 / 实现指引 | task-spec 生成 + PM 验收时迭代 |

模块规格**不**维护实现指引（跟 `设计-功能规格文档增强.md` §8 不同，按本次决议简化）。

#### `/task-spec` 生成时的填写来源

| section | 来源 |
|------|------|
| 用户使用流程 | 从 solution.md 相关节抽，按场景组织 |
| 功能清单 | 从 solution.md 相关节抽，转为三级功能块格式 |
| 实现指引 - 组件复用 | Glob 扫项目已有组件 + DESIGN.md §共享组件清单 |
| 实现指引 - 状态覆盖 | 从功能清单推断（出现"列表"→ Loading/Empty/Error；"弹窗"→ 打开/关闭/校验失败） |
| 实现指引 - 关键逻辑 | 从 solution.md 抽 |
| 实现指引 - 易错点 | **从同模块已完成 task 的"PM 反馈"section 抽**（经验在 req 内传递） |

最后一条特别有价值——把已完成 task 的 PM 反馈作为后续 task 的"易错点"输入，是 living doc 思路的延伸。

#### 防 functions-v4.1.md 类过度约束

参考文档 §9 第 1 条详细写了 "20px/600 字号、`spacing-5` 内边距、`rounded-md` 圆角"——这是过度约束。在新设计下：

- 这类视觉细节应该**全部上提到 `docs/DESIGN.md`**（统一规范，所有页面适用）
- 模块/task 功能清单条目里**不允许出现**字号、像素值、组件库具体类名
- 由 `/task-spec` 和 `/doc-update` 在生成/沉淀时自动检测并剥离这类细节

---

## DX Review 决议（plan-devex-review 产出，2026-04-25）

### Persona / Mode / Magical Moment / Review 锚点

| 维度 | 决定 |
|------|------|
| Target Persona | 单人 PM（dogfood），高 tolerance / 对"步骤多 + 闸门密"敏感 |
| Review Focus | **返工率最低 / 拆得准 + 走得顺**（其他维度是次要） |
| Magical Moment | **第一次 task 验收一次过**（PM 不翻 SKILL.md，按 task 文档逐步验收原型全对） |
| Mode | DX POLISH |

### 5 个 P0 决议（journey trace 发现的 friction）

| # | Friction | 决议 | 影响 |
|---|----------|------|------|
| RU3 | 打回时改 task 文档 vs 改代码顺序不明 | **agent 智能分流**：行为/规则修订 → 改 task 文档；bug/原型偏差 → 只改代码。agent 一句话告知判断，PM 可驳回 | 改 `/task-execute` + `/task-submit` 处理 PM 反馈分支 |
| RU4 | 自动 merge 进 module 规格"静默通过"，PM 想 verify 一眼 | **静默 + summary link**：merge 完后一行"已沉淀 N 条新增进 docs/modules/X.md (查看 diff: <link>)"，不强制 PM 看但有显式入口 | 改 Q5 沉淀逻辑 + `/doc-update` 输出 |
| RU6 | stage 6 子循环 4 命令链（spec/confirm/submit/close）+ 5 闸门 | **轻量 auto-chain**：close-task 完成后 orchestrator 自动提示"下一个 task 是 X，继续 (Y/n)"，PM 一键继续。其他暂停点不变 | 改 `/close-task` 末尾 + req-stage-gate 编排 |
| DB2 | doc-update 沉淀失败的错误呈现没设计 | **失败一律阻塞 close-task**：错误信息明确（哪个文件 / failure 类型 / 续跑路径），PM 解决后重跑 `/close-task` 自动续做 doc-update | 改 `/doc-update` + `/close-task` 失败处理 |
| UP | 现有 v1 项目升 v2 的 upgrade path 完全没讨论 | **Defer + TODOS.md**：作为后续独立子设计，本 plan 不解决 | 加 TODO 条目（见下方 P2） |

### 4 个 P1 obvious fix（写进 plan，无需 PM 拍板）

| # | Friction | 落地 |
|---|----------|------|
| RU1 | "基础设施"判定规则要查 SKILL.md | **task-plan.md 顶部固定附判定规则提示**：业务模块 / 基础设施二选一硬规则、4 行说明 |
| RU2 | 实现指引-易错点的来源不告知 | `/task-spec` 生成时在易错点条目后注明 `(来自 task-XXX 的 PM 反馈)`，让 PM 知道经验来源 |
| RU5 | task-plan 中途调整后没自动校验 vs `tasks/` 目录 | `/task-spec` 和 stage 6 子循环开头自动 check：task-plan.md 列表里的 task id ↔ `tasks/` 文件，列出差异 |
| RU7 | 基础设施 task 跟业务 task 流程透明度 | `/task-spec` 生成基础设施 task 时明确告知 PM "本 task 不会触发 module 规格 merge（按 Q1 决议）" |

### DX Scorecard

| 维度 | Plan 现状 | Fix 后预计 | Evidence |
|------|-----------|------------|----------|
| Getting Started (新 PM 上手) | 4/10 | 6/10 | TTHW 几小时（要走 stage 1-4），无 Quick Start。Defer 优化。|
| API/CLI Design (skill 命令 ergonomics) | 6/10 | 8/10 | 命令清晰但链长 → RU6 auto-chain 改善 |
| Error Messages | 5/10 | 7/10 | DB2 设计明确后改善；DB1（INVARIANTS 编号对 PM 不友好）defer |
| Documentation (设计文档+SKILL) | 5/10 | 6/10 | 设计文档详细但 README 缺入口（D1-D3 defer）|
| Upgrade Path | 2/10 | 3/10 | 完全没设计 → defer to TODOS（仅占位）|
| Dev Environment (worktree/状态机/事件流) | 7/10 | 7/10 | 已经扎实，无 plan-level 改动 |
| Community | N/A | N/A | PM 单人项目，跳过 |
| DX Measurement | 1/10 | 1/10 | 当前 plan 完全没涉及（无 metric / no instrumentation）|
| **Overall DX** | **5/10** | **6.5/10** | 主要 lift 来自 RU3/RU4/RU6/DB2 |

| 元数据 | 值 |
|--------|------|
| TTHW (PM 一个 task 端到端闭环) | v1: ~2h → v2: ~25-40min |
| Competitive Tier | 内部代际对照: v0 旧仓 / v1 当前实施 / v2 新设计 |
| Magical Moment | 验收一次过 — 由 RU3 智能分流 + RU2 易错点经验传递共同支撑 |
| Product Type | Claude Code Skill |

### DX Implementation Checklist（fixes 落地核对）

- [x] task-plan.md 顶部附"基础设施"判定规则提示（RU1）— Batch 2 (a6d33ab)
- [x] `/task-spec` 在易错点条目后注明 `(来自 task-XXX 的 PM 反馈)`（RU2）— Batch 1 (90997a3)
- [x] `/task-execute` + `/task-submit` 处理 PM 反馈时按"行为修订 vs bug"分流，agent 一句话告知判断（RU3）— Batch 3 (dfd5f5f)
- [x] `/doc-update` 沉淀新增条目时输出 summary line + diff link（RU4）— Batch 2 (a6d33ab)
- [x] `/task-spec` 和 stage 6 子循环开头校验 task-plan.md ↔ tasks/ 一致（RU5）— Batch 1 (90997a3)
- [x] `/close-task` 末尾轻量 auto-chain：完成后自动提示下一个 task，PM 一键继续（RU6）— Batch 3 (dfd5f5f)
- [x] `/task-spec` 生成基础设施 task 时明确告知"本 task 不触发 module merge"（RU7）— Batch 1 (90997a3)
- [x] `/doc-update` 失败一律阻塞 close-task；错误信息含文件 / failure 类型 / 续跑路径（DB2）— Batch 2 (a6d33ab)
- [x] Upgrade path 子设计写入 TODOS.md（UP）— commit 55015a9 时已加进 TODOS.md（DX backlog）

**Batch 3 衍生一致性 fix（dfd5f5f）**：req-stage-gate C2 半 close 检测精确化为 grep `<!-- SKIP_DOC_UPDATE:` AND `cleanup_status="pending"` 同时存在；cleanup 描述改为"改 status='done'"（保留 marker 作 audit trail）。

### 12 个 P2（已迁移 TODOS.md，本 plan 不解决）

D1/D2/D3 (Discover) / I1/I2 (Install) / HW1/HW2/HW3 (Hello World TTHW) / DB1 (INVARIANTS 编号) / UP (upgrade path 子设计) — 详见 TODOS.md 末尾"DX backlog (来自 plan-devex-review 2026-04-25)"

---

## Eng Review 决议（plan-eng-review 产出，2026-04-25）

### 4 个真决议

| # | Issue | 决议 | 影响 |
|---|-------|------|------|
| Eng-1 | 10 文件改动一次合 vs 分批？ | **分 3 批 PR 落地**（见上方"落地节奏"表） | 改动清单按 batch 重组 |
| A1 | doc-update 是 SPOF，DB2 阻塞但缺逃生舱 | **`close-task --skip-doc-update` flag**：必填 reason 写进文档偏差 section + 自动生成人工 cleanup TODO + task 标"半 close" | 改 `/close-task`（改动 #11）+ Q4 边界表更新 |
| A3 | 多模块 task doc-update merge atomicity | **atomic merge**：git 临时分支全 merge，任一失败全回滚 | 改 `/doc-update`（改动 #6 加 atomicity 处理） |
| T1 | plan 当前没明确测试策略 | **每批 PR 必带对应测试 + 4 critical gap 必须 E2E 在对应 batch 绿** | 落到 Batch 1/2/3 的 acceptance criteria；test plan 详见 `~/.gstack/projects/PM-AI-Workflow/local-user-main-eng-review-test-plan-20260425-204848.md` |

### 4 critical test gap（漏测 = silent failure）

落到对应 batch 的 acceptance criteria：

| # | Critical gap | 所属 batch |
|---|-------------|------------|
| 1 | doc-update 失败 → close-task 阻塞（DB2 必须工作） | Batch 2 |
| 2 | close-task --skip-doc-update reason 必填（A1 防滥用） | Batch 3 |
| 3 | req-stage-gate 半 close 检测（C2 防误推 stage 7） | Batch 2 |
| 4 | doc-update 失败 → 修复 → 续跑 E2E（端到端可恢复） | Batch 2 |

### 3 个一致性 fix（已直接修进设计文档）

- **C1**: 改动清单从 8 条扩展到 11 条（加 #9 task-execute / #10 task-submit / #11 close-task）
- **C2**: Q4 边界情况表加"task 用 --skip-doc-update close 视为半 close"
- **C3**: Q6 顶部新增字段说明跨模块 task 的"所属模块章节"格式

### 失败模式注册表

| 失败模式 | 决议 | 状态 |
|---------|------|------|
| doc-update 写文件失败 | DB2: 阻塞 close-task + 错误信息明确 | 已设计 |
| doc-update 永久失败导致 PM 卡死 | A1: --skip-doc-update 逃生舱 | 已设计 |
| --skip-doc-update 被滥用 | A1: 必填 reason + cleanup TODO | 已设计 |
| 半 close task 被误推 stage 7 | C2: 边界表强制阻塞 | 已设计 |
| 多模块 merge 部分成功的中间状态 | A3: atomic merge 回滚 | 已设计 |
| 多 req 并行同 module 的 markdown conflict | A2: defer + TODO | 接受偶发痛 |

### Worktree parallelization

3 batch PR 顺序执行（Batch 1 → 2 → 3）。每 batch 内部可并行：

| Batch | 可并行的文件改动 |
|------|------------------|
| 1 | task.md.tmpl / module.md.tmpl / DESIGN.md.tmpl 三模板可并行；新建 task-spec/SKILL.md 等模板就绪后做 |
| 2 | task-plan / req-stage-gate / doc-update 三 skill 可并行（不互依） |
| 3 | task-execute + task-submit 共享分流逻辑（先做共享提取再分别落）→ close-task 跟前两者独立可并行 |

### implementation 性能 flag（不阻塞 plan）

每个 task 子循环重复读 solution.md / DESIGN.md / module.md（大文件）→ orchestrator 缓存 read 结果跨子循环。implementation 阶段考虑。

---

## Stage 5/6 默认 review 决议（2026-04-26）

落地后的微调：把"建议 PM 跑 review"升级为"默认必跑"，避免 PM 凭手感跳过 review 导致拆分/单 task 设计的偏差只能等 task 验收时撞出来。

### Stage 5 → 6（task-plan.md 完成后）

- **从**：first req 自动跑 `/plan-eng-review`；后续 req 建议 PM 跑（可跳）
- **到**：所有 req 默认自动跑 `/plan-eng-review` 审阅 `task-plan.md`，不区分 first / 后续
- review 发现贴 chat（讨论性，不写盘）
- PM 提修改意见 → 回 `/task-plan` 改 `task-plan.md` → 重跑 review → 再次确认门
- 落点：`skills/req-stage-gate/SKILL.md` Stage 5 → 6 段

### Stage 6（task-spec 单 task 文档完成后，PM 确认前）

- **从**：`/task-spec` 步骤 7 写完直接进步骤 8 PM 确认门，无 review
- **到**：`/task-spec` 在 PM 确认门前插入默认 review 步骤
  - **业务模块 task** → 自动跑 `/plan-eng-review` + `/plan-design-review`
  - **基础设施 task** → 只跑 `/plan-eng-review`（无 UI 内容，跳过 design-review）
- review 发现贴 chat；PM 选项：
  - 改 task 文件 → 改完重跑对应 review（eng 改了重跑 eng，design 改了重跑 design）
  - 忽略发现继续 → 直接进 PM 确认门
- 步骤 9 摘要里显式列出 review 状态：`eng [PASS/有发现已处理/PM 忽略]，design [PASS/有发现已处理/PM 忽略/跳过(基础设施)]`
- Rule 硬约束：review 不可静默跳过，PM 只能在看到发现后选择"忽略发现继续"
- 落点：`skills/task-spec/SKILL.md` 步骤 8（新增）+ Rules 一条

### 与原 §改动清单 的关系

不改原 11 条改动清单的编号，作为追加决议——本决议只动两个 SKILL.md，不改模板、不改其他 skill。

### 不引入的东西

- ❌ 不新增 review skill（直接复用 gstack 的 `/plan-eng-review` / `/plan-design-review`）
- ❌ 不把 review 发现写入 task 文档（review 是讨论，不是文档产出，避免文档臃肿）
- ❌ 不引入"review PASS / FAIL"的硬阻塞——PM 是单人决策者，看到发现后有权选择忽略
- ❌ 不对基础设施 task 跑 design-review（无 UI 可审）

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | — | — |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues_open | 7 issues（4 真决议 + 3 一致性 fix）+ 4 critical test gap + 33 test gap，分 3 batch 落地 |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 1 | issues_open | score: 5/10 → 7/10, TTHW: 2h → 30min, 5 P0 决议 + 4 P1 obvious fix |

- **UNRESOLVED:** 0（DX 5 P0 + Eng 4 真决议全部决策完毕；3 一致性 fix 已直接修；TODOS.md 已更新 A2 / C-fix1 / UP）
- **VERDICT:** DX + ENG REVIEW DONE — 13 个决议待落地（见 §DX Review 决议 + §Eng Review 决议）。建议按"落地节奏"分 3 batch PR 推进，每批 PR 必带对应测试 + 4 critical gap 必须 E2E。
