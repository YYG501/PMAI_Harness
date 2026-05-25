---
name: task-plan
description: |
  Stage 5：读取上游 stage 文档 + 项目级文档 + 原型代码，拆分 task 规划。按 $REPO_ROOT/templates/task-plan.md.tmpl 生成单一文件 task-plan.md（PM 视图 + 末尾轻量自检与状态摘要）。不生成具体 task 文档，不生成工程合同分文件。
---

# /task-plan

## When To Use

- Orchestrator 在 stage 5 调用（由 `/req-stage-gate` 触发）

## PM 视图规则（必读）

本 skill 生成的文档须遵守 `skills/_shared/PM-VIEW-RULES.md`（主索引）。具体读以下子文件：
- `_shared/pm-view/writing-rules.md`（§三 写作规则：明确指代 / 正向描述 / 禁工程词 / 禁像素颜色 / 禁反向约束）
- `_shared/pm-view/section-order.md`（§七 章节顺序：按 `$REPO_ROOT/templates/task-plan.md.tmpl`）
- `_shared/pm-view/input-flow.md`（§九 输入流：上游 stage 文档 + 项目级文档；输入清单见下方 Required Inputs）

> 「工程合同」成分（反模式自检结论 / 验收 GAP 索引 / 模块规格状态）压在末尾 §四 自检与状态摘要节。详细论证 / autoplan 决策不长期存档，跑时输出即可。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-plan"
```

## Required Inputs

按 `_shared/pm-view/input-flow.md` 中 **Stage 5 task-plan** 段执行。

特别遵守：
- `input-flow.md` §9.3.1 prototype 读取强约束（>500 行禁整文件 Read）
- `_shared/pm-view/cross-skill.md`（特别 brief / DESIGN 改 ⚪ 按需，不强制全文必读）

**v2 / C2 补**：`implementation-design.md`（如本 req 已产出，在 task-plan 之前 stage 5）
作为必读输入 —— 段 1 架构决策表影响 task 拆分边界；段 1.5 原型简化项决定 §4.2 验收 GAP
是否走「原型不实现」第三种处置（kind 2 反向写回的入口在本 skill）。读法按 `input-flow.md
§9.1.1` 章节 grep。

## Workflow

### attachments AI 接管 hook（D-iii v2 trigger 0 — Stage 5b 期间生效）

PM 在 chat 描述 "我有 X 在 ~/Downloads/foo.pdf，重点 Y" → AI first-principle 识别 → 调 helper：

```python
from _lib.attachments import copy_attachment
result = copy_attachment(req_dir, Path("~/Downloads/foo.pdf"),
                        stage_prefix="task-plan", hint="Y 重点")
```

stage_prefix `"task-plan"`（Stage 5b）。chat 一行确认 `已归档（attachments/task-plan-foo.pdf），Y 重点。继续。`（禁工程黑话）。

异常 catch：`FileNotFoundError` / `SensitivePathError` / `FileSizeError` → chat 报错（fail-loud）。

**trigger 2 fallback**：写 `task-plan.md` 前扫 `attachments/`，`is_seen` 判定。

**引用 section 渲染**：写 `task-plan.md` 时 `list_attachments_seen` 按 `registered_at` 升序渲染到文档物理末尾。

**单一真相源**：`skills/_shared/pm-view/attachments-upload.md`。

### 步骤 0：读 PM 视图规则子文件（强制）

打开（一次会话只读 1 次）：
- `skills/_shared/pm-view/writing-rules.md`（§三）
- `skills/_shared/pm-view/section-order.md`（§七）
- `skills/_shared/pm-view/input-flow.md`（§九）

### 步骤 1：读取所有必读输入

按上方 Required Inputs 列出的文件**逐一读取**：
- 上游 stage 文档（brief / analysis / prd 功能规格）
- 项目级文档（PROJECT / DESIGN / prd / modules / prototypes）

**特别注意**：
- 项目级文档列为"必读"——AI 不得以"觉得不必要"为由跳过
- `prototypes/` 必读（input-flow.md §9.3）：
  - 判断哪些能力已存在（影响 task 拆分粒度，避免重复创建）
  - 反向校验上游文档：原型已删除 / 砍掉的工程概念不引入 task 拆分

### 步骤 2：拆分 task

> **颗粒度核心规则**：一个 task = PM 能在一次原型 demo 里完整验收的功能单元。
>
> **验收硬约束**：必须能在原型上演示一段业务流程才算端到端验收。PM 走查代码结构 / 文档可读性 / 契约合理性 **不算**端到端验收。文档型产物（模块规格文档 / functions.md / 字段口径契约 / 范围裁剪规则）天然不满足本约束 → **不立 task**，由业务 task close 后 `/doc-update` 流程沉淀对应章节。跨 task 共享口径决策应在 stage 2-3（analysis / prd）定死，stage 5 不为此立 task。
>
> **业务模块 task**：一个 task 对应 1-N 条紧密相关的功能清单条目；紧密相关指同一个 user story 链条，或同一个页面区域可一次性 demo。不同 user story 链条即使在同一页面，也要拆成不同 task。
>
> **基础设施 task**：一个 task 对应一类完整可用的基础设施能力，例如项目脚手架、共用组件库、auth context、API client、构建配置。
>
> **端到端切片原则**：task MUST 按 user story 端到端切（前端 + 后端 + 数据层捆绑）；technical layering cuts are FORBIDDEN，不允许拆成"先数据层、再 UI、再联调"。

#### 2.1 基本原则

> **DX RU1 固定提示：业务模块 / 基础设施判定硬规则**
>
> 1. 每个 task 必须显式声明 `所属模块`，只能是一个或多个业务模块，或 `基础设施`。
> 2. 产出在任何业务页面/流程上直接可见时，必须归到对应业务模块。
> 3. 只有产出不在任何业务页面/流程上直接可见，且不是文档型规格（模块规格文档 / functions.md / 字段口径契约 / 范围裁剪规则），才允许标 `基础设施`。
> 4. 基础设施 task 验收后不沉淀进 `docs/modules/<module>.md`；如需长期记录，由 PM 决定是否写入 `docs/PROJECT.md` / `docs/DESIGN.md`。
>
> 基础设施识别示例：项目脚手架、共用 Button/Modal 组件库、API client、auth context、构建配置。反例：登录页的"会话管理 hook"服务于登录流程，应归登录页/账号模块。

#### 2.2 反模式（必须避免）

每次拆完先按下面 5 条反照一遍，命中任何一条就合并或重构该 task：

**反模式 A：纯前置 task（重构 / 文档 / 规格 / 契约）**

> 例 1：为了后续 task 并行改同一大文件不冲突，先加一个"拆文件 + 引入 reducer"的纯结构 task。
> 例 2：为了让后续多个页面 task 共享字段口径与范围裁剪规则，先单独一个"写模块规格文档"task，文档写完后页面 task 才启动。
> 例 2 变体（同样错）：把"覆盖多平台的规格文档"塞进第一个页面 task，让该 task 同时承担"页面 + 跨平台规格"两件事。

- 问题：纯前置 task 不满足颗粒度核心规则的验收硬约束（无法在原型上演示业务流程），却要跑完整 `/review + submit + close` 流程。
- 判断：
  - **重构类前置**：后续 task 串行执行时 merge 冲突不存在，前置理由不成立，合并进首个相关业务 task。仅当后续 task 必须并行且冲突无法避免，才考虑前置，并且必须带端到端行为验证点。
  - **文档 / 规格 / 契约类前置**：不立 task。由各业务 task close 后的 `/doc-update` 沉淀对应章节（颗粒度核心规则已说明）。

**反模式 B：横切质量 task**

> 例：把所有 UI 改造 task 的 a11y、1280px 响应式、埋点、i18n 剥出来最后统一做一个"质量收尾 task"。

- 问题：前面 UI task 会在没有这些质量维度的状态下过 `/qa` 和 `/design-review`，等于 review 半成品。
- 判断：a11y / 响应式 / performance / 埋点 / i18n 等跨所有 UI 的质量维度必须写进每个 UI task 的验收依据，不允许独立成 task。

**反模式 C：共生对拆成两个**

> 例：task A 定义纯函数签名，task B 改 Mock 数据以匹配签名。单独跑 A 只能用 stub 验证，单独跑 B 没有函数可调。

- 判断启发式："单独跑完 A 后，能端到端验证到业务价值吗？"如果不能，合并 A 和 B。
- 典型共生对：纯函数层 + 对应 Mock/fixture；数据库 schema migration + ORM model 更新；新组件 + 首个调用方。

**反模式 D：同文件串行多 task（软约束）**

> 例：task 006/007/008 都改同一个详情页文件且串行，只为验收维度清晰就拆 3 个 task。

- 判断：同文件 + 串行的 task，必须在 `task-plan.md` §四 自检与状态摘要的反模式 D 行里显式写出"拆多个 vs 合并"的成本权衡结论。
- 没写权衡理由而拆多个的，默认合并。

**反模式 E：业务功能 task 没有模块归属**

> 例：task "实现产品访问管理列表页" 标 `所属模块: 基础设施`。

- 问题：业务功能不沉淀进 module 规格，living doc 会残缺。
- 判断：见 DX RU1（业务模块 / 基础设施判定硬规则）。
- 典型错误示例：登录流程、列表筛选、批量导出、权限提示、详情页状态展示都不是基础设施。

#### 2.3 task 数量启发式

- 单 req 总 task 数 > 7 时，立即回头按 2.2 审查。不是硬上限，但经验上超过 7 往往踩中反模式 A/B/C。
- 单模块软上限 = 3 tasks。单个模块被拆成超过 3 个 task 时，必须回头审查是否把同一页面区域或同一 user story 链条拆得过细。

#### 2.4 拆分后自检清单

给每个 task 问以下 5 个问题，任何一个答"是"或"不满足"就返回 2.2 处理：

1. [ ] 这个 task 的验收依据是否只有"代码结构变好/重构完成"这种过程性描述？（反模式 A）
2. [ ] 这个 task 描述的工作是否应该是其他某个 task 的验收标准的一部分？（反模式 B）
3. [ ] 这个 task 单独跑完后，能不能由 PM 通过原型 demo 验到业务行为？（反模式 A/C）
   - PM 走查代码结构 / 文档可读性 / 契约合理性 不算独立验证
   - 必须能在原型上演示一段业务流程才算
4. [ ] 这个 task 和另一个 task 改同一文件且串行，是否在 `task-plan.md` §四 自检与状态摘要里写了成本权衡结论？（反模式 D）
5. [ ] 所有 task 的模块归属是否满足硬规则？业务功能 task 是否真的归到了业务模块章节，而不是图省事标成 `基础设施`？（反模式 E）

### 步骤 3：写 task-plan.md

按 `$REPO_ROOT/templates/task-plan.md.tmpl` 生成 `$ACTIVE_REQ_DIR/task-plan.md`：

**章节顺序**（强制，由 `_shared/pm-view/section-order.md` §七锁定）：
1. 📌 拆分摘要
2. 一、Task 列表
3. 二、执行顺序与并行性
4. 三、风险
5. 四、自检与状态摘要（反模式自检 5 条 + 验收 GAP 清单 + 模块规格状态）
6. 📁 历史档案（变更记录）

**写作约束**（违反将由 `check-doc-pm-view.py` 报错）：
- 每个名词带完整指代前缀
- 不出现像素值 / 颜色码 / 工程词（reducer / dispatch 等）
- 不出现反向约束（"禁止 X / 不允许 Y"）
- task 列表 summary 一句话讲清交付物，不写实现细节

**§四 自检与状态摘要填写要点**：
- §4.1 反模式 5 条逐条勾选"未命中 / 命中（已处理）"，命中时一句话说明合并 / 重构结论。**5 条全 PASS 才能进入 stage 6**。
- §4.2 验收 GAP 清单：从 `prd.md` 「验收标准」逐条审视，编号 G1, G2, ...。**三种处置之一**（v2 / C1）：
  1. **由 task-NNN 接住**（默认）—— 由 stage 6 task-spec 按编号接住
  2. **已被 task 列表完全覆盖** —— 显式写「无 GAP」
  3. **原型本次不实现（kind 2 整块功能不做）** —— PM 在 task-plan 决策本期整块功能不立 task；
     在 GAP 行写「原型不实现（kind 2）→ 反向写回 implementation-design.md 段 1.5 SIMP-NN」+
     去 `implementation-design.md` 段 1.5 追加一行（SIMP-ID 顺延接，PRD 锚点 = GAP 来源章节，
     真实需求引用 PRD，原型本次计划简化为 = 「本功能原型不实现」，为什么简化 = PM 给的理由，
     来源 = kind 2）。close-req §2a 据此在 PRD 加「本功能原型本次不实现」标注
- §4.3 模块规格状态：列出本 req 涉及的每个业务模块的当前规格状态（已存在-完整 / 已存在-待补 / 不存在-待创建），影响 task-spec 步骤 4 判断。

### 步骤 4：自检（按 `_shared/pm-view/checklist.md` §八 12 项）

写完后对 `task-plan.md` 逐条检查：
- [ ] 章节顺序符合 $REPO_ROOT/templates/task-plan.md.tmpl
- [ ] 所有名词带完整指代前缀
- [ ] 无像素值 / 颜色码 / Emoji 视觉
- [ ] 无反向约束
- [ ] 无组件实现名
- [ ] 无设计意图解释
- [ ] 抽象动词都搭配具体效果

任一项未通过 → 修复后重新自检。

### 步骤 4.5：自动跑启发式 lint

人工自检之后，调用 `check-doc-pm-view.py` 做机器校验作为兜底：

```bash
python3 "$REPO_ROOT/.claude/scripts/check-doc-pm-view.py" "$ACTIVE_REQ_DIR/task-plan.md"
```

处理输出：
- **0 errors + 0 warnings**：进入步骤 5 退出 skill
- **有 warnings**：向 PM 展示，PM 决定是否修
- **有 errors**：修复后重跑 lint；连续 3 次仍有 error 时停下询问 PM

### 步骤 5：skill 结束 → /req-stage-gate 接手

写完 task-plan.md → skill 退出。向 PM 展示一句话摘要 + 文件绝对路径（不贴全文）。

控制权交回 `/req-stage-gate`，由它：
- 输出"推荐 review 工具"区块（`/plan-eng-review` `/plan-design-review` `/autoplan` 等，PM 自选自跑，I-RV1）
- 走推进确认门

**禁止**：skill 内部不得自动调任何 review 工具。PM 要求修改 → 改完 task-plan.md 重新走 stage-gate 流程。

进入 stage 6 后，具体 task 文档由 stage 6 的 `/task-spec <task-id>` 按 task-plan.md 逐个生成。

### 步骤 6（中途重新拆分）：stage 6 发现拆分需要重做

stage 6 task 子循环里，有时跑到 task-NNN 才发现 task 拆分本身有问题，需要废弃当前拆分回 stage 5 重拆。

被 stage-gate 重新触发本 skill 时（PM 已通过 task-transition / req-transition 完成 discard + rollback），按步骤 1-3 重新写 task-plan.md，遵守两条约束：

- 新增 task 编号**往后接**，不复用已废弃 task 编号
- 在 task-plan.md §历史档案 变更记录里追加一条变更说明（写明本次重拆替代了哪些已废弃 task）

discard / rollback 的具体操作流程见 `task-transition` 与 `req-stage-gate` skill，不在本 skill 复述。

## Rules

**禁止项**：

- ❌ skill 内部走推进确认门
- ❌ skill 内部自动调任何 review 工具（I-RV1）
- ❌ skill 内部调 req-transition.py
- ❌ 自动生成 tasks/task-NNN-*.md（这是 stage 6 task-spec 的事）
- ❌ 生成 task-plan.engineering.md 之类的工程合同分文件（task-plan 单文件，自检结论压在 §四）
- ❌ §四 自检与状态摘要里堆论证全文 / 拆分依据论证 / autoplan 决策表（这些是过程产物，跑时输出，不长期存档）
- ❌ 跳过项目级文档的"必读"（PROJECT / DESIGN / prd / modules / prototypes）

**正向约束**：

- task 编号三位数，从 001 开始，格式 `task-001`。
- 拆完 task 必须跑步骤 2.4 自检；任何一条命中就返回 2.2 合并或重构，不能直接进入步骤 3。
- task 总数超过 7 时，必须在 task-plan.md §四 自检与状态摘要的"结论"行里显式列出每个 task 的存在理由。
- 单模块超过 3 个 task 时，必须在 task-plan.md §四 自检与状态摘要里写明为什么不合并。
