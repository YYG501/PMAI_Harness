<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260512-145959.md -->
# PRD / modulespec 体系重构

> 状态：v1 方案 + autoplan 评审 + v1.1 stage 术语修正 + Q1-Q4 全部已拍 + D4/D8/D10/A2 AI 自决 + D13 v2 round 3 review / **§十四 D13 v3 设计稿已写入，待 PM review + round 4 autoplan**
> 日期：2026-05-11/12（v1 / autoplan / v1.1 / D13 v2-v3 连续迭代）
> 起因：adminconsole4 实操中发现当前三层文档体系（req-prd / modulespec / project-prd）有概念混淆 + project-prd 在 PM 实际工作流中没人看
> 触发对话：见本文末尾"对话关键节点"
> autoplan 评审完整 plan：`<LOCAL_CLAUDE_HOME>/plans/hashed-waddling-hummingbird.md`（含 D1-D12 决策清单 + 三视角独立 finding）
>
> **术语约定（v1.1）**：
> - **req stage**：仓库定义在 `scripts/req-transition.py:11-19` STAGE_NAMES，值 1-7（感受问题 / 需求分析 / 方案设计 / 设计系统建立 / 模块规格+task 拆分 / **task 执行** / **req close**）
> - **task status**：仓库定义在 `scripts/task-transition.py:43-46` VALID_TRANSITIONS，值"待执行 / 执行中 / 已完成 / 已废弃"——代码层不叫 stage
> - **本文凡说"stage X"特指 req stage 的数字编号**；提到 task 状态写"task status XX"避免混淆
> - close-req SKILL.md 的所有内部步骤（step 1 / 1.5 / 2a / 2b / 2c / ...）都是 **stage 7 内部工作**，不要标成 "stage 6 → 7"

## 一、起因与现状诊断

### 1.1 adminconsole4 暴露的现象

PM 在实操中观察到两条事实：

1. **不需要"包含所有功能"的 project-prd**——产品全貌的累积视图在实际工作中没人翻
2. **modulespec 的作用迷惑**——写起来跟 req-prd 撞内容，不知道存在意义

但 PM 同时承认了三个场景，反过来证明 modulespec 是必要的：

- 一个 req 可能同时改多个模块
- 某个 req 对某模块改的内容很少（在 req-prd 里只占一段）
- 可能改的是之前 req 的产出（增量在旧基础上）

这三种情况都意味着：**单看 req-prd 永远拼不出"模块 X 当前完整长什么样"**。

### 1.2 真正的根因

PM 心智里把 req-prd 误当成 modulespec 来写——以为"一份 req-prd 要交代清楚涉及到的每个模块的完整规格"，所以又厚又跟 modulespec 撞内容。

但 PM 同时又有"按需生成 PRD 评审"的实际工作流：

- req 结束**可能产生也可能不产生** PRD
- 也可能**没有任何 req 上下文**，PM 突然让 AI 给"某几个模块一起说明"生成一份 PRD
- PRD 是评审材料，可以丢、可以重生成

## 二、新分层设计

### 2.1 两类文档的根本区别

| 层 | 文件 | 性质 | 谁用 |
|---|---|---|---|
| **底层（持久）** | `docs/modules/*.md` (modulespec) | 单一真相源 / 长期维护 | task-execute 当硬约束 / doc-update 回填 / 后续派生 PRD 的底料 |
| **上层（临时）** | PRD（任意范围、任意时机） | 派生材料 / 按需生成 / 评审完即丢 | PM 评审 |

**modulespec ≠ 另一种 PRD。** 它是底层 source of truth，服务的不是 PM 评审场景：

1. **task 实施的硬约束源**——task-execute SKILL.md:275-276 明确要求按 modulespec 的功能清单 / 字段口径 / 角色权限执行。PRD 是评审材料、会漂移；硬约束必须有一份不会漂的。
2. **跨 req 真相累积**——模块被 N 个 req 改过，永远有一份"当下到底是什么样"的权威，新 req 进来不用反推。
3. **PRD 的底料**——PM 在主分支让 AI 写"某几个模块的 PRD"时，AI 从 modulespec 取真相 + 加业务包装。没 modulespec 时 AI 只能爬代码 + 翻历史 req-prd 自己拼，又慢又错。

### 2.2 PRD 的新定位

- **不强制产出**：req 结束可写可不写
- **范围灵活**：单 req / 单模块 / 多模块组合
- **触发地点**：req 分支内或主分支均可
- **生命周期**：评审完即丢，不必长期维护
- **生成路径**：从 modulespec + 业务上下文派生，不从代码反推

### 2.3 project-prd 砍掉

`docs/prd.md`（项目级累积总览）跟"PRD 按需派生"原则一致——要看产品全貌时临时让 AI 从所有 modulespec 拼一份就行，不长期维护一份。

## 三、modulespec 模板简化

### 3.1 当前模板章节审计

> **修正（autoplan F1）**：实际模板有 **10 节**，不是 8 节。多出的"九、Task 拆分提示"砍前必须说明谁接住（task-plan / task-spec 是当前消费者）。

| # | 当前章节 | 留/砍 | 理由 |
|---|---|---|---|
| 0 | 摘要 | 合并 | 揉进"定位" |
| 一 | 模块定位（1.1-1.4 四个子节） | 简化 | 拍扁成一段话 + 一张角色表 |
| 二 | Scope In / Scope Out | **砍** | req 切片，不是"模块当下"，属于 req-prd |
| 三 | 功能清单（硬约束） | **留** | task-execute 的硬约束、PRD 的底料，核心资产 |
| 四 | 页面与交互范围 | **砍** | 有原型时原型是真相；要讲交互在 req-prd / DESIGN.md |
| 五 | 硬约束 | **砍** | 功能清单本身就是硬约束，重复 |
| 六 | 本批不做 | **砍** | req 切片 |
| 七 | 验收标准 | **砍** | task / req 的事 |
| 八 | 跨模块依赖与占位策略 | **砍**（依赖部分按 D4 升级为结构化标注，**待拍**）| 依赖如何承接见 §3.3 Q2；占位是 req 切片 |
| 九 | Task 拆分提示 | **待拍** | task-plan / task-spec 是消费者；砍前必须确认它们是否能从其他来源（brief / analysis / solution）拿到等价信息。**这是 v1 文档遗漏，autoplan 才发现** |

### 3.2 简化后的 3 节模板

```markdown
# {{MODULE_NAME}}

> 模块当下状态 —— 单一真相源。
> task-execute 拿功能清单当硬约束；doc-update 在 task 落地后回填；
> 生成 PRD 时从这里取底料。
> 视觉/组件/状态规范走 docs/DESIGN.md；跨模块依赖在需求描述里直写。

## 定位
<!-- 一段话：模块是什么、解决什么问题、在系统里处于什么位置 -->

## 角色与能力
| 角色 | 主要能力 |
|------|---------|

## 功能清单（硬约束）
> 4 列表 + 续行 rowspan：二级 / 三级 / 使用角色 / 需求描述。
> 字段口径、跨模块调用都直写进需求描述。

### [一级章节]
#### N · [三级功能]
| 二级 | 三级 | 角色 | 需求描述 |
|------|------|------|---------|
```

### 3.3 三个连锁判断（已答）

**Q1：quick-fix 引用 modulespec 描述"功能形态"——只看功能清单够不够？**

**够。** 字段口径已经按 PM-VIEW-RULES §5.1 内联进"需求描述"列，禁止另起字段表。砍掉的 Scope/页面/验收/本批不做跟"功能形态"无关。

顺带要改：quick-fix:142 措辞收紧成"项目级模块规格的功能清单（硬约束）"。

**Q2：跨模块依赖那节 doc-update 要不要兼管？**

**砍掉这节。** 三个理由：

1. 依赖关系本来就该在功能清单的需求描述里直写（"调用 X 模块的 Y 能力拿数据"）——单立一节会跟功能清单脱节、漂移
2. 单独一节就要给 task 工程合同新增 section + doc-update 加沉淀逻辑——为一节静态信息加一整条管道，不划算
3. 未来真要"全局依赖图"，从所有 modulespec 的功能清单批量提取就行

砍了之后 doc-update 一行不用动。

**Q3：task-execute 的"软指引"（推荐组件 / DESIGN.md 对齐 / 交互状态覆盖）要不要留？**

**砍掉，让 modulespec 只承担硬约束。** 软指引现在三类内容的真正归宿都不在 modulespec：

- 推荐组件 → DESIGN.md / 已有源码（设计系统层面统一）
- DESIGN.md 对齐 → 直接引用 DESIGN.md 章节就好
- 交互状态覆盖（空态/加载/异常/无权限）→ 通用规范应该在 DESIGN.md 里写一次

留的代价是：DESIGN.md / modulespec / 已有源码 三处都讲组件选择，长期不一致是必然的。

唯一损失：模块级特有的实现倾向（比如这个模块习惯用 pagination 不用 infinite scroll）无处安放——但要么有业务理由（写进功能清单需求描述），要么是历史习惯（读已有源码自然就一致），不必固化。

## 四、close-req 简化

> **术语澄清（v1.1）**：仓库里 **close-req 是 stage 7 的内部工作**（`scripts/close-req.sh:34` 校验 stage=7），不是 stage 6 也不是 stage 6→7 转换。下面说的"step 2a/2b"是 `skills/close-req/SKILL.md:103-161` 内部的两个步骤。

### 4.1 当前流程（stage 7 内部工作）

```
close-req（stage 7 工作）当前：
  step 1   写 close-report.md
  step 1.5 分流 SKIP marker
  step 2a  统计 doc-update 覆盖率 → 决议 A完整 / B跳过 / C补差 → 询问 PM 怎么写 req-prd
  step 2b  按决议跑 /project-prd-update 增量并入 docs/prd.md
  step 2c  检查 req 级实现深度变更
  ...
```

### 4.2 新流程

**砍 step 2a + 2b（保留覆盖率统计降级 lint）**——因为：

- project-prd 砍了，step 2b 没东西要"增量同步"
- req-prd 改成按需评审材料，不该在 close-req 关头硬要 PM 决定写不写（step 2a 三选项决议消失）
- doc-update 已经在每个 task 落地时把内容回填进 modulespec 了，close-req 不该再做合并
- **保留覆盖率统计**降级为只读 lint（D8 倾向 B）——doc-update 漏回填时的诊断信号

简化后 close-req 只剩：写 close-report + 归档 req（active → closed）+ 闭环检查 + 覆盖率 lint。

**与 stage 编号无关**：stage 6（task 执行）、stage 7（req close 期间执行 close-req）的语义都不变。req-stage-gate SKILL.md 也不动（它处理 transition gate，跟 close-req 内部步骤无关）。

## 五、完整改动清单（autoplan 修正后 16 项）

> **修正（autoplan F2-F7 + Codex-3/4/6/8/10）**：v1 列了 12 项，autoplan 评审增补 4 项 + 修正 5 个低估颗粒度。新清单：

| # | 文件 / skill | 操作 | 说明 |
|---|---|---|---|
| 1 | `templates/module.md.tmpl` | **大改** | **10 节 → 3 必填节 + typed optional blocks**（D10 待拍）—— 不是简单 3 节 |
| 2 | `skills/close-req/SKILL.md:103-161` | **大改** | 砍 step 2a + 2b 决议树和 project-prd-update 调用；**保留覆盖率统计降级为 lint**（D8 倾向 B） |
| 3 | `skills/project-prd-update/` | **标 deprecated → 1-2 周后硬删**（Q1：B + 短）| framework 切换后跑 1-2 个新 req 验证 OK 即删 |
| 4 | `templates/project-prd.md.tmpl` | **标 deprecated → 1-2 周后硬删**（Q1：B + 短）| 同上 |
| 5 | `skills/prd-writing/SKILL.md` | **小改**（Q3 拍简化）| 只改 3 处：触发地点 description / 删过时陈述 / 必读列表清理。**模板和产物结构不动**，9-11 章保留 |
| 6 | `skills/req-stage-gate/SKILL.md` | **不动** | req-stage-gate 处理 stage 间 transition gate，跟 close-req 内部步骤无关。要砍的 step 2a/2b 在 close-req SKILL.md（stage 7 工作）里，不在 req-stage-gate |
| 7 | `skills/task-execute/SKILL.md` | 小改 | 砍"软指引"段。**行号 275-276 不准（F2）**，搜"硬约束"/"软指引"定位 |
| 8 | `skills/quick-fix/SKILL.md:142` | 小改 | 措辞收紧 |
| 9 | `templates/req-prd.md.tmpl` | 小改 | 删 project-prd-update 同步那行；改"按需评审材料"提示 |
| 10 | `skills/_shared/pm-view/input-flow.md:149-151` | 清理 | **修正 v1 路径**（v1 写"_shared/...", 实际 "skills/_shared/..."）；stage 7.5 project-prd-update 段清理 |
| 11 | `scripts/init-project.sh:124` | 清理 | 不再初始化 `docs/prd.md`（**第三阶段**才执行，见 §十一） |
| 12 | 残留引用扫尾 | 清理 | `req-analysis / req-solution / publish-to-lark / doc-update / solution.md.tmpl` 里的 `docs/prd.md` 引用 |
| **13** | `templates/CLAUDE.md.tmpl:207`（**F5**） | 改/删 | 当前硬编码"docs/prd.md \| 持续维护"，与本设计直接冲突 |
| **14** | `tests/helpers/fixture.sh`（**F6**） | 改 | 当前初始化 docs/prd.md；新 fixture：无 docs/prd.md 项目 + 3 节 modulespec |
| **15** | `docs/modules/INDEX.md` 自动生成器（**D9**） | **新增** | 轻量产品地图，替代 project-prd 的 discoverability 角色 |
| **16** | PM 操作分流 cheat sheet（**D12**） | **新增** | "提需求 / 验收回填 / 评审派生 / 不手改" 单页规则；放 `docs/cheatsheets/` 或写进 README |

**新增改动（Q1 + Q2 拍板后追加）：**
- **#17 临时双解析器**：framework 内置 modulespec 新（3 节）+ 老（8/10 节）双格式解析器，让 adminconsole4 增量迁移期 task-execute 读到老格式 fallback 不报错。代码 ≤ 50 行，跟 deprecated 物一起 1-2 周后删
- **#18 全仓术语一致化**：grep "模块 spec / module spec / 模块说明 / module-spec" 等变体，统一改成"模块规格" / modulespec
- **#19 prd-writing 加硬规则**：PRD 不允许引入 modulespec 没有的字段/角色/能力 + 检测到时反向更新 modulespec
- **#20 modulespec 顶部刺眼提示**：`> ⚠️ 此文件 task-execute 当硬约束在用，PM 修改前请走 quick-fix / doc-update，不要直接编辑`

**新增高估算工作（动手前必做）：**
- **测试 impact matrix**（Eng-1 + Codex-7）：动手前 grep 测试目录里 `project-prd / step 2a / step 2b / docs/prd.md / 8 节 modulespec section name`，按 templates/scripts/tests/docs/runtime/readme 分组列全量引用，估"预计修改 N 个测试"
- **GO/NO-GO 实测**（D7 升级 + Codex-11）：在 adminconsole4 跑 prd-writing 派生 + source coverage report + golden regression

## 六、待拍判断

### 6.1 ~~stage 6 怎么处理~~ → **整段是伪命题，作废**（v1.1 修正）

> **根因**：v1 文档讨论从一开始就**用错了 stage 编号**。
>
> 仓库实际定义（`scripts/req-transition.py:11-19`）：
> - stage 6 = **task 执行**（PM 在做 task）
> - stage 7 = **req close**（执行 close-req）
>
> **要砍的 step 2a + 2b 在 close-req SKILL.md（stage 7 内部工作）里，跟 stage 6 完全没关系。** v1 讨论"砍 stage 6"是把 close-req 错标成 stage 6 引发的伪问题。
>
> **真正要做的**：
> - close-req 内部砍 step 2a + 2b（详见 §四 4.2）
> - prd-writing 不再被 close-req 强制调用，改成按需触发
> - **stage 6 / stage 7 语义都不动**
> - **req-stage-gate SKILL.md 不动**（它处理 transition gate，跟 close-req 内部步骤无关）
>
> **此小节作废**。原 6.2 prd-writing 输入范围保留（它本来就是独立问题）。

### 6.2 prd-writing 改造后输入范围怎么定

三种模式：

- 模式 1：`/prd-writing --req <req-id>` 写本 req 的评审 PRD
- 模式 2：`/prd-writing --module <module-name>[,<module>]` 在主分支写一个/多个模块的 PRD
- 模式 3：`/prd-writing` 走交互问 PM 想写什么范围

**建议三种都支持，模式 3 当 fallback。**

## 七、风险与取舍

### 7.1 砍 project-prd 的风险

- **风险**：未来如果需要"产品全貌"视图（对外 demo / 立项汇报），临时拼一份会不会很慢？
- **取舍**：modulespec 已经是结构化的（功能清单 4 列表），AI 拼 N 个 modulespec 成"全貌 PRD"是机械性工作，不慢。比起长期维护一份永远会漂的累积总览，按需派生更便宜。

### 7.2 砍软指引的风险

- **风险**：模块级特有实现倾向无处安放，可能导致同模块不同 task 实现不一致
- **取舍**：见 §3.3 Q3 末段——业务性的写功能清单，习惯性的读已有源码，都不需要固化在 modulespec。如果实操中出现问题，再加回。

### 7.3 PRD 不强制的风险

- **风险**：PM 在 close-req 时跳过 PRD，未来某天需要评审材料时要现做
- **取舍**：现做的成本就是跑一次 `/prd-writing --req <id>`——这次任务讨论已经表明 PM 在主分支也常这么用，不是新负担。

## 八、~~动手分批建议（v1 三 batch）~~ → §十一 三阶段 rollout

> **v1 错误**：建议 3 batch commit 一次性切换。
> **autoplan 发现**：Codex-7 + D11 强烈建议**三阶段 rollout**（不是 3 batch commit），每阶段独立测试 + 独立回滚点。
>
> **此小节作废**，新执行顺序见 §十一。

## 十、待 PM 拍板的关键决策（autoplan 增补）

> 完整 D1-D12 决策清单见 plan file `<LOCAL_CLAUDE_HOME>/plans/hashed-waddling-hummingbird.md` §十。
> 这里只列**必须 PM 决定才能 Phase B 动手**的 4 个关键问题。

### Q1【已拍：B + b + 短】Migration 策略

**PM 决议（2026-05-11）**：
- **B 一次切换**：框架代码（skill / template / script）一个 PR 切到新机制，不分阶段
- **b 增量迁移**：adminconsole4 已有 modulespec / docs/prd.md 现状冻结；新 req 触及到某模块时把该模块 modulespec 重写到新格式
- **短兼容期（1-2 周）**：framework 切换后跑 1-2 个真实 req 验证，OK 后删 deprecated 物

**AI 补的实现细节（auto mode 自决）**：
- framework 内置**临时双解析器**（新 3 节 + 老 8/10 节 modulespec 都能读），让增量迁移期间 task-execute 读到老格式不报错
- 双解析器跟 project-prd-update skill / templates/project-prd.md.tmpl 一起标 deprecated，**1-2 周后硬删**（不是无限期保留）
- 严格 b：只有新 req **主动改动需求**的模块才必须重写到新格式；只被 task-execute 读不改的老 modulespec 走 fallback 老解析器
- adminconsole4 完成 1-2 个新 req 后，PM 评估剩余老 modulespec 是否需要批量迁移（如果剩没几个，顺手做掉）

**实施位置**：
- framework PR（一次切换）：§五 16 项改动清单 + 加双解析器小工具（≤ 50 行）
- 不需要单独的"已有项目迁移路径"章节——增量迁移就是 PM 自己在跑新 req 时按 doc-update 流程做掉
- §五 #3 / #4：deprecated 期改"1-2 周后硬删"，不是"长期保留"

### Q2【已拍：不重命名 + 术语一致化 + 软防线】

**PM 决议（2026-05-11）**：
- 中文统一叫"**模块规格**"（仓库已在用的术语）
- 英文 modulespec 不动
- 文件路径 `docs/modules/<name>.md` 不动
- 实质：**不做物理重命名**，只做术语一致化 + 软防线防混淆

**含义**：D3 codex-2 的物理隔离思路被 trade 掉，换成两条软防线（双管齐下）：
- **软防线 a**（D3 选项 B）：`prd-writing` 加硬规则——PRD 不允许引入 modulespec 没有的字段/角色/能力，发现就反向更新 modulespec
- **软防线 b**（DX-1）：modulespec 文件顶部加刺眼提示 + skill 入口分流（PM 永远从 prd-writing 进，从不直接打开 modules/*.md 编辑）

**新增动作**：
- **#18 全仓术语一致化**：grep 全仓 "模块 spec / module spec / 模块说明 / module-spec" 等变体，统一改成"模块规格" / modulespec
- **#19 prd-writing 加硬规则**：在 prd-writing SKILL.md 加一段"PRD 不允许引入 modulespec 没有的字段/角色/能力"约束 + 检测到时反向更新 modulespec 的流程
- **#20 modulespec 顶部刺眼提示**：模板顶部加 `> ⚠️ 此文件 task-execute 当硬约束在用，PM 修改前请走 quick-fix / doc-update，不要直接编辑`

**风险（PM 已默认接受）**：6 个月塌回原状的概率比物理重命名方案高——靠两条软防线 + PM 纪律守住

### Q3【已拍：否决三套模板，prd-writing 改动降到最小】

**PM 决议（2026-05-11）**：
- "对目前的 prd 产出挺满意了" → 现有 9-11 章 PRD 模板继续用
- "尽量不要修改" → prd-writing skill 改动降到最小

**含义（auto mode 自决细节）**：
- **不写**三套模板（单 req / 单模块 / 多模块）
- **不加** `--module` / `--modules` 参数
- **不动** 模板章节结构、产物结构、写作规则
- 主分支生成"某几个模块 PRD" 走 PM 手动 prompt（PM 当前的真实工作流，不需要 skill 化）

**prd-writing 实际只改 3 件事**（最小化）：
1. **触发地点**：description / when-to-use 段从 "Stage 6 close-req 调用" 改成 "按需触发"
2. **删过时陈述**：description 里 "Produces a 9-chapter PRD by default (11 chapters when...)" 描述保留（产物不变），但删 "Do NOT use for the project-level cumulative PRD (`docs/prd.md`) — that is updated by `/project-prd-update`" 这段过时陈述
3. **必读列表清理**：删 `_shared/pm-view/input-flow.md` 里 prd-writing 必读列表的 `docs/prd.md`

**autoplan Q3 / D6 整套作废**——不再跟踪三种模板设计。

**风险（PM 已默认接受）**：未来想生成"模块 PRD"或"多模块协作 PRD"时模板套不齐（用 9-11 章硬套可能有些章节空），PM 评审场景接受这点

### Q4【已拍：做 + 中 + 切换前】PRD on-demand 实测

**PM 决议（2026-05-11）**：
- **做**：framework 切换前必跑实测
- **中级**：定义 PRD 输入优先级 + 跑 2-3 个模块实测 + 写简单 source coverage report（每个 PRD 字段标"来自 modulespec.X / DESIGN.md.Y"）
- **不建 golden regression**：长期维护负担太大
- **切换前**：Phase B 完成后立即跑，作为 GO/NO-GO 闸门，不通过则回头改设计再切

**实测内容**（auto mode 自决细节）：
1. **PRD 输入优先级定义**（设计活）：
   - 第一来源：`docs/modules/<module>.md`（功能清单 + optional blocks）
   - 第二来源：`docs/CONTEXT.md` + `docs/DESIGN.md`（业务背景 + 视觉规范）
   - 第三来源：相关历史 `requirements/closed/<req>/prd.md`（业务包装层 / 决策 why）
   - 不读：task 工程合同 / engineering.md（PM 视图链路最终交付层不取工程层细节）
2. **跑 2-3 个 PRD 实测**（Q3 简化后调整）：
   - 1 个简单模块 PRD（9-11 章模板，PM 手动 prompt prd-writing 指定单模块为范围）
   - 1 个复杂模块 PRD（含状态机或权限矩阵）
   - 1 个常规 req-prd（标准 prd-writing 使用方式，验证现有流程仍然工作）
3. **source coverage report**：PRD 每节末尾加 `<!-- 来源：modulespec §X / DESIGN.md §Y -->` 注释，PM 检查覆盖率
4. **PM 主观评分**：可读性 / 完整性 / 业务正确性 三项 1-5 评分

**通过标准**：3 个实测 PRD 全部 ≥ 4 分 + source coverage 无字段标"hallucinated 来源"

---

## 九、对话关键节点（可追溯）

按时间顺序（同一会话内）：

1. PM：发现不需要 project-prd，每个 req 一份完整 prd 就行；modulespec 作用迷惑
2. AI：第一轮诊断—— modulespec 是跨 req 累积视图、project-prd 多余、可以砍；问 PM 砍法
3. PM：澄清——一个 req 同时改多个模块、某模块改得少、可能改旧产出；问 modulespec 作用
4. AI：第二轮诊断翻面——这三场景反过来证明 modulespec 必要；真正问题是 req-prd 被当成 modulespec 写了
5. PM：再翻——prd-writing 没问题；req-prd 是评审材料，可以脱离 req 在主分支生成；再问 modulespec 作用
6. AI：第三轮诊断收敛—— modulespec 是底层 source of truth，服务工程实施 + 真相累积 + PRD 底料，不服务 PM 评审；分两层（底层持久 + 上层临时派生）
7. PM：同意分层；问 modulespec 内容怎么设计
8. AI：模板从 8 节简化到 3 节；列三个连锁判断
9. PM：三个连锁问题让 AI 自己想
10. AI：三个都答"砍"；列 12 项改动清单 + 2 个待拍判断
11. PM：问 close-req 是不是也要改
12. AI：是，是改动最大的一处；step 2a + 2b 整段砍
13. PM：把整体方案先写进文档 → 本文档 v1
14. PM：跑 /gstack-autoplan 评审本文档
15. AI：autoplan 评审（Explore 事实核查 + Claude subagent 三视角 + Codex 对抗）发现 14 条 finding（3 critical / 8 high）
16. PM：approve 评审 plan + auto mode
17. AI：把机械修正应用到本文档（F1-F8 / D5 翻面 / 16 项改动清单 / 三阶段 rollout 标识 / Q1-Q4 待 PM 拍）
18. PM：指出 stage 理解还有问题（"task 有自己的 stage，req 也有自己的 stage"）
19. AI：v1.1 修正 —— 仓库 stage 定义本身清楚（`req-transition.py:11-19` STAGE_NAMES），是 v1 文档误把 close-req（stage 7 工作）标成 stage 6。§四 / §五 / §六 6.1 全部按"close-req 是 stage 7 内部工作"重写；术语统一（req stage 用数字，task status 用文字）
20. PM：建议 stage 用整数（req）+ 小数（task）做术语公约 → 出 A2 决策（单独文档）
21. PM：拍 Q1（B + b + 短）/ Q2（不重命名 + 模块规格 + 路径不动）/ Q3（否决三套模板，prd-writing 最小改）/ Q4（做 + 中 + 切换前）；AI 接管 D4 / D8 / D10 / A2
22. PM：D8 解释完后追问"什么是半关闭 / task 直接修改 modulespec 吗"；AI 解释半关闭 + task → modulespec 链路（task close → close-task 调 doc-update settlement mode）
23. PM：基于"后续 task 或 quickfix 改前 task 工作"场景，提议 task close 不写 modulespec，等 req close 时一起写
24. AI：把当前 framework 三种写入路径（settlement / 对账 / rewrite）摆出来，说明 PM 提议本质 = "改成 rewrite-only"；列 trade-off
25. PM：选 B（rewrite-only），但要求先写进文档 review
26. AI：写 §十二 D13 rewrite-only modulespec 维护方案 —— 工作流 / 砍掉的机制 / INVARIANTS 影响 / 5 个待 review 开放问题 / D13 通过后 §五 追加 7 项

---

## 十二、rewrite-only modulespec 维护方案（D13，v2）

> **版本**：v2（2026-05-11）。v1 推倒重写。
> **状态**：方案待 PM 拍板。本节包含 C1/C2/C3 三个 critical 设计 + 完整改动清单。
> **若 PM 通过**：替换 §3.2 / §四 / §五 相关章节。

### 12.1 决策背景

**PM 痛点**（2026-05-11 澄清后）：不是 modulespec 有陈旧痕迹，而是 **token 浪费**。

浪费来源 = N 次 doc-update × 单次完整成本（skill 指令加载 + modulespec 读 + PM 视图读 + AI 推理 + 写回），覆盖所有维度：
1. 每次 settlement / 对账都重新读整份 modulespec + skill 指令
2. 多 task 改同一处时重复 patch 同段内容
3. 多 task 触发多次 close-task → 每次都过完整 doc-update 流程

**D13 方向**：N 次合并成 1 次——task close 时不写 modulespec，等 req close 时一次性 rewrite。

**关键观察**：rewrite mode 已存在（`skills/doc-update/SKILL.md` §8），现在是 fallback（close-req §1.5 检测 ≥2 SKIP marker 才触发）。**D13 本质是把这个 fallback 升 default**，不是新写机制。

### 12.2 新工作流

```
stage 6（task 执行期间）
  ├ task A close → 只 merge + 归档，不写 modulespec
  ├ task B close → 同上
  ├ quickfix    → 改原型 / 写结构化 metadata（C3 新机制）；docs/modules/* 不直接改
  └ ... 所有 task 完成

stage 6 → 7 gate
  └ req-stage-gate：所有 task 已 close + worktree 清理
     （半关闭概念消失）

stage 7（close-req 内部）
  ├ 步骤 1   写 close-report.md
  ├ 步骤 1.5 砍（无 SKIP marker 分流——D13 下所有 task 隐式 skip）
  ├ 步骤 2   ★ 必跑 doc-update rewrite mode（C2 包裹原子性）
  │         输入 = 持久 modulespec + 本 req 所有 task PM 视图 + 本 req quickfix metadata
  │         按模块聚合 → 整段 rewrite docs/modules/<module>.md
  │         PM 审 diff（逐章节）
  ├ 步骤 3   实现深度变更检查
  └ 步骤 4   归档 req + merge req 分支到 main
```

### 12.3 砍掉的机制清单

| 机制 | 位置 | 影响 |
|---|---|---|
| **settlement mode** | `skills/doc-update/SKILL.md` §1.7 | doc-update 不再被 close-task 调用 |
| **对账模式** | `skills/doc-update/SKILL.md` §1.5 / §1.6 | task close 时不再做行级对账 |
| **半关闭机制** | `skills/close-task/SKILL.md` `--skip-doc-update` flag | 整套砍：flag + reason 参数 + SKIP_DOC_UPDATE marker + cleanup_status 字段 + 人工 Cleanup TODO 写入逻辑 |
| **req-stage-gate 半关闭检测** | `skills/req-stage-gate/SKILL.md:308-344` | 简化 stage 6→7 gate 为"所有 task 已完成 + merged + worktree cleaned" |
| **D8 覆盖率统计** | `skills/close-req/SKILL.md` step 2a | 自然失效（监控对象消失） |
| **close-task 调 doc-update** | `skills/close-task/SKILL.md` 步骤 2 | 直接 merge + 归档 |
| **doc-update §0.5 沉淀风险判断** | `skills/doc-update/SKILL.md` | settlement 砍后无意义 |

doc-update 保留：
- **§8 rewrite mode** —— 升为 close-req 默认调用路径
- **§1.7.3 多模块 atomic merge** —— rewrite mode 也依赖

---

### 12.4 三个 critical 设计

#### 12.4.1 C1 — task-execute 在 active req 内读什么

**问题**：D13 下 `docs/modules/*.md` 只在 close-req 时更新。本 req 内 task A close 后，task B 执行时读什么知道 task A 改了什么？

**现状**（已部分存在）：
- `skills/task-execute/SKILL.md:290` 步骤 2.1 已包含"同模块已完成 task 的 PM 视图 + 工程合同（两文件都读，复用经验、避免重复）"
- `skills/_shared/pm-view/input-flow.md` §9.4 已规定 PM 反馈四类分流

**D13 下要做的**（不是新建 overlay 文件，是**正确叠加**已有必读）：

| 来源 | 角色 | 读取方式 |
|---|---|---|
| `docs/modules/<module>.md` | 持久 modulespec（反映上次 close-req 状态） | 完整 Read |
| 同 req 内同 module 已 close task 的 PM 视图主文件 | 本 req 内中间状态叠加 | 完整 Read，按 close 时间顺序 |
| 本 req `quickfix-log` 中 `module=<module>` 且 `needs-modulespec-update=true` 的条目（C3 新机制） | 本 req 内原型/文档增量 | 完整 Read，按时间顺序 |

合并语义：modulespec 是基线，task PM 视图按顺序叠加，quickfix 按顺序叠加。冲突时**后写覆盖前写**（time-ordered last-writer-wins）。

**实施清单**：
1. `skills/task-execute/SKILL.md:281-297` 步骤 2.1 加 D13 模式说明 + 叠加顺序
2. `skills/task-spec/SKILL.md` 加约束：拆 task 时识别本 req 内同 module 的已 close task，在工程合同 §3 启动前必读列表里列出
3. `skills/_shared/pm-view/input-flow.md` §9.4 加 D13 注解（明确"本 req 已 close task PM 视图"是 task-spec / task-execute 都要读的，不只 close-task）
4. 不新增 overlay 文件（避免引入新持久化）

**约束**：本设计依赖 task-spec 在拆分时正确识别 module 影响范围。如果 task-spec 漏标 module，task-execute 会读不到必要的本 req 上下文 → 加 lint：拆分时若 task 触及某 module 但 module_impact 字段空，警告 PM。

---

#### 12.4.2 C2 — close-req rewrite 原子性

**问题**：D13 把 N 次 settlement 合并成 1 次 rewrite。rewrite 在 close-req 流程中失败（AI 推理错误 / PM 拒绝某章节 / 网络中断），如何避免 close-req 留下半状态？

**现状机制不够**：
- `skills/doc-update/SKILL.md` §8 内部已 atomic（要么全章节通过，要么退回）—— 但只覆盖 doc-update 自身
- `INVARIANTS.md` I-CR5-7 规定 close-req 顺序：req 分支 commit 状态 → merge main → 清理 —— 没有"rewrite 必须先完成"的约束
- I-CR9 已说"close 失败不能留下半完成状态"——但当前 close-req 没插入 rewrite 步骤，这条 invariant 没覆盖 rewrite 失败场景

**设计**：

```
close-req 步骤 2（rewrite 包裹层）：

1. 记录 pre-rewrite checkpoint：
   $ git rev-parse HEAD > .runs/close-req-rewrite-checkpoint
   $ echo "{ts, head, req}" >> events/close-req.jsonl

2. 调 doc-update rewrite mode（§8）

3a. rewrite 成功 → 继续后续步骤
3b. rewrite 失败 / PM 拒绝 / 中断：
    $ git reset --hard <pre-rewrite HEAD>
    $ rm .runs/close-req-rewrite-checkpoint
    $ exit 1（保持 req stage=7、req 留在 active/、PM 可改后重试 /close-req）
```

**新 INVARIANTS**：

| INVARIANT | 内容 |
|---|---|
| **I-CR10** | close-req 必须先成功完成 rewrite mode（§8 退出码 0）才能继续步骤 3+（实现深度检查、归档、merge main） |
| **I-CR11** | rewrite 失败 → 必须 reset 到 pre-rewrite checkpoint HEAD，req 保留 active/、stage=7；不允许进 closed/ |
| **I-CR12** | pre-rewrite checkpoint 文件存在但 rewrite 未跑完 → 视为"上次失败未清理"，close-req 入口提示 PM 选择 retry / abort 并清理 |

**实施清单**：
1. `scripts/close-req.sh` 加 checkpoint 记录 + reset 回滚逻辑（line ~54-88 当前 req 分支操作前后）
2. `INVARIANTS.md` `close-req.sh` 节加 I-CR10/11/12 + 守卫点行号
3. `skills/close-req/SKILL.md` 步骤 2 加 checkpoint / 回滚说明
4. `tests/` 加用例：rewrite 失败 → req stage 不进 closed / checkpoint 文件存在时入口提示

---

#### 12.4.3 C3 — quickfix 结构化元数据

**问题**：D13 rewrite mode 要消费 quickfix log。当前 quickfix 是自由文本 commit message + `[quick-fix-log]` 提交，rewrite 时 AI 无法可靠提取"改了哪个 module 的哪个 feature / 需要同步进 modulespec 吗"。

**当前格式**（`skills/quick-fix/SKILL.md` 步骤 4 / 步骤 5）：
- 两个 commit：`[quick-fix]` 改动 + `[quick-fix-log]` 日志
- log 内容是自由文本

**新 schema**（quick-fix 步骤 4 commit 前生成 + PM 确认）：

```yaml
# requirements/active/<req>/quickfix-log.jsonl 每行一条
{
  "ts": "2026-05-11T14:23:00Z",
  "type": "quickfix",
  "commit": "<quick-fix commit sha>",
  "summary": "改筛选默认排序为按时间倒序",
  "module": "log",                    # 受影响模块；纯文案/无影响时 null
  "feature": "列表筛选",               # 受影响 feature（free text，对应 modulespec 功能清单条目；module=null 时也为 null）
  "change-type": "modify",             # add / modify / remove / behavior-only / null
  "needs-modulespec-update": true      # rewrite mode 是否消费；null 时默认 false
}
```

**字段含义**：
- `module`：null 表示"不影响任何模块规格"（纯原型微调 / 文案修改 / DESIGN.md 微调）
- `change-type`：`behavior-only` 表示行为变化但 modulespec 文字不变（如调默认排序方向）→ rewrite 时仍需 PM 决定要不要写
- `needs-modulespec-update`：PM/AI 联合决定。AI 在 quickfix 步骤 3.5 偏差扫描后建议初值，PM 在步骤 4 commit 前确认

**rewrite mode 消费逻辑**（doc-update §8 修订）：
1. 读 `requirements/active/<req>/quickfix-log.jsonl`
2. 筛选 `needs-modulespec-update: true` 条目
3. 按 module 分组，并入对应 module 的 rewrite 输入（与 task PM 视图同等地位）
4. 时间排序合并（与 C1 叠加规则一致）

**老 quickfix 兼容**：
- D13 上线前的 quickfix（无 metadata）：rewrite mode 降级处理—— AI 读 `[quick-fix-log]` commit message + 当前原型 diff 推测影响，**并在 rewrite 前向 PM 显式提示"以下旧格式 quickfix 需要 PM 人工指认 module/feature"**
- 增量迁移：D13 上线后新 quickfix 强制填新字段（lint）；旧条目保持原状

**实施清单**：
1. `skills/quick-fix/SKILL.md` 步骤 3.5（偏差扫描）输出后 / 步骤 4 commit 前加 metadata 填写步骤
2. `scripts/quick-fix.sh`（如存在）或 quick-fix 脚本：生成 metadata template + PM 确认交互
3. `templates/quickfix-log.schema.json` 新建 JSON Schema（lint 用）
4. `skills/doc-update/SKILL.md` §8 加 quickfix log 消费段落
5. `scripts/check-prd-hierarchy.py` 或新 lint：commit 前校验 quickfix-log.jsonl 条目符合 schema
6. `tests/` 加测试：缺字段 / 老格式降级 / rewrite 输入合并

---

### 12.5 INVARIANTS 影响（修正 v1 错误 + 新增）

| INVARIANT | 当前 | D13 后 |
|---|---|---|
| **I-CT2** | 前置条件 = task worktree clean / 分支存在 / req 分支存在 / req worktree 存在（**不含 "doc-update 已完成"**） | **不变**（v1 §12.5 描述错误，实际 I-CT2 本就不含 doc-update prereq） |
| **I-CT3-8** | 不变 | 不变 |
| **I-CR1-9** | close-req 流程 | 不变 |
| **I-CR10** | （新增） | rewrite mode 必须先成功才能继续步骤 3+ |
| **I-CR11** | （新增） | rewrite 失败 → reset 回 pre-rewrite HEAD，req 保留 active/、stage=7 |
| **I-CR12** | （新增） | 存在残留 checkpoint → close-req 入口提示 retry/abort |
| **I-TT** | 不变 | 不变 |
| **I-CB10** | 不变 | 不变 |

### 12.6 D13 改动清单（替代 v1 §12.7）

| # | 文件 / skill | 操作 | 关联 |
|---|---|---|---|
| 21 | `skills/close-task/SKILL.md` | 砍 --skip-doc-update flag + 砍调 doc-update 步骤 + 砍 SKIP marker / cleanup TODO 写入 | D13 主流程 |
| 22 | `skills/doc-update/SKILL.md` | 砍 settlement（§1.7）/ 对账（§1.5/1.6）/ 沉淀风险（§0.5）；§8 rewrite mode 升 default；§8 加 quickfix log 消费段 | C3 + 主流程 |
| 23 | `skills/req-stage-gate/SKILL.md:308-344` | 简化 stage 6→7 gate：砍 half-close detection | D13 主流程 |
| 24 | `skills/close-req/SKILL.md` | 步骤 1.5 改：不依赖 SKIP marker，默认调 rewrite；步骤 2 加 pre-rewrite checkpoint + 回滚 | C2 |
| 25 | `scripts/close-req.sh` | 加 checkpoint 记录 + git reset 回滚 + 残留 checkpoint 入口检测 | C2 |
| 26 | `INVARIANTS.md` | 新增 I-CR10/11/12；修正 v1 关于 I-CT2 的描述 | C2 |
| 27 | `skills/quick-fix/SKILL.md` | 步骤 4 commit 前加 metadata 填写步骤 | C3 |
| 28 | `scripts/quick-fix.sh`（或对应脚本） | 生成 metadata template + lint | C3 |
| 29 | `templates/quickfix-log.schema.json` | 新建 JSON schema | C3 |
| 30 | `skills/task-execute/SKILL.md:281-297` | 步骤 2.1 加 D13 模式说明 + 叠加顺序 | C1 |
| 31 | `skills/task-spec/SKILL.md` | 拆 task 时识别 module 影响范围 + 工程合同 §3 必读列出同 req 已 close task | C1 |
| 32 | `skills/_shared/pm-view/input-flow.md` §9.4 | 加 D13 注解：本 req 已 close task PM 视图是 task-spec / task-execute / close-req 都要读 | C1 |
| 33 | 测试套件 | grep `settlement / 对账 / SKIP_DOC_UPDATE / cleanup_status / half-close`，逐个改/删 | D13 主流程 |
| 34 | `tests/` 新增 | C2 atomic 用例 + C3 schema lint 用例 | C2 + C3 |

### 12.7 待 review 的开放问题（v2 修订）

| # | 问题 | v1 状态 | v2 处理 |
|---|---|---|---|
| 1 | rewrite mode 的 PM 工作量（每次 close-req 都审 diff） | 开放 | **仍开放**——PM 要拍接受默认逐章节审 vs 简化"默认接受+PM 主动审" |
| 2 | 跨 req 连续修改 task-spec 读什么 | 部分答 | **C1 已答**（叠加规则 + lint） |
| 3 | active req 期间主分支跑 prd-writing | 开放 | **Q4 已拍接受 trade-off**（main 分支 PRD 永远是 stable state） |
| 4 | close-req 失败 blast radius | 仅建议方向 | **C2 已答**（pre-rewrite checkpoint + 回滚 + 3 条 invariant） |
| 5 | 测试套件影响升级（settlement / 半关闭测试） | 估算待定 | **§12.8 加 pre-flight grep 任务** |

### 12.8 实施前 pre-flight（必跑）

D13 决定动手前必须先做：

- [ ] **grep 测试套件**：`grep -rn "settlement\|对账\|SKIP_DOC_UPDATE\|cleanup_status\|half-close\|skip-doc-update" tests/ scripts/tests/` —— 估算改动量（v1 估"少数"，v2 怀疑"几十个"）
- [ ] **GO/NO-GO token 实测**：在 adminconsole4 跑一次模拟 rewrite mode（手动触发 close-req §8），掐 input/output token + PM 主观评分。对比同样输入跑 N 次 settlement 的累积 token。决策：rewrite 收益是否随 N 线性放大（如果 N=1 时 rewrite 反而更贵，需要 fallback 策略）
- [ ] **C3 schema 评审**：metadata schema 设计稿先内部 review（特别是 `change-type` 枚举是否够用），避免发出后返工
- [ ] **C2 atomic 测试**：补 `tests/` 用例（rewrite 中断 / pre-rewrite HEAD 回滚 / req stage 不进 closed / 残留 checkpoint 入口提示）
- [ ] **C1 lint 测试**：task-spec 漏标 module 触发 lint 警告
- [ ] **跑 /gstack-autoplan 第三轮**（覆盖 C1/C2/C3）：本节写完后再走一遍对抗式评审，捕获盲点

---

## 十一、修正后的执行顺序（替代 v1 §八）

> 详见 plan file `<LOCAL_CLAUDE_HOME>/plans/hashed-waddling-hummingbird.md` §十一。

**Phase A（已完成）**：本文档机械修正
- ✅ F1-F8 事实修正应用
- ✅ §六 6.1 作废（伪命题：要砍的 close-req step 2a/2b 在 stage 7，不在 stage 6）+ §四 加术语澄清
- ✅ §五 改动清单 12 项 → 16 项 + 标 deprecated 而非硬删
- ✅ §八 v1 三 batch 作废，转 §十一 三阶段 rollout
- ✅ §十 加 Q1-Q4 待 PM 拍

**Phase B（等 PM 答 §十 Q1-Q4 后做）**：v2 文档完善
- 补 §3.2 modulespec 模板：3 必填节 + typed optional blocks registry（待 D10）
- 补 §3.2 跨模块依赖标注规则（待 D4 升级版）
- 补 §3.2 "决策锚点"行（CEO-2）
- 补 §3.3 重命名 Module Contract 评估（待 Q2）
- 补 §6.2 三种产出模板草图（待 Q3）
- 补 §五加：覆盖率统计降级 lint（D8）/ INDEX.md 自动生成（D9）/ PM 操作分流 cheat sheet（D12）
- 补一节 §七.4：Migration 字段映射表 + docs/prd.md 处置（待 Q1）

**Phase B.5（GO/NO-GO 闸门，Q4 已拍）**：在 Phase B 后、Phase C 前
- 定义 PRD 输入优先级
- adminconsole4 跑 2-3 个模块实测 + source coverage report + PM 评分
- 通过标准：全部 ≥ 4 分 + 无 hallucinated 来源
- **不通过则回头改 §3.2 设计再重跑**

**Phase C（GO/NO-GO 通过后）**：动手实施
- 测试 impact matrix（grep + 分组列）
- **一个 PR 切换** framework（Q1 已拍 B）+ 内置临时双解析器
- 切换后跑 1-2 个真实 req 验证 → 删 deprecated 物（Q1 已拍 短）

---

## 十三、Round 3 autoplan 评审结论 + D13 v3 任务清单（2026-05-11）

> **范围**：仅评 §十二 v2（C1/C2/C3），不重复 round 1/2 覆盖。
> **方法**：Codex 对抗视角 + Claude subagent 独立工程视角并行评审。
> **PM 拍板（2026-05-11）**：D13 v2 不直接实施，进入 v3 设计回合补 4 critical + 6 high，写完跑 round 4 autoplan 验。

### 13.1 双方共识 critical（两个独立视角都指出）

| # | 缺陷 | 涉及 | 根本问题 | 修复方向 |
|---|---|---|---|---|
| **CR-1** | LWW 叠加语义不成立 | C1 | PM 视图是快照不是 delta；time-ordered 覆盖会把 task A 的有效改动错丢；同 anchor 不同结论靠时间排序覆盖丢内容 | 改 3-way merge：`base modulespec + task delta + 当前累积态`，同 anchor 不同结论进**冲突门**而非按时间覆盖 |
| **CR-2** | `git reset --hard` 不是原子回滚 | C2 | `.runs/` 在 `.gitignore` 里 reset 不到；untracked 新 modulespec 文件 reset 不到；doc-update `doc-update-settle/*` temp branch 不会被清；checkpoint 文件自己也是 untracked | 改**隔离 temp worktree/branch 内 rewrite**，全部通过后 fast-forward。或必须给 scoped 清理列表（temp branch enumerate + truncate `.runs/events/close-req.jsonl` 到 pre-rewrite 行数 + checkpoint 最后删） |
| **CR-3** | 跨模块原子性缺口 + PM 部分接受未定义 | C2 | doc-update §8 没有跨模块 atomic 内部约束；PM 接受 module A 拒绝 module B 时是全量回滚还是保留 A 未定义；C2 仅靠外层 reset 救场 | 显式锁定：**所有模块审批完成才写入目标分支**；或拆 per-module transaction 但 req 必须全模块成功才可 close。§8 自身要么用 1.7.3 temp branch 内部 atomic，要么显式声明依赖外层 C2 |
| **CR-4** | `change-type=remove` 不可执行 | C3 | `feature` 是 free text，rewrite 时 AI 无法可靠定位 4 列表格哪行该删；fuzzy 匹配 = 静默失败模式（无匹配 = 不删 = 鬼影 feature） | 二选一：(a) 加 `feature_id`（stable hash）字段，强制精确定位；(b) 砍 `change-type=remove`，删除一律走 close-req PM 审 diff 章节级触发 |

### 13.2 单方 high（互补或共识）

| # | 缺陷 | 涉及 | 修复方向 |
|---|---|---|---|
| **H-1** | 时间排序键不稳 | C1 | 用 **git commit topo order on req branch**（不依赖 wall clock ts）；JSONL `ts` 降级为显示用 |
| **H-2** | 模块身份模型不够 | C1+C3 | 加 `module_aliases` 表到 `.req-meta.json`；C3 `module` 改 `[<module>, ...]` 多值数组；漏标必须 block close-req rewrite 而非 warn |
| **H-3** | C3 schema 缺字段 | C3 | 补 `schema_version` / `supersedes: <prev sha>` / `affected_paths` / `confirmed_by` / `confirmed_at` |
| **H-4** | close-req mutation 边界 | C2 | checkpoint 在 close-req **第一处写操作前**记录；入口 worktree 必须 clean 或精确 auto-commit；I-CR12 stale checkpoint 检测要 req+HEAD 双重验证（避免 cancel-req 后误判） |
| **H-5** | Token break-even 未计算 | Cross | 加 fallback：`N=1 且零相关 quickfix → 走 settlement-patch 而非 rewrite`；pre-flight 实测要给 break-even 阈值 |
| **H-6** | task→module 映射函数缺失 | Cross | 必须设计 `scripts/list-req-module-impact.sh`（或等价）：输入 req-id，输出 task→modules + quickfix→modules；C1/C2/C3 都消费它，是基础设施 |

### 13.3 共同根因

D13 说"把 N 个状态合并成 1 个最终状态"，**但没把 merge 函数写下来**。
- LWW 是声称但不能成立的承诺
- 部分回滚（C2）声称 atomic 但缺清理列表
- 跨模块 / change-type=remove 都是"AI 猜"
- task→module 映射是 C1/C2/C3 都依赖的基础设施，但 0 设计

**v3 入口**：先把 merge 函数公式 + 每种 change-type 的 worked example + task→module 映射脚本写下来。这是其他 v3 设计的依赖根节点。

### 13.4 v3 任务清单（按依赖顺序）

**Foundation — 基础设施**（必先做，是其他 v3 task 的依赖）

| Task | 描述 | 依赖 |
|---|---|---|
| **V1** | task→module 映射脚本（C1/C2/C3 都依赖；输入 req-id，输出 task→modules + quickfix→modules） | — |
| **V2** | 全局时间序定义（git commit topo order on req branch 替代 wall clock；写进 §十二 v3 + 各 skill 必读约束） | — |

**C1 v3 — merge 函数**

| Task | 描述 | 依赖 |
|---|---|---|
| **V3** | merge 函数公式（feature-key set-union + 同 anchor 冲突进显式冲突门；每种 change-type 写一个 worked example：add/modify/remove/behavior-only/null） | V1 |
| **V4** | 模块身份模型（`.req-meta.json` 加 `module_aliases` 表 + rename 检测；C3 `module` 改数组） | V1 |
| **V5** | task-spec module_impact 强 lint（field 进 task md 元数据；check-script 在 task dispatch gate 失败时阻断；不只是 warn） | V1+V4 |

**C2 v3 — 隔离 worktree + 边界锁死**

| Task | 描述 | 依赖 |
|---|---|---|
| **V6** | 隔离 temp worktree/branch 内 rewrite（消除 .runs/ / untracked 残留风险）；或显式 scoped 清理列表（temp branch enumerate + event log truncate + checkpoint last-delete） | — |
| **V7** | close-req mutation 边界锁死（checkpoint 位置在第一处写操作前；入口 worktree dirty gate；现有 close-req.sh active→closed/ commit 位置可能要后移到 rewrite 成功后） | V6 |
| **V8** | PM 部分接受语义（全模块审批完成才写入 OR 显式 per-module transaction；写进 §8 + I-CR10/11 详化） | V6 |
| **V9** | I-CR12 stale checkpoint 检测（req 匹配 + HEAD 可达性双重验证；避免 cancel-req 后误判） | V7 |

**C3 v3 — schema 完整化**

| Task | 描述 | 依赖 |
|---|---|---|
| **V10** | `feature_id`（stable hash）字段 + remove 强制精确匹配；或砍 remove 走 PM 审 diff | V4 |
| **V11** | `schema_version` / `supersedes` / `affected_paths` / `confirmed_by/at` 字段补全；`module` 改数组 | V4 |
| **V12** | `needs-modulespec-update=false` 二次验证（close-req 入口 grep `[quick-fix]` commits 反查 prototype/modules diff，可疑条目让 PM 二次确认） | V11 |
| **V13** | 老 quickfix downgrade 上限（≤5 条 / close-req；超限 fail 提示走 `/quickfix-backfill`）+ 显式 "defer / skip" 选项（带 audit marker） | V11 |

**Cross-cutting**

| Task | 描述 | 依赖 |
|---|---|---|
| **V14** | Token break-even 算法 + N=1 fallback 策略（写进 §12.1 + §12.8） | V1 |
| **V15** | 测试 fixture（rewrite 失败 + retry + 残留无 + 跨模块 partial + change-type=remove 端到端 + 老 quickfix downgrade） | V6-V13 |

**Multi-req parallelism — 新发现的 critical 维度（2026-05-11 PM 确认必做）**

PM 确认日常在 adminconsole4 经常多 req 并行改同模块。当前 D13 v2/v3 全都是单 req 视角，**没有任何 task 处理多 req 并行**。

**真实链路**：

```
T0  main: modulespec = X
T1  req A 起来 (branch off main)         req A 分支: X
T2  req B 起来 (branch off main)         req B 分支: X
T5  req B close-req → rewrite → X'      req B 分支: X'
T6  req B merge main                     main: X'
T7  req A 还在跑                          req A 分支: 还是 X（没 pull main）
T8  req A 内 task A2 起来 → 看的是 X（旧的，不知道 X' 存在）
T9  req A close-req → rewrite 输入 = X + task PM 视图 → 输出 X+A
T10 req A merge main → X+A vs X' → git 冲突
```

**两个独立危害**：
1. **T8 信息盲**：req A 期间 PM/AI 不知道 req B 改了 module M（task A2 可能重做了 B 已做的事 / 跟 B 的设计冲突而不知）
2. **T10 合并冲突放大**：rewrite 整段重写比 settlement 行级 patch 更难合 git 冲突

⚠️ 这问题不是 D13 引入的——settlement-first 也有同样链路。但 D13 让冲突更难合（整段 vs 行级），所以 D13 必须直面这个问题。

| Task | 描述 | 依赖 |
|---|---|---|
| **V16** | 多 req 并行 modulespec 演进策略（PM 已拍方向 (e)，close-time detection + AI 助理合并）；含 active req 期间感知其他 req close 的机制 + close-req 时 base 选择策略 + 合并冲突解决约定 | V1 + V3 + V7 |
| **V17** | 同 req 内 task 过程中的并行盲点（task A2 起来后 task A1 close 不可见 / task A1 起来后 quickfix 改 modulespec / task worktree 跟 req 分支漂移）；同根 V16，不同表现层 | V1 + V3 |

**V16 / V17 方向**：PM 2026-05-11 拍板方向 **(e) Close-time detection + AI 助理合并**（a/b/c/d 作废）。详见 §13.11 + §14.7。

**C4 — quickfix 重定位**（§13.10 拍板后并入 v3 任务清单）

| Task | 描述 | 依赖 |
|---|---|---|
| **C4.1** | C3 schema 扩展：加 `target_origin_req` / `recorded_in_req` / `modulespec_patch`（结构化 patch instructions） | V11 |
| **C4.2** | quickfix 写 modulespec 的协调机制：quickfix 直接 patch modulespec；已起 task worktree 读 snapshot 不受影响；后起 task 看新 modulespec | V3 + C4.1 |
| **C4.3** | close-req rewrite 消费 quickfix 改动的逻辑：rewrite 输入区分"待应用 patch（task PM 视图）"vs"已应用 patch（quickfix 实时写）"；避免重复 / 冲突 | C4.1 + V3 + V7 |
| **C4.4** | quickfix 改历史 req 产物的归因：modulespec 行级 / feature 级标注"来源 req"；quickfix 记录 `target_origin_req` 让审计可追溯 | C4.1 |
| **C4.5** | PM 在 active req 中"记录"quickfix 改动的 UX：quickfix log 入口设计（PM 视图里能看见，不只在 jsonl 翻） | C4.1 |

### 13.5 v3 工作量预估（含 V16/V17 + quickfix 重新定位）

- **Foundation（V1-V2）**：1-2 小时（脚本设计 + 时间序约束公约写文档）
- **C1 v3（V3-V5）**：3-4 小时（merge 函数公式最重 + worked example × 5 + lint check）
- **C2 v3（V6-V9）**：3-4 小时（temp worktree 设计最重 + 边界锁死改 close-req.sh + invariant 详化）
- **C3 v3（V10-V13）**：2-3 小时（schema 补字段直接 + 验证机制设计）
- **Cross-cutting（V14-V15）**：2-3 小时（break-even 算法 + 测试 fixture 设计）
- **Multi-worktree（V16+V17）**：4-6 小时（多 req + 同 req 内 task 并行盲点，合并设计；如选 (d) rebase 工作量进一步加大）
- **quickfix 重定位（C4 新设计）**：3-5 小时（推翻 §13.7 旧 rationale；C3 schema 扩展 target_origin_req / recorded_in_req；quickfix 写 modulespec 跟 task-execute 合同稳定的协调机制；跟 D13 rewrite-only 边界关系）

**总计**：18-29 小时。

### 13.6 v3 完成后

1. 跑 **round 4 autoplan** 验 v3（焦点：merge 函数公式是否覆盖所有 change-type + temp worktree 是否真消除残留 + task→module 脚本是否完整 + V16 多 req 策略是否真能落地）
2. 通过后才进入 §11 Phase C 实施 phase
3. 如 round 4 仍有 critical → 继续 v4 设计循环

### 13.7 ~~quickfix 不动 modulespec 的 design rationale~~ → **正式作废**（2026-05-11 PM 拍板）

> **状态**：PM 在 2026-05-11 拍板 §13.10 quickfix 实际意图四点全对，本节正式作废，仅留作历史追溯。
> 真实意图见 §13.10；v3 设计按 §13.10 + C4.1-C4.5 重审 C1/C3/D13 边界。

~~PM 在 v3 阶段问了为什么 quickfix 改原型但不动 modulespec。归档原因，避免下次重新讨论：~~

~~1. modulespec 是 task-execute 的硬约束：task 执行中 agent 把 modulespec 当不可违反的合同读。如果 quickfix 能任性改 modulespec，正在跑的 task 会看到合同突变 → 实现漂移。~~
~~2. 小动作不应付重路径代价：quickfix 改的可能是文案 / 默认值 / 排序方向 / 按钮位置；让它每次走"读 modulespec → 推理改哪行 → 写回"= 把 settlement-mode 的浪费复制一遍。~~
~~3. task-execute 已经"知道"了 quickfix 改动：C1 设计下 task-execute 读 = `docs/modules` + 同 req 已 close task PM 视图 + quickfix log（needs-modulespec-update=true）。即使没 hard-write modulespec，task-execute 通过 quickfix log overlay 仍然看得到。modulespec 的"延迟更新"不等于"信息延迟"，信息已在 overlay 里。~~

### 13.8 续接说明（下次新对话从这里 boot）

**当前状态（2026-05-12 更新）**：D13 方向已定（rewrite-only），v2 写完跑过 round 3 autoplan，发现 4 critical + 6 high + 多 worktree 并行新维度（V16/V17）+ **quickfix 实际意图被 PM 在 2026-05-11 末尾澄清（§13.10），推翻 §13.7 假设**。PM 拍板进入 v3 设计回合；§14 已写入 v3 设计稿，下一步是 PM review + round 4 autoplan。

**v3 任务清单**：V1-V17 + C4 新设计（见 §13.4 + §13.10 + §14），按依赖关系排序，总工作量 18-29 小时。

**下次开新对话的 boot 顺序**：
1. 先读 `docs/design/prd-modulespec-重构.md` §十二 v2（D13 当前方案）+ §十三 v3 任务清单 + **§13.10 quickfix 实际意图 + §13.11 V16/V17 方向 (e)** + **§十四 v3 设计稿**（§13.10 / §13.11 是 D13 边界根基的重新校准，§14 是当前落稿）
2. 跟 PM 对齐：
   - **§14.6 quickfix 重定位落地是否符合 §13.10 四点真实意图**
   - **§14.7 方向 (e) 工作流是否对**（特别是 step 0.5 三分类 A/B/C 粒度 + close-task 也做）
   - §14 是否可以进入 round 4 autoplan，还是先局部重写某节
3. 若 PM 放行，跑 round 4 autoplan；若发现 critical，进入 v4 设计循环；若通过，再进 Phase C 实施

**起手点候选**：
- **§14 自检 + PM review**：推荐第一步，因为 v3 草稿已写完，先抓矛盾再 autoplan
- **round 4 autoplan**：覆盖 §14 全套，重点看 V3 merge 公式 / V6 temp worktree / §14.7 step 0.5 / C4.2 snapshot
- **Phase C 实施准备**：若 round 4 通过，再按 §14.8 v3-01 → v3-36 拆 PR

**关键事实备查**（避免下次重新摸现状）：
- rewrite mode 已存在于 `skills/doc-update/SKILL.md` §8，当前是 fallback（≥2 SKIP marker 才触发）；D13 = 升 default
- I-CT2 不含 doc-update prereq（v1 §12.5 描述错误已修正）
- task-execute 步骤 2.1（`skills/task-execute/SKILL.md:290`）已包含"同模块已完成 task 的 PM 视图"——C1 是在此基础上叠加 quickfix log + 修复 merge 语义
- 多 req / 多 task / task vs quickfix 并行都是 PM 实操常见场景（adminconsole4 + PM 2026-05-11 确认）
- 整个讨论的 plan files：`<LOCAL_CLAUDE_HOME>/plans/hashed-waddling-hummingbird.md`（round 1）+ `<LOCAL_CLAUDE_HOME>/plans/d13-rewrite-only-autoplan-review.md`（round 2）

### 13.9 V17 同 req 内 task 过程中的并行盲点（2026-05-11 新发现）

PM 提示后发现：多 req 并行（V16）只是同根问题的一种表现层，**同 req 内 task 过程中也有同样问题**。

**三类场景**：

| 场景 | 谁不知道谁 | 共享资源 |
|---|---|---|
| 多 task 同 req 并行 | task A2 起来时读了"当时已 close 的 task 列表"；之后 task A1 close → task A2 看不到新内容（worktree 隔离） | req 分支的 task PM 视图 |
| task vs quickfix 并行 | task A1 起来后 PM 做 quickfix（在 req 分支或主分支）→ task A1 worktree 没 pull，不知道改动 | req 分支 / 主分支的 modulespec / 原型 |
| task worktree 跟 req 分支漂移 | task A1 close 时 merge 回 req 分支 → 跟期间的 quickfix / 其他 task close 产生 git 冲突 | req 分支 modulespec |

**共同根因**：git worktree 隔离 + 共享资源事后变化。

**跟 V16 的关系**：
- V16 = 跨 req（共享 main）
- V17 = 同 req 跨 worktree（共享 req 分支）
- 解法可合并设计（V16/V17 共用 4 候选方向 a/b/c/d）

### 13.10 quickfix 实际意图重定位（2026-05-11 PM 澄清，推翻 §13.7；2026-05-11 PM 拍板）

> **状态**：PM 在 2026-05-11 拍板"四点都对" → §13.7 正式作废，C4.1-C4.5 进 v3 设计稿（§14.8）。

**AI 之前的（错误）理解**：quickfix = 原型层小修补（文案 / 默认值 / 按钮位置），不动 modulespec，留 close-req 同步。

**PM 在 2026-05-11 澄清的实际意图**：

> "我 quickfix 修改的时候，实际上就是想要修改原型，同时修改 modulespec，甚至我修改的还可能是之前某个 req 的产物，我需要你帮我同时在 req 中记录。"

理解为四点：

1. **quickfix 是产品决策**（轻量但有分量），不是原型层小修补
2. **同时改原型 + modulespec**（两个一起改，不是一个改一个等）
3. **修改目标可能是之前某个 req 的产物**（不限于当前 active req 新加的 feature；可能改的是历史 req 早已沉淀进 modulespec 的内容）
4. **必须在当前 active req 中记录**这次 quickfix（哪改了 / 为什么 / 关联到哪个 req / 影响范围）

**这是根本性设计变化，影响**：

| 维度 | §13.7 旧设计 | §13.10 重定位后 |
|---|---|---|
| quickfix 写 modulespec 吗 | 不写，等 close-req | **写**（PM 决策即时落地） |
| 改 modulespec 谁的 | 只能改本 req 加的 | **可改任何 req 的产物**（历史也行） |
| 跟 active req 关系 | 解耦（quickfix 是横切动作）| **必须挂载到当前 active req**（记录到 quickfix log + modulespec patch 归因） |
| 跟 task-execute 合同稳定 | 通过"不动 modulespec"保证 | 需要新机制（task worktree snapshot lock + quickfix 改 req 分支 → 已起 task 不受影响） |
| D13 rewrite-only 边界 | 唯一 modulespec 写入者 = close-req rewrite | **quickfix 也是 modulespec 写入者**；close-req rewrite 跟 quickfix 实时写要协调（rewrite 时怎么消费已经实时写过的 quickfix 改动？避免重复 / 冲突？） |

**v3 新增任务（C4 — quickfix 重定位设计）**：

| Task | 描述 | 依赖 |
|---|---|---|
| **C4.1** | C3 schema 扩展：加 `target_origin_req`（修改的目标产物属于哪个 req，可为本 req 也可为历史 req）/ `recorded_in_req`（本次 quickfix 在哪个 active req 中记录）/ `modulespec_patch`（结构化 patch instructions，不只是 free text） | C3 |
| **C4.2** | quickfix 写 modulespec 的协调机制：quickfix 直接 patch modulespec，但 task worktree 已起来的 task 读 snapshot（不受影响）；后起 task 看新 modulespec；机制需要 task-execute 起来时 freeze modulespec snapshot 到 worktree | V3 + C4.1 |
| **C4.3** | close-req rewrite 消费 quickfix 改动的逻辑：quickfix 已经把改动写进 modulespec，rewrite 时不能重复应用 → rewrite 输入要区分"待应用 patch（task PM 视图）"vs"已应用 patch（quickfix 实时写）"；可能 rewrite 改成"仅消费未 applied 的 patch + 验证已 applied 的 patch 跟当前 modulespec 一致" | C4.1 + V3 + V7 |
| **C4.4** | quickfix 改历史 req 产物的归因机制：modulespec 行级 / feature 级标注"来源 req"；quickfix 改时记录 `target_origin_req` 让审计可追溯 | C4.1 |
| **C4.5** | PM 在 active req 中"记录"quickfix 改动的 UX：quickfix log 是结构化记录，但 PM 在 active req PM 视图里看得到吗？还是只能去 quickfix-log.jsonl 里翻？设计入口 | C4.1 |

**v3 落点**：
- §13.10 4 点已作为 C4 进入 §14.6（特别是"产品决策 vs 小修补"+"改之前 req 产物"+"挂载到当前 active req"）
- §13.7 已正式作废，C1/C3/D13 都按本节重审
- 工作量增加 3-5 小时（已计入 §13.5 C4）

### 13.11 V16/V17 方向 (e) — Close-time detection + AI 助理合并（2026-05-11 PM 拍板）

> **状态**：PM 在 2026-05-11 拍板 (e)，且 close-task 也做 step 0.5（不只 close-req）。a/b/c/d 全部作废。
> v3 设计稿见 §14.7（V16/V17 合并设计）。

**PM 原话**：
> "其实是我默认允许的情况，比如我通过做两个 req，如果他们有关联关系，我自己就会判断出来，但是常规的情况会是两个 req 关系不大。但是如果出现了边界情况，我同时做了两个有关联关系的 req，他们互相不知道，那可能需要你再 close 之前，帮我检查并处理好，如果需要决策就和我确认，你的责任是帮我处理好合并。"

**核心哲学**：
- 默认接受冲突（不限并行度，不持续干扰 PM）
- PM 自己判断 req 关联性（不让 framework 替 PM 想）
- 但**边界情况 AI 必须主动兜底**：close 前 detection + AI-assisted merge
- AI 的责任是处理合并体力活；PM 的责任是做语义决策

**详细工作流**：

```
close-req 流程（rewrite mode 之前新增 step 0.5）：

step 0.5：跨 worktree 共享资源变化检测
  ├─ pull main，得到 main 当前 modulespec / 共享资源状态
  ├─ 对比本 req 起来时的 modulespec（base） vs main 当前（new base）
  ├─ AI 用 V1 task→module 映射 + V3 merge 函数尝试三方合并：
  │  ├─ base modulespec
  │  ├─ main 已有改动（其他 req close 后写入的 patch）
  │  └─ 本 req 累积改动（task PM 视图 + quickfix metadata）
  └─ 分类结果：
     ├─ A) 完全不重叠（不同 module / 同 module 不同 section）→ 默认继续 rewrite，PM 不打扰
     ├─ B) 表面重叠但无语义冲突（如格式差异 / 顺序差异）→ AI 自动合并，结果展示给 PM 简短 confirm
     └─ C) 真正语义冲突（同 anchor 不同结论）→ 进显式决策门：
        - AI 分析冲突类型（functional / cosmetic / 真正语义冲突）
        - AI 提议 2-3 个合并方案
        - PM 选 / 自定义
        - AI 拿决策应用，不让 PM 看 git marker

step 0.5 通过后 → 进入 rewrite mode（V3 merge 函数已经把 main 改动 + 本 req 改动统一合并）
```

**同 req 内 task 并行（V17）等价处理**：

```
close-task 流程新增 step 0.5：
  ├─ 检测 task A1 起来后 req 分支上其他 task close / PM 做的 quickfix
  ├─ 用 V1/V3 同样的方法分类 A/B/C
  └─ A 默认继续 / B AI 自动合并 + 简短 confirm / C 显式决策门
```

**AI 责任范围**（PM 给的）：
- 主动检测（不是 PM 自己想起来 + PM 主动 pull）
- 分析冲突类型（功能性 vs 表象 vs 真冲突）
- 提议 2-3 个合并方案（不是把 raw diff 甩给 PM）
- 处理合并细节（应用 patch / 解 git marker / 验证 modulespec 完整性）
- 边界情况让 PM 决策（不是 AI 自作主张）

**PM 责任范围**：
- 判断 req 起来时是否有关联（常规决策）
- 处理 step 0.5 上报的真冲突（语义决策）
- 不做：pull / merge / 解 git marker / 验证 modulespec / 写合并 patch

**跟 a/b/c/d 的区别**：
| 维度 | (a) | (b) | (c) | (d) | **(e)** |
|---|---|---|---|---|---|
| 限制并行度 | 否 | **是** | 否 | 否 | 否 |
| 持续干扰 PM | 否 | 否 | **是** | 否 | 否 |
| 强制 rebase | 否 | 否 | 否 | **是** | 否 |
| PM 解 git marker | **是** | 否 | 否 | 否 | 否 |
| AI 主动检测兜底 | 否 | 否 | 否 | 否 | **是** |
| 默认场景 PM 体验 | 同 (a) | 受限制 | 频繁打扰 | 强制操作 | **零打扰** |
| 边界场景 PM 体验 | 解 git 体力活 | 不发生 | 提前发现 | 提前发现 | **AI 助理 + PM 决策** |

**实施依赖**：
- V1（task→module 映射脚本）— 检测共享资源用
- V3（merge 函数公式）— AI 三方合并基础
- 新增能力：AI 冲突分类器（functional / cosmetic / 语义冲突）+ AI 合并方案生成器

**工作量增量**：估 4-6 小时（在原 V16+V17 4-6 小时基础上**替换**而非追加；(e) 实现重于 (a) 但合并设计后总量可控）

**v3 落点**：
- §14.7 已采用 (e) 工作流，step 0.5 三分类 A/B/C 作为 V16/V17 共用检测模型
- close-task 也做 step 0.5（见 §14.7.3），不只 close-req 做
- quickfix 实时写 modulespec 的协调写入 §14.7.4（step 0.5 是 patch 域合并，step 2 rewrite 是应用域合并）

---

## 十四、D13 v3 设计稿（2026-05-11/12）

> **版本**：v3（基于 §十二 v2 + round 3 autoplan 4 critical/6 high + §13.10 quickfix 重定位 + §13.11 多 worktree 方向 (e)）。
> **关系**：v3 不重写 §十二 v2，而是叠加补丁——v2 已答 C1/C2/C3 的核心方向，v3 补齐"merge 函数公式 / 隔离边界 / schema 完整 / 多 worktree 并行 / quickfix 实时写"五条主线。
> **状态**：待 PM 逐节确认。通过后跑 round 4 autoplan 验，再进 Phase C 实施。
> **总工作量**：18-29 小时。

### 14.0 v3 总图

**五条主线**：

| 主线 | 任务 | 解决的根问题 |
|---|---|---|
| Foundation | V1（task→module 脚本）+ V2（全局时间序） | 其他主线依赖；当前 v2 假设"AI 知道 task 改了哪些 module"和"AI 知道叠加顺序"，未明确定义机制 |
| C1 v3 — merge 函数 | V3-V5 | v2 §12.4.1 写"后写覆盖前写"但没定义"什么算冲突"、"feature 怎么识别"、"module 重命名后怎么对齐" |
| C2 v3 — 隔离 worktree + 边界锁死 | V6-V9 | v2 §12.4.2 只盖 rewrite 内部 atomic，没盖外部残留（`.runs/` / temp branch / event log）+ close-req 入口 dirty + cancel-req 误判 |
| C3 v3 — schema 完整化 | V10-V13 | v2 §12.4.3 schema 缺 stable id / version / affected_paths / 二次验证 / 老条目降级保护 |
| 横切 + 新维度 | V14-V15（横切）+ V16-V17（多 worktree）+ C4.1-C4.5（quickfix 重定位） | v2 没答 break-even / 测试 fixture / 多 req 并行 / quickfix 写 modulespec |

**主线依赖图**：

```
V1 ─┬─→ V3 ─┬─→ V4 ─→ V10, V11
    │       │
    │       └─→ V5
    │
    ├─→ V14
    │
    └─→ V16/V17 (方向 e step 0.5)
            ↑
V3 ──────────┘
            ↑
V7 ──────────┘

V6 ─→ V7 ─→ V8, V9, V15
V11 ─→ V12, V13, C4.1
V3 + C4.1 ─→ C4.2 ─→ C4.3
C4.1 ─→ C4.4, C4.5
```

**写作密度策略**：每节 = 问题陈述 + 设计方案 + 关键决策 + 实施清单 + （必要时）worked example。不重复 v2 已写清楚的内容（如 close-req 整体流程、settlement 砍的细节）。

---

### 14.1 Foundation

#### 14.1.1 V1 — task→module 映射脚本

**问题**：v2 §12.4.1 / §12.4.3 / §13.11 step 0.5 都假设"AI 知道某个 task 或 quickfix 改了哪些 module"，但 v2 没给可执行机制。手动猜测 module 影响范围在 round 3 autoplan 被标为 critical（C1 共识）。

**设计**：

```bash
scripts/req-module-impact.py <req-id> [--include-quickfix] [--since <commit>] [--format json|md]
```

**输入**：
- `<req-id>`：active 或 closed 的 req
- `--since`：可选，从某 commit 开始统计（默认从 req 起点）
- `--include-quickfix`：把 quickfix metadata 也算进来

**输出**（JSON 模式）：

```json
{
  "req": "R-2026-001",
  "base": "<git sha>",
  "head": "<git sha>",
  "tasks": [
    {
      "task": "T1",
      "modules": ["module-log", "module-filter"],
      "source": "task-spec module_impact field"
    }
  ],
  "quickfixes": [
    {
      "commit": "<sha>",
      "modules": ["module-log"],
      "target_origin_req": "R-2025-098",
      "source": "quickfix-log.jsonl"
    }
  ],
  "modules_touched": {
    "module-log": {
      "tasks": ["T1"],
      "quickfixes": ["<sha1>", "<sha2>"]
    },
    "module-filter": {
      "tasks": ["T1"],
      "quickfixes": []
    }
  }
}
```

**数据源优先级**（顺序明确，不交叉验证）：
1. task：从 `requirements/.../tasks/T*.md` 的 `module_impact:` frontmatter 字段（V5 强 lint 保证存在）
2. quickfix：从 `requirements/active/<req>/quickfix-log.jsonl` 的 `module` 字段（C3 schema 保证存在）
3. **不退到**"grep diff 反推"，因为信号噪声大；如 frontmatter / log 缺字段 → 脚本退出非零 + 报告缺哪个 task/quickfix

**关键决策**：
- **不引入"自动推断 module"**：所有 module 标注都是 task-spec 时 PM 拍 / quickfix 时 PM 拍。脚本只汇总，不推断。
- **不交叉验证 diff**：不在脚本里跑"task 标了 module-A 但 diff 显示动了 module-B 文件 → 警告"。理由：diff vs module 映射本身也是估算（哪些文件属于 module 没有硬规则），加这层只会引入噪声。诚信靠 V5 lint + V12 quickfix 二次验证 + close-req rewrite 时 PM 审 diff 三层保障。

**实施清单**：
1. `scripts/req-module-impact.py` 新建
2. `tests/scripts/test-req-module-impact.py` 新建，覆盖：task frontmatter 正常 / 缺字段 / 多 module / quickfix 合并 / `--since` 切片
3. C1/C2/V16/V17/C4 任何用到 module 映射的地方都调此脚本，不重复实现

---

#### 14.1.2 V2 — 全局时间序定义

**问题**：v2 §12.4.1 写"按时间顺序叠加，后写覆盖前写"。但"时间"指什么？close 时间戳？文件 mtime？commit 时间？wall clock 在多 worktree 并行时不可靠（各 worktree 时钟可能漂移；merge 进 req 分支后 commit 时间是原始 author time 还是 commit time？）。

**设计**：**git topo order on req branch**——以 req 分支上 commit 的拓扑顺序为权威时间序。

**定义**：

```
对 req 分支 R 上的任意两个改动事件 e1 (在 commit c1)、e2 (在 commit c2)：
  e1 < e2 (in time)  ⟺  c1 是 c2 的祖先（git merge-base --is-ancestor c1 c2 == 0）
  否则 e1 和 e2 不可比（并行分支，需进 V16/V17 step 0.5 处理）
```

**实操含义**：
- task A close 在 commit cA、task B close 在 commit cB、quickfix Q 在 commit cQ
- merge 合并到 req 分支后：read `git log --topo-order req-branch -- requirements/active/<req>/`，按从老到新顺序就是叠加顺序
- 同一个 commit 内多次写（同一 task PM 视图修改 + quickfix log）：按文件出现顺序（实际不会发生，task 和 quickfix 是分别 commit）

**为什么不用 wall clock**：
1. 多 worktree 时钟漂移
2. cherry-pick / rebase 会改 author time 但不改拓扑顺序
3. 老旧仓库 / migration 时 commit 时间不可靠

**为什么不用 commit time（committer time）**：
- commit time 在 merge / rebase 时会更新，导致同一逻辑事件的 "时间" 在历史上跳变；topo order 是不可变事实

**实操：取叠加顺序的脚本**：

```bash
scripts/req-event-order.py <req-id> [--filter task|quickfix|all]
```

输出：按 topo order 的事件列表 (commit sha + 类型 + module + feature 摘要)。

**关键决策**：
- 并行 commit（拓扑顺序不可比，如多 worktree 各自前进未 merge）→ **不在 V1/V2 解**，进 V16/V17 step 0.5 检测并提交 PM 决策。V2 只定义"已 merge 进 req 分支后顺序怎么算"。
- merge commit 怎么算？→ merge commit 自身有时间序意义（标识两条分支合点）；其父链按 topo 自然展开。

**实施清单**：
1. `scripts/req-event-order.py` 新建（V1 的姊妹脚本）
2. 把"按 topo order 叠加"写进：
   - `skills/doc-update/SKILL.md` §8 rewrite mode 输入构造
   - `skills/task-execute/SKILL.md` 步骤 2.1 D13 模式说明
   - `INVARIANTS.md` 新增 I-CR13：rewrite mode 输入合并必须按 git topo order，不允许 wall clock
3. `tests/scripts/test-req-event-order.py`：覆盖正常 / merge commit / 并行未合（应报错让 V16 处理）

---

### 14.2 C1 v3 — merge 函数

#### 14.2.1 V3 — merge 函数公式

**问题**：v2 §12.4.1 写"modulespec 是基线，task PM 视图按顺序叠加，quickfix 按顺序叠加；冲突时后写覆盖前写"。这只是口号，没有公式 → AI rewrite 时无法可重复执行，每次结果可能不同。

**核心定义**：

> **merge 函数** `M(base, [patch_1, patch_2, ...]) → new_modulespec`，输入：基线 modulespec（按 module 拆分）+ 时间序排好的 patch 列表（每个 patch 来自一个 task PM 视图或一个 quickfix），输出：新 modulespec。

**步骤**：

```
M(base, patches):
  1. 把 base 拆成 feature 集合：FB = { f | f ∈ base.features_by_module }
     每个 feature 有：feature_id（V10 stable hash）+ anchor（module + 章节）+ payload（描述 + 行为 + 关联）

  2. 把每个 patch 也拆成 feature 集合 + change-type 标注：
     patch_i = { (op_j, feature_j) | op_j ∈ {add, modify, remove, behavior-only} }

  3. 按 topo order 应用每个 patch：
     state = FB
     for patch in patches (topo order):
       for (op, f) in patch:
         apply(state, op, f)

  4. 输出 state 重新组装回 modulespec 文本
```

**`apply(state, op, f)` 单步语义**：

```
apply(state, op, f):
  match op:
    case add:
      if feature_id(f) ∈ state:  → CONFLICT_ADD_EXISTING（feature 已存在还想新加）
      else:                       state[feature_id(f)] = f  （新增）

    case modify:
      if feature_id(f) ∉ state:  → CONFLICT_MODIFY_MISSING（要改的 feature 不在）
      else:                       state[feature_id(f)] = merge_payload(state[feature_id(f)], f)

    case remove:
      if feature_id(f) ∉ state:  → CONFLICT_REMOVE_MISSING（要删的 feature 不在）
      else:                       del state[feature_id(f)]

    case behavior-only:
      if feature_id(f) ∉ state:  → CONFLICT_BEHAVIOR_MISSING
      else:                       state[feature_id(f)].behavior = f.behavior  （文字不变，只刷行为说明）
```

**`merge_payload(old, new)` 单 feature 内部字段合并**：

```
merge_payload(old, new):
  result = {}
  for field in {description, behavior, related_features, acceptance, ...}:
    if new[field] != null and new[field] != old[field]:
      if old[field] != null:
        → CONFLICT_FIELD_CHANGE（同字段 same anchor 不同新值，进显式冲突门）
      else:
        result[field] = new[field]  （old null → new 覆盖）
    else:
      result[field] = old[field]
  return result
```

**冲突进什么门**：

| 冲突类型 | 处理 |
|---|---|
| CONFLICT_ADD_EXISTING | rewrite mode 暂停，列出冲突 → PM 选 (a) 把 add 改成 modify 走 merge_payload (b) 改名（V4 rename）(c) 取消本 patch |
| CONFLICT_MODIFY_MISSING | 暂停 → PM 选 (a) 改成 add (b) skip 本 patch (c) 检查 V4 rename 是否漏 |
| CONFLICT_REMOVE_MISSING | 暂停 → 同上 |
| CONFLICT_BEHAVIOR_MISSING | 同 CONFLICT_MODIFY_MISSING |
| CONFLICT_FIELD_CHANGE | 暂停 → PM 选 (a) 用新值 (b) 用旧值 (c) 写第三个值 (d) 二选一二选拆分（拆 feature） |

**关键决策**：
- **冲突不静默 last-writer-wins**：v2 §12.4.1 写"后写覆盖前写"被 round 3 autoplan 标为根因（feature-key 不稳定 + 冲突静默压扁）。v3 改：last-writer-wins 仅适用 `null→非null` 升级（属于互补，非冲突）；两个非 null 值发生变化必入显式冲突门。
- **顺序仍按 topo order 应用**：保证可重放（同样的 base + 同样的 patches 顺序 → 同样的中间状态 + 同样的冲突点）。
- **feature 不存在的 modify 不静默升级成 add**：v2 行为是"补上就完了"，但这掩盖了"task-spec 标错 module / V4 rename 漏对齐 / feature_id 不稳"三种 bug。v3 强制让 PM 看到。

#### 14.2.2 V3 worked examples（5 个 change-type 各一）

**Example A — add**：

```
Base (module-log)：
  feature_id=L-001 "列表筛选" { sort_default: 时间倒序 }

Patch 1（task T1 PM 视图）：
  add: feature_id=L-002 "导出 CSV" { description: "..." }

Patch 2（quickfix）：
  add: feature_id=L-002 "导出 CSV" { description: "新版" }  ← 跟 Patch 1 同 feature_id

apply(state, add, L-002 from P1)：state[L-002] = P1.L-002
apply(state, add, L-002 from P2)：L-002 已在 → CONFLICT_ADD_EXISTING
  → 暂停，PM 选 (a) 改成 modify 合并：state[L-002] = merge_payload(P1.L-002, P2.L-002)

最终 state：L-001 (原), L-002 (合)
```

**Example B — modify**：

```
Base：
  L-001 "列表筛选" { sort_default: 时间倒序, related: [L-003] }

Patch 1（task T1）：
  modify: L-001 { sort_default: 时间正序 }  （只改 sort_default 字段）

Patch 2（task T2，晚于 T1 close）：
  modify: L-001 { related: [L-003, L-007] }  （只改 related 字段）

apply(state, modify, L-001 from P1)：
  merge_payload({sort_default:倒序, related:[L-003]}, {sort_default:正序})
    sort_default: 倒序 vs 正序，都非 null → CONFLICT_FIELD_CHANGE
    → 暂停，PM 选"用新值 (正序)"
    related: P1 没填 → 保留 [L-003]
  → state[L-001] = {sort_default: 正序, related: [L-003]}

apply(state, modify, L-001 from P2)：
  merge_payload({sort_default:正序, related:[L-003]}, {related:[L-003, L-007]})
    sort_default: P2 没填 → 保留正序
    related: [L-003] vs [L-003, L-007]，都非 null → CONFLICT_FIELD_CHANGE
    → 暂停，PM 选"用新值 [L-003, L-007]"（PM 也可看到这只是扩集合 → 自定义"合并集合"语义留 v4）
  → state[L-001] = {sort_default: 正序, related: [L-003, L-007]}
```

**Example C — remove**：

```
Base：
  L-005 "PDF 导出" { description: "..." }

Patch 1（task T1）：
  remove: L-005

apply(state, remove, L-005)：state[L-005] 存在 → del state[L-005]

Patch 2（task T2，T1 后 close）：
  modify: L-005 { description: "..." }

apply(state, modify, L-005)：L-005 不在 → CONFLICT_MODIFY_MISSING
  → 暂停，PM 看到 T1 已 remove L-005，T2 又想改 → 选 (a) 取消 T2 的 modify (b) 把 T2 的 modify 改成 add（feature 复活）(c) PM 调度：让 T1 的 remove 改成 modify

注意：rewrite 时 PM 已看到所有 patch，不是 task close 时孤立处理；这种顺序矛盾在 rewrite 是 surface 出来供 PM 决策的契机。
```

**Example D — behavior-only**：

```
Base：
  L-001 "列表筛选" { sort_default: 时间倒序（文字描述）, behavior: "首次进入按时间倒序排" }

Patch 1（quickfix）：
  behavior-only: L-001 { behavior: "首次进入按时间倒序排，PM 可点击表头切换" }
  （没改 sort_default 文字字段，仅澄清行为）

apply(state, behavior-only, L-001)：L-001 存在 → state[L-001].behavior = P1.behavior

state[L-001] = {sort_default: 时间倒序, behavior: "...切换"}

后续 rewrite 输出时，behavior 段更新；sort_default 字段不变。
```

**Example E — null**（quickfix 标 module=null，不参与 merge）：

```
Patch 1（quickfix metadata：module=null）：
  纯文案改 / DESIGN.md 微调 / 按钮位置

rewrite mode 完全跳过这条（前置过滤）：
  filter patches where module != null and needs-modulespec-update = true

state 不变；quickfix log 仍保留作 audit trail。
```

#### 14.2.3 V4 — 模块身份模型 + rename 检测

**问题**：module 改名后 base 里叫 `module-log`、patch 里叫 `module-event-log`——merge 函数会当成"两个不同 module"，base 整段当成"消失"+ patch 整段当成"新增"，rewrite 一夜回到解放前。

**设计**：

`.req-meta.json` 加 `module_aliases` 表，记录本 req 内的 rename / alias 链：

```json
{
  "module_aliases": [
    {
      "canonical": "module-event-log",
      "aliases": ["module-log"],
      "renamed_in_commit": "<sha>",
      "renamed_by_task": "T3",
      "reason": "扩大职责包含审计事件"
    }
  ]
}
```

**rewrite mode 消费**：merge 函数读 `module_aliases`，把所有 alias 统一映射到 canonical 名称，再做 merge。

**rename 检测时机**：

| 时机 | 检测方式 | 触发动作 |
|---|---|---|
| task-spec 拆 task 时 | task-spec 的 `module_impact` 包含 base 不存在的 module 名 | 问 PM："module-event-log 是新建吗，还是 module-log 改名？" → 写 module_aliases |
| quickfix 时 | quickfix metadata 填写时 PM 选了 base 不存在的 module | 同上 |
| close-req rewrite 入口 | 自动扫 base modules vs patches modules 差集 | 报告 → PM 确认每条差集是 (a) rename (b) 真的 new module (c) 真的 remove |

**module_id**（潜在升级，v4 候选）：本 v3 保留 module 用文件夹名作 id（`docs/modules/<name>.md`）；如果 rename 频繁发生 → v4 引入 stable module_id (UUID/hash) + 文件名只是 alias。

**关键决策**：
- 不引入 stable `module_id` 字段（暂缓）：理由是 module rename 在 adminconsole4 实际频率很低（PM 凭印象），引入 UUID 让 modulespec 文件读起来更难。如果 round 4 autoplan 发现真高频，v4 加。
- 多个 module 合并成一个（merge），或一个拆成两个（split）——v3 范围外：用 `module_aliases` 只解 1-to-1 rename。merge/split 走 PM 显式 close-req 前重写（手动），不在 merge 函数里自动处理。

**实施清单**：
1. `templates/.req-meta.schema.json` 加 `module_aliases` 字段
2. `skills/task-spec/SKILL.md` 加"识别 module rename / new"问 PM 的 step
3. `skills/quick-fix/SKILL.md` metadata 填 module 时若不在 base → 触发同样问询
4. `skills/close-req/SKILL.md` rewrite 入口加 module diff 报告
5. `scripts/req-module-impact.py`（V1）输出时把 alias 解到 canonical

#### 14.2.4 V5 — task-spec module_impact 强 lint

**问题**：v2 §12.4.1 末尾"如果 task-spec 漏标 module → 警告 PM"——只 warn 不阻断。round 3 autoplan 指出：warn 在 PM 一忙就被滚屏走，等 close-req rewrite 发现 module_impact 缺字段时已无法定位"这个 patch 来自哪个 task"。

**设计**：把 `module_impact` 字段从 task-spec 软建议升级成 task md frontmatter 必填 + dispatch gate 硬阻断。

**字段定义**（task md frontmatter）：

```yaml
---
task_id: T3
module_impact:
  - module: module-log
    change_kind: [feature_add, feature_modify]
    confidence: high
  - module: module-filter
    change_kind: [feature_modify]
    confidence: medium
---
```

- `change_kind` 枚举：`feature_add` / `feature_modify` / `feature_remove` / `behavior_only` / `unknown`
- `confidence`：`high`（PM 已确认）/ `medium`（AI 推断 PM 同意）/ `unknown`（task-spec 拆时还没看仔细——dispatch gate 阻断）
- `module_impact: []` 显式空数组 = 表示本 task 不影响任何 modulespec（PM 主动声明，gate 允许）

**lint 触发点**：

| 触发点 | check | 失败动作 |
|---|---|---|
| task-spec 写 task md 时 | `module_impact` 字段是否存在 | 拒绝写出 task md，回 PM 补 |
| task dispatch gate (`task-confirm` 前) | `module_impact` 中无 `unknown` confidence | 阻断 dispatch，回 task-spec 重审 |
| close-task gate | `module_impact` 一致性：实际改动 vs 声明范围（diff vs module_impact）| warn（不阻断；diff 推断信号噪声大，进 audit log） |
| close-req rewrite 入口 | 所有 task 的 `module_impact` 都 fully resolved | 阻断 rewrite，回 task-spec |

**关键决策**：
- **dispatch gate 阻断**：在 task 起来之前卡死，是最便宜的纠错点。task 已 dispatch 后再发现漏标 → 要么硬中断（影响 task-execute 状态），要么放过 → close-req 暴雷。
- **close-task gate 只 warn 不阻断**：理由是 diff vs module_impact 一致性本身有噪声（哪些文件属于哪个 module 没硬规则）；硬 fail 会误伤。设计意图是给 PM/AI 一个"实际跟声明对不上"的 audit signal，让 PM 在 close-req rewrite 前能补一刀。

**实施清单**：
1. `templates/task.template.md` 加 `module_impact` frontmatter
2. `scripts/check-task-meta.py` 新建：lint module_impact + 在以下 hook 调用：
   - task-spec 写出 task md 后
   - task dispatch（`task-confirm` 前）
   - close-task（warn）
   - close-req rewrite 入口
3. `skills/task-spec/SKILL.md` 加 module_impact 填写 step（输入 PM 视图 + base modules → 推荐 module 列表 + change_kind + confidence）
4. `INVARIANTS.md` 新增 I-TS1：所有 dispatch 的 task 必须 `module_impact` 字段存在且无 `unknown` confidence
5. `tests/` 覆盖：缺字段 / unknown confidence / 空数组合法 / dispatch gate 阻断行为

---

### 14.3 C2 v3 — 隔离 worktree + 边界锁死

#### 14.3.1 V6 — 隔离 temp worktree/branch 内 rewrite

**问题**：v2 §12.4.2 只 atomic rewrite 内部（要么所有章节通过，要么退回），但残留可能在外部：
- `.runs/close-req-rewrite-*` 工作文件
- 中途生成的 untracked diff
- event log `events/close-req.jsonl` 半写条目
- 如 rewrite 写 modulespec 文件后中断 → modulespec 文件已落盘但未 commit，working tree 留 dirty

`git reset --hard` 能把已 tracked 文件回滚，但 untracked / event log 不动。

**设计**：rewrite 全程在隔离 temp worktree + temp branch 内做，成功 → fast-forward 回 req worktree；失败 → rm -rf temp worktree（一刀切），原 req worktree 完全不动。

**流程**：

```
close-req 步骤 2（rewrite 隔离版）：

1. 创建 temp worktree：
   $ git worktree add -b close-req-rewrite/<req>-<ts> <tmp-path> <req-branch HEAD>
   $ cd <tmp-path>

2. 在 temp worktree 内跑 doc-update rewrite mode：
   - 读 base modulespec (HEAD)
   - 读 task PM 视图 + quickfix log（从 req 分支历史 topo order，V2）
   - 跑 V3 merge 函数
   - 写新 modulespec 文件到 temp worktree
   - PM 审 diff（逐章节，V8 决定 atomic 粒度）

3. 成功路径：
   $ cd <tmp-path> && git add docs/modules/ && git commit -m "doc-update rewrite for <req>"
   $ cd <req-worktree>
   $ git merge --ff-only close-req-rewrite/<req>-<ts>
   $ git worktree remove <tmp-path> --force
   $ git branch -D close-req-rewrite/<req>-<ts>
   继续 close-req 步骤 3+

4. 失败 / 取消路径：
   $ cd <req-worktree>
   $ git worktree remove <tmp-path> --force
   $ git branch -D close-req-rewrite/<req>-<ts>
   close-req exit 1，req 保留 active/、stage=7、worktree 干净
```

**关键决策**：
- **temp branch 命名约定**：`close-req-rewrite/<req-id>-<unix-ts>`，前缀固定 → 残留扫描可枚举（V9）
- **fast-forward 而不 merge**：保证 req worktree HEAD 只前进一个 commit（rewrite commit）。如果 merge 需要解冲突 → 说明 req worktree 期间发生过其他写（不应该），让 V16/V17 step 0.5 处理。
- **失败时 `--force` 清理**：因为 temp worktree 必然 dirty（rewrite 中断），不 force 删不了
- **event log 怎么处理**：temp worktree 独立写 `events/close-req.jsonl`，失败 `--force` 一起删；成功路径 ff merge 时 event log 也会带过来。设计上 event log 写在 req worktree 而不是 temp worktree——但 close-req 步骤 1（checkpoint 记录）在 req worktree 已写一条"开始 rewrite"，步骤 2 全在 temp worktree（不再追加），步骤 3+ 回到 req worktree 追加"成功"或"失败"条目。

**实施清单**：
1. `scripts/close-req.sh` 加 worktree 创建/销毁逻辑（覆盖当前 line ~54-88）
2. `skills/doc-update/SKILL.md` §8 加"必须在 temp worktree 内运行"约束
3. `INVARIANTS.md` 新 I-CR14：rewrite mode 必须在 temp worktree 内进行；req 主 worktree 不允许直接被 rewrite mode 写入
4. `tests/close-req/test-rewrite-isolation.sh`：rewrite 中断 → temp worktree 删干净 + req worktree 不动

#### 14.3.2 V7 — close-req mutation 边界锁死

**问题**：v2 §12.4.2 提到"pre-rewrite checkpoint"但位置含糊——checkpoint 在 close-req 哪一步？checkpoint 之前已经做了什么 mutation？close-req.sh 当前已有 active→closed/ 移动 + commit 等动作，这些在 rewrite 之前还是之后？

**设计**：

```
close-req 流程边界（v3 精确化）：

[阶段 P — pre-mutation read-only]
  step 0    入口 dirty gate：req worktree 必须 clean（git status --porcelain 空）
            否则中止：列出 dirty 文件 + 提示 PM commit/stash/clean
  step 0.5  V16/V17 step 0.5（跨 worktree 检测；§14.7）
  step 1    写 close-report.md（commit 到 req 分支）— **第一处持久 mutation**

[阶段 Q — mutation: 进入 commit 前 checkpoint]
  step 1.5  CHECKPOINT 记录：
            $ git rev-parse req-branch > .runs/close-req-checkpoint
            $ echo "{ts, head, req, phase: pre-rewrite}" >> events/close-req.jsonl

  step 2    rewrite mode (V6 隔离 temp worktree)
            成功 → checkpoint phase: post-rewrite
            失败 → reset req-branch HEAD 回 step 1 之前？不行，step 1 已经 commit。
            修订：rewrite 失败 → req 留在 stage=7、close-report 留下、不进 step 3

  step 3    实现深度变更检查（可能产生 commit）
  step 4    active → closed/ 移动 + commit
  step 5    merge req → main + push
  step 6    清理 checkpoint：rm .runs/close-req-checkpoint
```

**修订后的 atomic 边界**：

| 边界 | 保证 |
|---|---|
| step 0 (dirty gate) | req worktree 干净，不会跟期间动作混 |
| step 1 commit close-report | 这是第一处 mutation，但只是元数据，无破坏性 |
| step 1.5 → step 2 | rewrite 失败时，状态在"close-report 已提交 / modulespec 未变"——可恢复（PM 修后 retry，rewrite 会重读 head 不会重复 close-report） |
| step 3-5 | 必须 rewrite 成功才能跑；rewrite 后这三步任一失败 → 见 V9 stale checkpoint |
| step 6 清理 | 标志 close-req 流程完结 |

**新 INVARIANTS（v3 修订 v2 的 I-CR10/11/12）**：

| INVARIANT | 内容 |
|---|---|
| **I-CR10**（v3 修订）| close-req step 0 入口 dirty gate：req worktree `git status --porcelain` 必须空，否则中止 |
| **I-CR11**（v3 修订）| close-req step 2 rewrite 必须在 temp worktree（V6），失败 `--force` 清理，req 保留 stage=7、close-report 已 commit |
| **I-CR12**（v3 修订）| `.runs/close-req-checkpoint` 存在 + phase=pre-rewrite → close-req 入口提示"上次 rewrite 未完成，retry 还是 abort"；phase=post-rewrite → "上次 step 3+ 未完成，retry 还是 abort" |
| **I-CR13** | rewrite mode 输入合并按 V2 git topo order，不允许 wall clock |
| **I-CR14** | rewrite 必须在 temp worktree（V6） |
| **I-CR15** | close-req step 1 之后任何步骤失败，req 保留 active/、stage 不进 closed/，PM 可 retry |

**关键决策**：
- **不把 close-report 推到 step 2 之后**：close-report 是 PM 看到 rewrite 之前的素材（写出来 → PM 知道这次要 rewrite 什么）；放 rewrite 之后顺序倒置。
- **dirty gate 不省略**：哪怕 close-req 是 PM 显式触发，PM 也可能忘记 stash。dirty gate 比 PM 记忆便宜。
- **rewrite 失败后允许 retry**：retry 时 close-report 已存在（skip step 1），直接进 step 1.5 重新 checkpoint + step 2。这要求 step 2 rewrite mode 是幂等的（V6 隔离 + 重读 base 保证）。

**实施清单**：
1. `scripts/close-req.sh` 重排步骤：加 dirty gate + checkpoint 时机精确化 + retry 入口逻辑
2. `skills/close-req/SKILL.md` 步骤改写
3. `INVARIANTS.md` 替换 v2 §12.5 的 I-CR10/11/12 描述
4. `tests/close-req/test-mutation-boundary.sh`：覆盖每个失败时机的状态保证

#### 14.3.3 V8 — PM 部分接受语义

**问题**：v2 §12.4.2 写"PM 拒绝某章节 → 退回"——但如果有 3 个 module 各自 rewrite，PM 通过 module-A 拒绝 module-B 还在审 module-C，怎么处理？整体 atomic 让通过的 A 也回滚？per-module atomic 让 B 失败时 A 已落盘？

**设计**：**显式 per-module transaction，整体半接受语义 = "PM 一次审完全部 module 后统一 commit"**。

**流程**：

```
rewrite mode 内（temp worktree）：

1. 按 module 分批 rewrite：
   for module in affected_modules:
     生成 new modulespec(module) 草稿（写到 temp worktree 的 docs/modules/<module>.md）
     PM 审 diff（per-module）
     PM 选：accept / reject / edit / defer

2. 全部 module 审完后汇总：
   accepted = [module for module if status == accept or edit]
   rejected = [module for module if status == reject]
   deferred = [module for module if status == defer]

3. 决策门：
   if rejected or deferred:
     PM 选：
       (a) 整体 abort：rewrite 失败 → V6 失败路径 → req 保留 stage=7，下次 retry
       (b) 部分 commit：只写 accepted modules，rejected/deferred 留待下次 close-req（reject 理由 + defer reason 记 audit）
       (c) 回去重审：PM 重新看 rejected/deferred，给出 edit 直到全部 accept

4. 选 (b) 时：
   - temp worktree 内 git add 只 accepted modules 的文件
   - 写 audit：`requirements/.../close-req-rewrite-partial.md`（哪些 accept/reject/defer，原因）
   - rewrite commit
   - req 仍可进入 closed/，但 close-req 注脚提示"部分 rewrite，缺 modules: ..."
   - 下次 close-req 或新 req 内 task 涉及缺失 module → V12 二次验证会触发

5. 选 (a)：req 留 active/，下次进 retry 入口
6. 选 (c)：回到步骤 1 重审 rejected/deferred
```

**关键决策**：
- **per-module rewrite 草稿在 temp worktree 内分别写**：让 PM 看 git diff 是清晰的"这个 module 改了什么"
- **part-commit 不算半状态**：选 (b) 的 audit + close-req 注脚让"未完成 module" 在下次 close-req 自动 surface（V12 反查 + close-req 入口 grep "rewrite-partial.md" 提示 PM 继续）
- **不强制 all-or-nothing**：v2 隐含 all-or-nothing 让 PM 一次大 reject 整批工作浪费

**实施清单**：
1. `skills/doc-update/SKILL.md` §8 加 per-module audit + 三选门
2. `templates/close-req-rewrite-partial.template.md` 新建
3. `INVARIANTS.md` 新 I-CR16：part-commit 必须配套 audit 文件
4. `tests/close-req/test-part-commit.sh`：覆盖三选 + audit 写入 + 下次 close-req surface

#### 14.3.4 V9 — I-CR12 stale checkpoint 检测

**问题**：v2 §12.4.2 写"checkpoint 文件存在 → 提示 retry/abort"，但没区分场景：cancel-req（PM 主动放弃）之后 checkpoint 还在 → 下次 close-req 入口误判 → 提示 retry 一个已经被 cancel 的 req。

**设计**：checkpoint 文件检测时**双重验证**：

```python
def detect_stale_checkpoint():
    cp = read('.runs/close-req-checkpoint')
    if not cp:
        return None

    # 验证 1：checkpoint.req 跟当前 req 一致
    if cp.req != current_req_id():
        # 残留来自别的 req（不应该发生，但保护）
        return ('cross-req-stale', cp)

    # 验证 2：checkpoint.head 是当前 req 分支的祖先（HEAD 可达性）
    if not git_is_ancestor(cp.head, current_branch_head()):
        # checkpoint 指向的 commit 已不在 HEAD 链路（cancel-req 时 reset 过 / rebase 过）
        return ('orphaned', cp)

    # 验证 3：req 状态机一致
    if req_stage() != 7:
        # checkpoint 留下了，但 req 已经被推进或后退到非 close-req 阶段
        return ('mismatched-stage', cp)

    # 全部对得上：真正 stale，提示 PM
    return ('valid-retry', cp)
```

**处理映射**：

| 检测结果 | 入口动作 |
|---|---|
| None | 正常 close-req |
| valid-retry | "上次 close-req 在 phase=<X> 中断，retry / abort（清理 checkpoint）" |
| cross-req-stale | "checkpoint 属于 req=<X>，当前是 req=<Y>，自动清理 + 继续" |
| orphaned | "checkpoint 指向的 commit 已不在 HEAD（可能 cancel-req 后），自动清理 + 继续 + 写 audit" |
| mismatched-stage | "checkpoint 留下了但 req 不在 stage=7，提示 PM 调查（可能有别的脚本错误）" |

**关键决策**：
- **三层验证**：v2 只检测文件存在 → 误报率高；HEAD 可达性 + req 一致 + stage 一致让大部分"非真 stale" 自动清理而不打扰
- **mismatched-stage 不自动清理**：这是 "脚本写过 checkpoint 但 req 状态机走偏" → 真正的不一致，让 PM 介入比静默清理安全

**实施清单**：
1. `scripts/close-req.sh` 入口加 `detect_stale_checkpoint` 函数
2. `scripts/cancel-req.sh`（如存在）配套清理 `.runs/close-req-checkpoint`
3. `INVARIANTS.md` I-CR12（v3）改为三层验证规则
4. `tests/close-req/test-stale-checkpoint.sh`：覆盖 4 种检测结果

---

### 14.4 C3 v3 — schema 完整化

#### 14.4.1 V10 — feature_id stable hash + remove 精确匹配

**问题**：V3 merge 函数的 `feature_id(f)` 假设存在稳定可复算的标识。v2 §12.4.3 schema 写了 `feature` 字段是自由文本（"列表筛选"），rewrite 时 AI 凭语义对齐 → 跨 task / 跨时间不可靠（同一个 feature 在不同 task PM 视图里叫"筛选"、"列表筛选"、"日志筛选"）。

**设计**：feature 加 `feature_id` 字段，值 = stable hash。

**hash 计算**：

```
feature_id = blake2b(
  canonical_module_name +
  '/' +
  normalize(feature_anchor)
)[:12]   # 12 字符 hex
```

其中：
- `canonical_module_name`：V4 解 alias 后的 canonical 名（防 rename 改了 module 名导致 id 漂）
- `feature_anchor`：feature 在 modulespec 内的"锚点"——v3 用 modulespec 内的 H3 标题作锚点（如 `## 列表筛选`）
- `normalize`：去标点、空格、大小写折叠（让 "列表 筛选" 和 "列表筛选" 算同一个）

**写入时机**：

| 时机 | 谁写 |
|---|---|
| close-req rewrite 输出 modulespec 时 | rewrite mode 给每个 feature 注入 HTML 注释 `<!-- feature_id: a3f2c8 -->` |
| task PM 视图 / quickfix metadata | 触及现有 feature 时 PM/AI 必填 `feature_id`（task-spec / quick-fix step 引导）；新增 feature 时空着，rewrite 自动算 |
| modulespec template (`templates/MODULE_TEMPLATE.md`) | 每个 H3 标题下默认注释 `<!-- feature_id: TBD -->` 占位 |

**remove 强制精确匹配**：

V3 merge 函数 `case remove`：必须用 feature_id 匹配，不允许"按 feature 名匹配"。理由：remove 是破坏性操作，"名字模糊匹配"删错了恢复成本高。

**fallback：feature_id 缺失时**：

- task PM 视图 / quickfix 没填 feature_id → V5 lint 阻断不了（V5 只检查 module_impact 不查 feature）；改进：close-req rewrite 入口加二次检查——`module_impact` 中 change_kind 包含 `feature_modify/feature_remove/behavior_only` 但对应 patch 没 feature_id → 阻断，回 PM 补
- 老 modulespec 文件没 feature_id 注释（v3 上线前）→ rewrite 第一次跑时 AI 自动算并写入；PM 审 diff 确认

**关键决策**：
- **不砍 remove 走 PM 审 diff**：v2 §13.4 V10 候选写"或砍 remove 走 PM 审 diff"——v3 不采用。理由：保留 remove 让 PM 视图能精确表达"砍 feature"意图（不只 modify 成空），rewrite 跑 V3 公式时也能产出干净结果；feature_id 精确匹配能消除"删错"风险。
- **hash 12 字符**：碰撞概率极低（modulespec 内 features 数 < 1000 通常），手抄 / 视觉对账短；不用全 32 字符省 modulespec 视觉杂音。

**实施清单**：
1. `templates/MODULE_TEMPLATE.md` 加 `<!-- feature_id -->` 占位
2. `scripts/compute-feature-id.py` 新建（hash 算法 + normalize）
3. `skills/doc-update/SKILL.md` §8 rewrite 输出时调用 + 在草稿展示给 PM
4. `skills/task-spec/SKILL.md` / `skills/quick-fix/SKILL.md` 加 feature_id 填写引导
5. `INVARIANTS.md` 新 I-FT1：feature_id 不可变 → 一旦写入 modulespec 不允许再生（feature 改名也保留 id）
6. `tests/` 覆盖：normalize / 碰撞 / 缺失 fallback / rename 后 id 不变

#### 14.4.2 V11 — schema 字段补全

**问题**：v2 §12.4.3 quickfix metadata schema 缺 `schema_version`（升级时不知道老条目走哪条路径）、`supersedes`（同 feature 多次 quickfix 没有显式关联）、`affected_paths`（影响哪些原型文件 / DESIGN.md 节）、`confirmed_by/at`（who/when 拍板）。

**设计**：扩展 quickfix-log.jsonl schema：

```json
{
  "schema_version": "v3",                      // 新
  "ts": "2026-05-12T10:23:00Z",
  "type": "quickfix",
  "commit": "<sha>",
  "summary": "...",
  "module": ["module-log"],                    // 改数组，v2 是单字符串
  "feature_id": "a3f2c8",                       // V10，可空（add 时）
  "feature_anchor": "列表筛选",                  // 人可读
  "change_type": "modify",                      // V3 公式枚举
  "needs_modulespec_update": true,
  "modulespec_patch": {                         // C4.1 新增（§14.6）
    "op": "modify",
    "fields": {"sort_default": "时间正序"}
  },
  "target_origin_req": "R-2025-098",            // C4.1 新增
  "recorded_in_req": "R-2026-001",              // C4.1 新增
  "supersedes": "<earlier quickfix commit sha>", // 可空，标连续优化
  "affected_paths": [
    "prototypes/log-page.html",
    "DESIGN.md#log-typography"
  ],
  "confirmed_by": "PM",
  "confirmed_at": "2026-05-12T10:23:00Z"
}
```

**字段详解**：

| 字段 | 含义 | 必填 |
|---|---|---|
| `schema_version` | 当前 schema 版本，rewrite mode 按版本走不同路径 | 必 |
| `module` | 改数组：一次 quickfix 可跨多模块（罕见但合法） | 必 |
| `feature_id` | V10 stable hash；新增 feature 可空（rewrite 自动算） | change_type ∈ {modify, remove, behavior-only} 时必填 |
| `feature_anchor` | 人可读锚点，辅助 PM 阅读 log | 必 |
| `modulespec_patch` | C4.1 结构化 patch；rewrite 不仅靠 free text summary | needs_modulespec_update=true 时必 |
| `target_origin_req` | 改的是哪个 req 的产物（历史 req 也行） | 必（默认 = recorded_in_req） |
| `recorded_in_req` | 本条 quickfix 记录在哪个 active req 里 | 必 |
| `supersedes` | 链接到被本次 quickfix 替代的前次 quickfix（同 feature 反复改） | 可空 |
| `affected_paths` | 影响哪些 prototype / DESIGN.md 节 | 必（可为空数组） |
| `confirmed_by/at` | 谁何时拍板 needs_modulespec_update / modulespec_patch | 必 |

**老 schema 升级路径**：见 §14.4.4 V13（downgrade 上限）。

**实施清单**：
1. `templates/quickfix-log.schema.json` 写完整 JSON Schema
2. `skills/quick-fix/SKILL.md` 加交互填表 step
3. `scripts/lint-quickfix-log.py` 新建（commit 前 lint，hook 到 git pre-commit 或 close-req 入口）
4. `tests/quick-fix/test-schema-v3.py` 覆盖必填校验

#### 14.4.3 V12 — `needs_modulespec_update=false` 二次验证

**问题**：v2 §12.4.3 让 PM 拍 `needs_modulespec_update`。但 PM 可能漏判——quickfix 实际改了 modulespec 文字（如改默认值），却标 `false`，rewrite mode 跳过 → modulespec 跟 prototype 脱节，下个 task 读 modulespec 看到旧默认值。

**设计**：close-req 入口反查—— grep `[quick-fix]` commits 的 diff，检查是否触及 `prototypes/` 或 `docs/modules/` 之外的 modulespec-like 内容；对 `needs_modulespec_update=false` 的 quickfix 做 sanity check。

**算法**：

```python
def verify_needs_update_false_entries():
    suspicious = []
    for qf in quickfix_log where needs_modulespec_update == false:
        diff = git_show(qf.commit, '--stat')
        # 红色信号 1：diff 触及 prototypes/ 同时 description 含"默认"、"排序"、"流程"等结构词
        if 'prototypes/' in diff_files and re.search(r'(默认|排序|流程|跳转|展示)', qf.summary):
            suspicious.append((qf, 'structural-word-in-summary'))
        # 红色信号 2：affected_paths 写了 DESIGN.md# 但 needs_modulespec_update=false
        if any('DESIGN.md' in p for p in qf.affected_paths):
            suspicious.append((qf, 'design-touched-but-flag-false'))
    return suspicious
```

**触发动作**：

```
close-req 入口（在 step 0 dirty gate 之后、step 0.5 V16/V17 之前）：

if suspicious := verify_needs_update_false_entries():
    显示 PM：
    "检测到 <N> 条 quickfix 标记 needs_modulespec_update=false，但有红色信号：
       <列表 with reason>
     请逐条确认：
       (a) 升级为 true 并补 modulespec_patch
       (b) 保留 false（PM 二次确认）
       (c) 取消本次 close-req，回去 /quickfix-revise 修"
```

**关键决策**：
- **不静默**：哪怕 0 条 suspicious 也写 audit "二次验证通过"，方便追溯
- **结构词列表来自经验**：初始硬编码 `默认|排序|流程|跳转|展示|顺序|过滤|权限|入口`，PM 用一阵后可调（写进 `scripts/quickfix-structural-words.txt`）
- **不允许"全部 (b) 保留"快捷键**：每条都要逐条点 (b)，防 PM 一键放行

**实施清单**：
1. `scripts/lint-quickfix-needs-update.py` 新建（含 suspicious 检测算法）
2. `scripts/close-req.sh` step 0 后调用，结果阻断 close-req（除非 PM 逐条确认）
3. `scripts/quickfix-structural-words.txt` 写默认词表
4. `templates/close-req-verification-audit.template.md` 写 audit 格式
5. `tests/quick-fix/test-needs-update-verify.py`：覆盖红色信号 + PM 三选

#### 14.4.4 V13 — 老 quickfix downgrade 上限 + 显式 defer/skip

**问题**：v2 §12.4.3 末尾"老 quickfix 兼容：rewrite 时 AI 推测影响 + PM 人工指认"——AI 推测 N=20 条老条目时 PM 工作量爆炸；且没说"PM 不想现在处理"的逃生口。

**设计**：

1. **downgrade 总量上限 ≤5 条 / close-req**：
   - 老条目（schema_version != v3，缺 module/feature_id 等关键字段）触发 downgrade 处理
   - 超 5 条 → fail：提示 PM 走 `/quickfix-backfill` 单独流程提前补好

2. **每条 downgrade 三选门**：
   - **resolve**：PM 人工指认 module / feature_id / change_type，写回 quickfix-log（commit `[quickfix-backfill]`）
   - **defer**：标记 `deferred: true`，写下次 close-req 处理（带 audit reason）
   - **skip**：标记 `skipped_in_rewrite: true`，rewrite 跳过本条；不阻断 close-req（PM 接受"这条永久不进 modulespec"）

3. **defer / skip 都写 audit marker**：

```jsonl
{ ... existing fields ..., "downgrade_decision": "skip", "decided_at": "2026-05-12T10:30:00Z", "decided_by": "PM", "reason": "原型已下线，不必入 modulespec" }
```

4. **defer 跨 close-req 累积上限**：累积 deferred 老条目 ≥10 条时强制 PM 走 backfill（避免无限堆积）

**`/quickfix-backfill` 单独流程**（新 skill）：

```
skills/quickfix-backfill/SKILL.md
  输入：req-id（或 --all-active）
  流程：
    1. 列出本 req 范围内所有 schema_version != v3 的 quickfix
    2. 逐条 PM 指认（resolve / defer / skip），可批量按 commit 时间段 / module 过滤
    3. 写回 quickfix-log 各条 + commit
  退出：缺失 quickfix 数量 = 0 或 ≤5
```

**关键决策**：
- **5 条上限**：经验值（PM 单次 cognitive load）；可在 round 4 autoplan 后调
- **defer 不无限**：累积 10 条 hard cap，避免延期文化
- **skip 是合法选项**：PM 有权说"这条不再相关"；audit 留痕足够（不让 framework 把 PM 困死）

**实施清单**：
1. `skills/quickfix-backfill/SKILL.md` 新建
2. `scripts/lint-quickfix-log.py` 加 schema_version 检测 + 5 条上限计数
3. `scripts/close-req.sh` step 1 之前调用 downgrade gate
4. `INVARIANTS.md` 新 I-QF1：close-req 入口老 quickfix > 5 → 必须先走 /quickfix-backfill
5. `tests/quickfix-backfill/`：覆盖 5 条阈值 / defer 累积 / skip audit

---

### 14.5 横切

#### 14.5.1 V14 — Token break-even 算法 + N=1 fallback

**问题**：D13 的论证基础是"N 次 settlement → 1 次 rewrite 省 token"。但 N=1（一个 req 只有 1 个 task）时，rewrite 反而比 settlement 更贵（rewrite 要重读整 module，settlement 行级 patch）。v2 §12.8 标了"GO/NO-GO 实测"但没给 break-even 算法。

**设计**：

**单 close-task 成本**（settlement 模式）：

```
C_settle(task) ≈
  C_skill_indir +       # doc-update skill 指令加载
  C_modulespec_read +   # 当前 modulespec 全文读（同 module 部分）
  C_pm_view_read +      # 本 task PM 视图
  C_diff_reasoning +    # AI 推理改哪行
  C_write +             # 写回（patch 大小）
  C_pm_review_diff
```

**单 close-req rewrite 成本**：

```
C_rewrite(req) ≈
  C_skill_indir +
  C_modulespec_read +                # 整 module 全文
  Σ_i (C_pm_view_read_i) +           # 每个 task PM 视图（N 个）
  C_quickfix_log_read +              # quickfix metadata（M 条）
  C_merge_reasoning +                # V3 函数应用 + 冲突门
  C_full_rewrite_write +             # 整 module 重写
  C_pm_review_per_module             # PM 审 diff
```

**break-even 公式**：

```
N * C_settle ≈ C_rewrite
  → N_BE = (C_rewrite_fixed + C_full_rewrite_write + C_pm_review_per_module + C_merge_reasoning + C_quickfix_log_read)
           / (C_skill_indir + C_diff_reasoning + C_write + C_pm_review_diff - C_pm_view_read_i_in_rewrite)
```

实际算需要先 instrument。**实操路径**：

1. **测量 phase**（pre-flight，§14.10）：
   - adminconsole4 跑一个真实 req（4-5 tasks + 2-3 quickfix）
   - 模拟跑两遍：一遍 settlement（每个 task 都走老 doc-update），一遍 rewrite（一次 close-req）
   - 记录每段 token + PM 主观工作量评分
2. **算出 N_BE 实测值**：可能在 2-3 区间
3. **写进 doc-update §8 头部**作运行时 fallback 判断：

```
rewrite mode 入口：
  count_patches = N_tasks_pm_view_changes + M_quickfix_needs_update
  if count_patches < N_BE_threshold (从配置读，默认 2):
    fall back to settlement mode：
      逐 patch 跑老 doc-update（PM 见到"本 req 改动少，走传统模式更便宜"提示）
    else 跑 rewrite mode
```

**配置**：`config/doc-update.yml` 加 `rewrite_break_even_threshold: 2`，PM 可调。

**N=1 特殊**：恒走 settlement（rewrite 必然更贵）；如果配置改 0 强制 rewrite 也允许（出于"统一流程"考虑），但默认值是 2。

**关键决策**：
- **不硬编 2**：每个项目 module 大小不同（adminconsole4 modules 大 vs 小 module 项目），break-even 不一样；配置化让 PM 可在实测后调
- **fallback settlement 不复原全部 v2 砍掉机制**：只复原 doc-update settlement 单 patch 路径；半关闭 / SKIP marker 不复活。fallback 是 D13 内置救济，不是回退 v2。
- **保留 N=1 fallback** 是 round 3 autoplan 标的"D13 不能假设 N>>1"风险点对冲。

**实施清单**：
1. `config/doc-update.yml` 加阈值字段
2. `skills/doc-update/SKILL.md` §8 头部加 N 检测 + 分流
3. `scripts/measure-rewrite-tokens.py` 新建（pre-flight 用）
4. `tests/doc-update/test-break-even.sh`：N=1 / N=2 / N=5 分流验证

#### 14.5.2 V15 — 测试 fixture

**问题**：v2 §12.8 提到"测试套件影响升级"，没给覆盖矩阵。round 3 autoplan 标的 critical 之一是"无端到端 fixture"——unit test 通过不代表组合通过。

**fixture 目录结构**：

```
tests/fixtures/d13-v3/
├── case-01-rewrite-success/
│   ├── README.md            # 场景描述
│   ├── input/
│   │   ├── base-modulespec/
│   │   ├── req-meta.json
│   │   ├── tasks/T*.md
│   │   └── quickfix-log.jsonl
│   ├── expected-output/
│   │   ├── new-modulespec/
│   │   ├── audit.md
│   │   └── events.jsonl
│   └── run.sh               # 调 rewrite mode 跑
├── case-02-rewrite-fail-retry/
├── case-03-no-residue/
├── case-04-partial-accept/
├── case-05-remove-feature/
├── case-06-old-downgrade/
├── case-07-multi-worktree-A/
├── case-08-multi-worktree-B/
├── case-09-multi-worktree-C/
├── case-10-quickfix-realtime/
└── case-11-quickfix-history-ref/
```

**11 个 fixture 覆盖**：

| # | 场景 | 验证什么 |
|---|---|---|
| 01 | rewrite 成功路径（3 task + 2 quickfix，无冲突） | V3 公式正确应用 + V6 temp worktree merge ff |
| 02 | rewrite 中断 → retry 成功 | V6 失败清理 + V9 checkpoint 检测 |
| 03 | rewrite 全程无残留（rewrite 后扫 tmp/ + .runs/） | V6 隔离边界 |
| 04 | 3 module rewrite，PM 接受 A、拒绝 B、defer C | V8 部分接受 + audit |
| 05 | change_type=remove 全链路（task PM 视图 → quickfix → rewrite 出干净文档） | V3 remove + V10 feature_id 精确匹配 |
| 06 | 6 条老 quickfix（schema v1）→ 阻断 → /quickfix-backfill 后通过 | V13 上限 + defer/skip audit |
| 07 | 多 req 并行——A、B 改不同 module → step 0.5 case A | V16 分类 A 默认继续 |
| 08 | 多 req 并行——同 module 不同 section（无语义冲突） | V16 分类 B 自动合并 + simple confirm |
| 09 | 多 req 并行——同 feature anchor 不同结论 | V16 分类 C 显式决策门 |
| 10 | quickfix 实时写 modulespec → 起 task → close-req | C4.2 snapshot + C4.3 rewrite 消费 |
| 11 | quickfix 改历史 req 产物 | C4.4 归因 + audit |

**fixture 形态**：

- 每个 case 用 git 仓库 fixture（小型，pre-built）
- run.sh 跑相关脚本 → 用 diff 跟 expected-output 对比
- expected-output 是 deterministic（V2 topo order 保证可重放）

**关键决策**：
- **整 git 仓 fixture 不只 JSON**：rewrite mode 重度依赖 git 状态（HEAD / worktree / branch），mock 不出真效果
- **不写 chaos fixture**（如随机失败注入）：v3 范围太大；放 round 4 后

**实施清单**：
1. `tests/fixtures/d13-v3/` 各 case 目录 + run.sh
2. `tests/run-d13-v3.sh` 总入口跑全套
3. CI 集成（待 CI 决策）

---

### 14.6 C4 — quickfix 重定位（§13.10 拍板）

> **背景**：§13.10 推翻 §13.7。quickfix 实际意图四点（产品决策 / 同时改原型+modulespec / 可改历史 req 产物 / 必须挂当前 active req）已 PM 拍板。
> **本节**：把意图落成可执行机制。

#### 14.6.1 C4.1 — schema 扩展（已在 §14.4.2 V11 写入）

V11 schema 已含 C4.1 三字段：`target_origin_req` / `recorded_in_req` / `modulespec_patch`。本节补 patch 子结构：

```json
"modulespec_patch": {
  "op": "modify",                            // V3 公式枚举：add/modify/remove/behavior-only
  "feature_id": "a3f2c8",                    // V10
  "feature_anchor": "列表筛选",
  "fields": {                                // op=modify 时的字段级 patch
    "sort_default": "时间正序"                // null = 不改；非 null = 替换
  },
  "new_feature": null                        // op=add 时这里是完整 feature payload
}
```

**字段含义**：
- `op=add`：`fields=null`，`new_feature={feature_id?, anchor, payload}`，feature_id 可空（rewrite 算）
- `op=modify`：`fields` 是局部 patch（只列要改的字段），feature_id 必填
- `op=remove`：`fields=null`，feature_id 必填
- `op=behavior-only`：`fields={behavior: "..."}`，feature_id 必填

**结构化 vs 自由文本**：
- v2 schema 的 `summary` 字段保留（PM/AI 读 log 用），但 rewrite 时**不消费** summary——只消费 `modulespec_patch`
- 这强制 PM/AI 在 quickfix 时就把"改什么"想清楚，不留模糊文本到 rewrite 再猜

#### 14.6.2 C4.2 — quickfix 写 modulespec 协调（snapshot lock）

**问题**：quickfix 实时改 req 分支的 modulespec → 期间已起的 task worktree 不能突然看到新 modulespec（合同稳定原则）。

**设计**：task-execute 起来时 freeze modulespec 到 task worktree。

**机制**：

```
task-execute 起 task worktree 流程（v3）：

1. git worktree add <task-worktree-path> -b task/<T-id> <req-branch HEAD>

2. snapshot lock：
   $ cp -r <req-worktree>/docs/modules/ <task-worktree>/.runs/modulespec-snapshot/
   $ echo "{ts, base_commit: <sha>, modulespec_snapshot_path: '.runs/modulespec-snapshot'}" \
       > <task-worktree>/.runs/task-snapshot.json

3. task-execute 读 modulespec：
   - 优先读 .runs/modulespec-snapshot/（snapshot，恒定）
   - 不读 docs/modules/（task worktree 本地 docs/modules/ = git checkout 时刻的状态，但被本规则禁止直接读）
```

**quickfix 在 req worktree 写 modulespec**：

```
quick-fix skill 步骤：

1. PM 描述改动
2. AI 推断 modulespec_patch + 填 metadata
3. PM 确认
4. 在 req worktree apply patch：
   - 改 prototype / DESIGN.md
   - 跑 V3 公式 apply patch 到 docs/modules/<module>.md
5. commit：
   - 一个 commit [quick-fix] 含 prototype + modulespec 改动 + log entry
   - 不再分两个 commit（v2 是分 [quick-fix] + [quick-fix-log] 两次）
```

**已起 task worktree 影响**：完全不受。task 在 .runs/modulespec-snapshot/ 读，不会看到 req 分支新写入。

**task close 时怎么办**：

- task 工作期间不感知 quickfix 改了 modulespec
- task PM 视图描述 task 的改动 → 进 V3 merge 函数时跟 quickfix 改动同等地位 patch
- 冲突由 V3 函数 + V16/V17 step 0.5 surface

**新起 task worktree**：snapshot 自然包含已 commit 的 quickfix → 后起 task 看到新 modulespec

**关键决策**：
- **snapshot 用 cp 而不 symlink**：symlink 跟着 req worktree 改动跑 → 破坏合同稳定；硬复制保证恒定
- **snapshot 占空间**：modulespec 总文本量一般 < 100KB → 可忽略
- **task 期间 PM 在 task worktree 内修 modulespec 是反模式**：禁止。所有 modulespec 改动只在 req worktree（quickfix）或 close-req rewrite。`INVARIANTS.md` 新 I-TT2：task worktree 内 docs/modules/ 不允许被修改（hook 检测）。

**实施清单**：
1. `scripts/create-task-worktree.sh` 加 snapshot 复制
2. `templates/task-snapshot.schema.json` 新建
3. `skills/task-execute/SKILL.md` 步骤 2.1 D13 模式：明确读 snapshot 路径
4. `skills/quick-fix/SKILL.md` 单 commit + 写 modulespec 步骤
5. `INVARIANTS.md` 新 I-TT2：task worktree docs/modules/ 不可改
6. `tests/quickfix-realtime/test-snapshot-isolation.sh`：quickfix 改 modulespec → 已起 task 看不到 / 新起 task 看到

#### 14.6.3 C4.3 — close-req rewrite 消费已 applied quickfix

**问题**：quickfix 已实时写 modulespec → close-req rewrite 时 base modulespec 已含 quickfix 改动；如果 rewrite 又把 quickfix 当 patch 应用一遍 → 重复 apply / 冲突。

**设计**：rewrite mode 输入区分两类 patch：

| 类型 | 来源 | 是否已落到 base | rewrite 处理 |
|---|---|---|---|
| **task PM 视图** patch | 同 req 内 task 的 PM 视图改动 | 否（task close 时不写 modulespec，D13 主流程） | 应用 + V3 公式 |
| **quickfix-applied** patch | 同 req 内 quickfix `modulespec_patch`，且已实时 apply 到 base | 是 | **仅验证一致性**（base 中现状是否 == patch 期望结果），不重复 apply |
| **quickfix-unapplied** patch | 老 schema quickfix 或 needs_modulespec_update=true 但因故未实时 apply 的 | 否 | 应用 + V3 公式 |

**判定方式**：

- quickfix schema_version=v3 且 `applied: true` 标记 → quickfix-applied
- quickfix schema_version=v3 且 `applied: false`（罕见，apply 失败留待 rewrite）→ quickfix-unapplied
- 老 schema → quickfix-unapplied（走 V13 downgrade 路径）

**`applied` 字段**：quickfix step 4 commit 时 apply 成功后写入 metadata。

**rewrite 处理 quickfix-applied 的逻辑**：

```
for qf in quickfix_log where applied == true:
  expected = qf.modulespec_patch
  actual_state = state[feature_id(expected)]
  if not matches(expected, actual_state):
    → CONFLICT_APPLIED_DRIFT
       （已 applied 的 patch 跟当前 modulespec 对不上 → base 被后续 patch / 手动改 / rebase 改过）
       暂停，PM 决策：
         (a) 信 base：把 quickfix log 标 superseded
         (b) 信 patch：rollback base 到 patch 结果（罕见，需 PM 明确选）
         (c) 调查：让 PM 手动比对
```

**matches() 实现**：feature_id 对得上，且 patch.fields 描述的所有字段在 base 里跟 patch 一致。

**关键决策**：
- **不静默 drop applied patches**：drift 检测是必要的护栏（quickfix 写完后被其他动作改坏 → rewrite 时 surface）
- **applied 字段是 quickfix step 4 commit 后写**：这要求 quickfix step 4 是事务性的（写 modulespec + 标 applied 在同一个 commit）

**实施清单**：
1. `templates/quickfix-log.schema.json` 加 `applied` 字段
2. `skills/quick-fix/SKILL.md` step 4 commit 后写 `applied: true`
3. `skills/doc-update/SKILL.md` §8 加 applied/unapplied 分流逻辑
4. `tests/doc-update/test-rewrite-applied-skip.sh`：applied patches 不重 apply
5. `tests/doc-update/test-rewrite-applied-drift.sh`：drift 触发 CONFLICT 门

#### 14.6.4 C4.4 — 历史 req 产物归因

**问题**：quickfix 改的可能是历史 req 早就沉淀进 modulespec 的 feature → modulespec 文件没说"哪行来自哪 req" → audit / rollback 困难。

**设计**：modulespec 文件每个 feature anchor 加来源 req 注释。

**格式**（modulespec 文件渲染）：

```markdown
## 列表筛选
<!-- feature_id: a3f2c8 -->
<!-- origin_req: R-2025-098 -->
<!-- last_modified_req: R-2026-001 -->
<!-- last_modified_at: 2026-05-12T10:23:00Z -->

默认按时间正序排序，PM 可点击表头切换升降序。
```

**字段含义**：
- `origin_req`：feature 首次进 modulespec 时的 req（add 操作来源）
- `last_modified_req`：最近一次修改本 feature 的 req（modify / behavior-only 操作来源）
- `last_modified_at`：最近修改的 commit 时间戳

**写入时机**：rewrite mode 输出 modulespec 时根据 V3 merge 历史自动注入：

- 新 add 的 feature → origin_req = recorded_in_req of patch
- modify / behavior-only → 只更 last_modified_*
- remove → 整个 feature 从 modulespec 移除（注释一起删），但 `requirements/closed/<req>/feature-removal-log.md` 留 audit

**quickfix `target_origin_req` 字段消费**：

- quickfix metadata 已含 `target_origin_req`（C4.1）：PM 拍 quickfix 改的是哪个 origin_req 的产物
- rewrite 时把 `target_origin_req` 跟 base modulespec 的 `origin_req` 比对：
  - 一致 → 走常规 modify 路径
  - 不一致 → 报警 PM："你说改 R-2025-098 的产物，但 base 里这个 feature origin_req 是 R-2024-050，确认改的是同一个吗？"

**关键决策**：
- **三注释（origin / last_modified / last_modified_at）足够**：再加更多（如 modify_history 数组）会让 modulespec 视觉拥挤；history 已在 git log 里
- **target_origin_req 校验是 sanity check，不阻断**：drift 可能合法（feature 改名 / module 合并），PM 看到 warning 自己判断

**实施清单**：
1. `templates/MODULE_TEMPLATE.md` feature 块格式加注释
2. `skills/doc-update/SKILL.md` rewrite 输出时注入注释（基于 V3 公式追踪）
3. `requirements/closed/<req>/feature-removal-log.md` 模板新建
4. `skills/quick-fix/SKILL.md` metadata 填写时 PM 选 target_origin_req（从 base modulespec 现有 origin_req 列表推荐）
5. `tests/audit/test-origin-attribution.sh`：覆盖 add/modify/remove/cross-req drift

#### 14.6.5 C4.5 — PM 在 active req 中"记录"quickfix UX

**问题**：§13.10 第 4 点要求"必须在当前 active req 中记录 quickfix"。当前 quickfix-log.jsonl 是结构化 log，PM 视图里看不到 → PM 想在 req 内回顾"本 req 做过哪些 quickfix" 要去 jsonl 翻。

**设计**：req 内 PM 视图加 quickfix 章节。

**位置**：`requirements/active/<req>/quickfix-summary.md`（每个 req 一份，rewrite mode 入口生成）

**生成时机**：

| 时机 | 谁生成 |
|---|---|
| 每次 quickfix step 4 commit 后 | quickfix skill 自动追加一条 |
| close-req 入口 | 重新整理 + 按 module 分组（不只是 append-only） |
| stage-gate 6→7 | re-render（PM 在 close-req 之前能看到完整列表） |

**内容**：

```markdown
# req R-2026-001 quickfix summary

> 自动生成。改 quickfix 请用 `/quick-fix`；改本文件无效。

## 时间线（按 commit 顺序）

| ts | summary | module | feature | change | origin_req | applied |
|---|---|---|---|---|---|---|
| 2026-05-12 10:23 | 改筛选默认排序 | log | 列表筛选 (a3f2c8) | modify | R-2025-098 | ✅ |
| 2026-05-12 14:05 | 新增导出 CSV | log | 导出 CSV (5d8e21) | add | R-2026-001 | ✅ |

## 按 module 分组

### module-log
- 列表筛选（modify，origin R-2025-098）：sort_default 时间倒序 → 正序
- 导出 CSV（add，origin 本 req）：新增功能

## audit 提示
- 跨 req 改动：1 条改了 R-2025-098 的产物
```

**PM 入口**：

- `scripts/status-view.py` / `skills/task-status/SKILL.md`（现有 req/task 状态查询入口）增加"显示 quickfix-summary.md 内容"section
- close-req gate 在 step 0 前显示一个"请审 quickfix summary"提示，PM 浏览后确认

**关键决策**：
- **每个 req 一份 summary 而不是全局 dashboard**：PM 看 req 范围更聚焦；全局 dashboard 待 v4
- **summary 不替代 jsonl**：jsonl 是 source of truth（机器读），summary 是 PM 视图（人读）
- **生成是 derived view 不可手改**：手改会被 close-req 重写覆盖；hook 警告

**实施清单**：
1. `scripts/render-quickfix-summary.py` 新建（jsonl → md）
2. `skills/quick-fix/SKILL.md` step 4 后调用渲染
3. `skills/close-req/SKILL.md` step 0 前调用渲染 + 显示
4. `scripts/status-view.py` / `skills/task-status/SKILL.md` 加 quickfix summary section
5. `INVARIANTS.md` 新 I-QF2：quickfix-summary.md 是 derived，PM 修改无效（rebuild from jsonl）

---

### 14.7 多 worktree 并行——方向 (e) close-time detection（V16+V17）

> **背景**：§13.11 PM 拍板方向 (e)，close-req 和 close-task 都做 step 0.5。本节是 V16（跨 req / 共享 main）+ V17（同 req 跨 worktree / 共享 req 分支）的合并设计。
> **AI 责任**：主动检测 + 分类 + 提议合并方案 + 应用 patch；PM 责任：判断 req 关联性 + 处理真冲突的语义决策。

#### 14.7.1 共用 step 0.5 工作流（V16 / V17 同一套）

**触发位置**：

| Gate | 检测对比 | 共享资源 |
|---|---|---|
| close-req step 0.5 | base modulespec (本 req 起来时 = main HEAD@req_start) vs main 当前 | main 上的 modulespec / DESIGN.md |
| close-task step 0.5 | task 起来时 req 分支 HEAD snapshot vs req 分支 当前 | req 分支的 modulespec / quickfix |

**算法（公共部分）**：

```
def step_0_5(local_base, remote_now, local_patches):
    """
    local_base:    本 worktree 起来时记的 base commit
    remote_now:    远端共享资源当前 HEAD（main 或 req branch）
    local_patches: 本 worktree 累积的改动（task PM 视图 / quickfix metadata）
    """
    # 1. 取 remote 在 local_base..remote_now 之间的改动
    remote_patches = extract_patches_between(local_base, remote_now)
      （借 V1 req-module-impact.py 类似算法，输出 module/feature 粒度的 patch list）

    # 2. 跑 V3 三方 merge：
    state = M(base=local_base.modulespec, patches=remote_patches)
    final = M(state, patches=local_patches)

    # 3. 分类
    if no_overlap(remote_patches, local_patches):
        return ('A', auto_continue)
    elif overlap_but_no_semantic_conflict(remote_patches, local_patches):
        return ('B', auto_merge, brief_confirm_diff)
    else:
        conflicts = collect_conflicts_from_V3()
        return ('C', conflicts, ai_proposals)
```

**no_overlap / overlap_but_no_semantic_conflict 判定**：

| 判定 | 条件 |
|---|---|
| no_overlap (A) | remote_patches 和 local_patches 的 (module, feature_id) 集合不相交 |
| overlap_but_no_semantic_conflict (B) | 集合相交，但 V3 merge 函数应用后无 CONFLICT_* 抛出（add 互不冲突 / modify 不同字段 / behavior-only 跟 modify 兼容） |
| semantic_conflict (C) | V3 merge 函数抛出任何 CONFLICT_*（同字段不同值 / remove vs modify 等） |

#### 14.7.2 V16 — 多 req 并行（close-req step 0.5）

**完整 close-req 流程（v3 修订）**：

```
step 0    入口 dirty gate（V7）
step 0.5  多 req 并行检测（V16）：
          - local_base = req 起来时 main HEAD（从 .req-meta.json 读 origin_commit）
          - remote_now = main 当前 HEAD（git fetch origin main）
          - local_patches = 本 req 累积（task PM 视图 + quickfix-log）
          - 跑 step_0_5() 算法
          - 分类处理：
            A → auto_continue（不打扰 PM）
            B → AI 显示三方 merge 后的 diff，PM 简短 confirm（一次性）
            C → 进显式决策门，AI 提议 2-3 合并方案，PM 选
          - 结果：合并后 patch set 注入 step 2 rewrite 输入

step 1    写 close-report.md（含 step 0.5 audit summary）
step 1.5  checkpoint
step 2    rewrite mode (V6 temp worktree)，输入 = step 0.5 输出的合并 patch set
step 3-6  同 V7 定义
```

**AI 冲突分类器（B vs C 判定）**：

V3 公式直接给——B = V3 merge 应用后无 CONFLICT_*；C = 有任意 CONFLICT_*。无须额外语义模型。

**AI 提议 2-3 合并方案（C 分支）**：

对每个 CONFLICT_* 生成方案：

| 冲突类型 | 方案模板 |
|---|---|
| CONFLICT_ADD_EXISTING | (a) 本 req 改成 modify 合并 (b) 本 req 改 feature 名（rename + add）(c) skip 本 req add |
| CONFLICT_MODIFY_MISSING | (a) 本 req 改成 add (b) skip (c) 检查 V4 rename |
| CONFLICT_REMOVE_MISSING | (a) skip remove (b) confirm（已被远端 remove，无需再 remove）|
| CONFLICT_FIELD_CHANGE | (a) 用远端值 (b) 用本 req 值 (c) 写第三个 |

PM 选完后 AI apply → 注入 rewrite 输入。

**实施清单**：
1. `scripts/step-0-5-detect.py` 新建（公共算法）
2. `scripts/close-req.sh` step 0.5 调用 + 三分类处理
3. `skills/close-req/SKILL.md` 加 step 0.5 描述 + 决策门 UX
4. `templates/step-0-5-audit.template.md` 新建（A/B/C 结果都写一份 audit）
5. `INVARIANTS.md` 新 I-CR17：close-req step 0.5 必须先于 step 1（写 close-report 之前）

#### 14.7.3 V17 — 同 req 内 task 并行（close-task step 0.5）

**完整 close-task 流程（v3 修订）**：

```
step 0    task worktree dirty gate
step 0.5  同 req 跨 worktree 检测（V17）：
          - local_base = task 起来时 req 分支 HEAD（task-snapshot.json，C4.2）
          - remote_now = req 分支 当前 HEAD（git fetch req-branch）
          - local_patches = task 的 PM 视图（task md 内 PM 反馈段）
          - 跑 step_0_5() 算法
          - 分类处理 A/B/C（同 V16）
          - 结果：合并后 task PM 视图注入 task close commit

step 1    把 task PM 视图（含 step 0.5 合并结果）写到 task md
step 2    commit task PM 视图 + merge task → req 分支
step 3    清理 task worktree（含 .runs/modulespec-snapshot/）
```

**V17 共享资源的特殊性**：

- close-task 时 req 分支可能已有：(a) 其他 task close 写的 task PM 视图；(b) PM 在 req 分支做的 quickfix（含 modulespec_patch + prototype 改动）
- 检测对象不是 modulespec 本体（task worktree 不写 modulespec），而是 **task PM 视图 + quickfix patches** 在 V3 公式下的兼容性

**算法适配**：

```
local_patches = task A1 的 PM 视图改动（推断成 V3 patch 集）
remote_patches = (
  其他已 close task 的 PM 视图 +
  quickfix-log 中 applied=true 的 patch
)

跑 V3 merge：base=task-snapshot.modulespec
  → state1 = M(base, remote_patches)
  → final = M(state1, local_patches)

分类同 V16。
```

**B/C 处理与 V16 等价**：AI 提议方案 + PM 选 + apply。

**应用结果落到哪**：

- task PM 视图被修订（PM 选的合并版本）→ 写 task md
- 不直接改 modulespec（D13 主流程，modulespec 只在 close-req rewrite 改）
- step 0.5 audit 写 task md 注脚 + req 分支 audit log

**关键决策**：
- **V17 不直接改 modulespec**：task 不写 modulespec 是 D13 主流程，V17 保持
- **V17 触发的修订写回 task PM 视图**：让 close-req rewrite 看到的本 req task 视图是已合并版本（避免 close-req 又重做一遍 step 0.5）

**实施清单**：
1. `scripts/close-task.sh` step 0.5 调用
2. `skills/close-task/SKILL.md` 加 step 0.5 描述
3. 同 V16 共用 `step-0-5-detect.py` + audit 模板
4. `INVARIANTS.md` 新 I-CT9：close-task step 0.5 必须先于 task PM 视图 commit

#### 14.7.4 step 0.5 跟 C4 协调

**问题**：C4.3 close-req rewrite 已经区分 applied / unapplied patches；step 0.5 又跑一遍 V3 三方 merge——会重复处理？

**协调**：

| 阶段 | 输入 | 处理 | 输出 |
|---|---|---|---|
| step 0.5 | base@req_start + remote_now main patches + 本 req 累积 patches | V3 三方 merge → 检测 A/B/C，合并 patch set | 一份"step 0.5 已合并的 patch set"，含 origin marker |
| step 2 rewrite | base@main_now + step 0.5 合并 patch set | V3 公式应用，区分 applied / unapplied（C4.3） | 新 modulespec |

step 0.5 是 **patch 域的合并**（把 main 改动跟本 req 累积合一），step 2 是 **应用域的合并**（base + patch → 新 modulespec）。两层不冲突：step 0.5 解决"跨 worktree 改动如何合"，step 2 解决"合并后的 patch 如何写入 modulespec"。

**applied/unapplied 在 step 0.5 怎么算**：

- 本 req quickfix applied=true → 已在本 req 分支 modulespec 中，step 0.5 取本 req 分支 HEAD 时这部分已包含
- 跨 req（main 已合的别的 req）quickfix → 它们已是 main 的一部分，作 remote_patches 来源；不区分 applied / unapplied，全部当 "已落 main"

#### 14.7.5 多 worktree 并行 — 跨 worktree 加锁防爆

**问题**：多 worktree 同时跑 close-req 时，两个都到 step 0.5 → 都看到对方"还没合"→ 互相提议合并 → 第一个 commit 后第二个的 step 0.5 又过时 → race。

**设计**：close-req 进入 step 1.5 checkpoint 时加 **main 推进锁**：

- 用 git ref：`refs/locks/close-req-active` 指向当前 close-req 的 req
- 抢锁失败（ref 已存在）→ close-req 中止并提示"另一个 close-req 进行中（req=<X>），等其完成再试"
- 锁在 step 5 push main 之后清理（成功）或 V6/V8 失败清理路径清理（失败）

**关键决策**：
- **锁在 step 1.5 拿不在 step 0**：让 step 0.5 在无锁下做尽量多探索；commit/push 时才独占
- **锁失败不排队**：PM 单人 + 多 worktree 同时 close 罕见；中止重试比写排队队列简单
- **task close 不锁**：close-task 写 req 分支，多 task 并 close 的冲突由 git 自然处理 + V17 step 0.5 兜底

**实施清单**：
1. `scripts/acquire-close-req-lock.sh` + `release-close-req-lock.sh` 新建（基于 git ref）
2. `scripts/close-req.sh` step 1.5 / step 5+ 调用
3. `INVARIANTS.md` 新 I-CR18：close-req step 1.5 必须先拿锁；锁状态在 events 写 audit

---

### 14.8 v3 改动清单（替代 §12.6）

> v3 全集 = v2 §12.6 33 项 + v3 新增/修订。v2 §12.6 中标 ✅ 已对的不重列；下表只列 v3 相对 v2 的增量。

| # | 文件 / skill | 操作 | 关联 task |
|---|---|---|---|
| v3-01 | `scripts/req-module-impact.py` | 新建 | V1 |
| v3-02 | `scripts/req-event-order.py` | 新建（topo order） | V2 |
| v3-03 | `scripts/compute-feature-id.py` | 新建（feature_id hash） | V10 |
| v3-04 | `scripts/check-task-meta.py` | 新建（module_impact lint） | V5 |
| v3-05 | `scripts/lint-quickfix-log.py` | 新建（schema lint + downgrade 上限） | V13, V11 |
| v3-06 | `scripts/lint-quickfix-needs-update.py` | 新建（V12 二次验证） | V12 |
| v3-07 | `scripts/render-quickfix-summary.py` | 新建 | C4.5 |
| v3-08 | `scripts/step-0-5-detect.py` | 新建（V16/V17 公共算法） | V16, V17 |
| v3-09 | `scripts/acquire-close-req-lock.sh` / `release-close-req-lock.sh` | 新建（git ref 锁） | V16 |
| v3-10 | `scripts/measure-rewrite-tokens.py` | 新建（pre-flight） | V14 |
| v3-11 | `scripts/create-task-worktree.sh` | 加 modulespec snapshot 复制 | C4.2 |
| v3-12 | `scripts/close-req.sh` | 重排：dirty gate / step 0.5 / 拿锁 / temp worktree rewrite / 三层 checkpoint 验证 / part-commit | V6, V7, V8, V9, V16, V12, V13 |
| v3-13 | `scripts/close-task.sh` | 加 step 0.5 | V17 |
| v3-14 | `scripts/cancel-req.sh` | 清理 close-req checkpoint + 释放锁 | V9 |
| v3-15 | `skills/doc-update/SKILL.md` | §8 改：N break-even fallback / temp worktree / applied/unapplied 分流 / part-commit | V14, V6, C4.3, V8 |
| v3-16 | `skills/task-spec/SKILL.md` | 加 module_impact 填表 + module rename 识别 + feature_id 填表 | V5, V4, V10 |
| v3-17 | `skills/task-execute/SKILL.md` | 步骤 2.1 改：读 `.runs/modulespec-snapshot/` | C4.2 |
| v3-18 | `skills/quick-fix/SKILL.md` | 大改：单 commit + 写 modulespec patch + metadata 扩展（含 modulespec_patch / target_origin_req / applied）+ render summary | C4.1, C4.2, C4.5, V11 |
| v3-19 | `skills/close-req/SKILL.md` | 加 step 0.5 描述 + 决策门 UX + part-commit + downgrade gate + V12 | V16, V8, V13, V12 |
| v3-20 | `skills/close-task/SKILL.md` | 加 step 0.5 | V17 |
| v3-21 | `skills/quickfix-backfill/SKILL.md` | 新建 | V13 |
| v3-22 | `scripts/status-view.py` / `skills/task-status/SKILL.md` | 显示 quickfix-summary section | C4.5 |
| v3-23 | `templates/MODULE_TEMPLATE.md` | feature 块加 feature_id / origin_req / last_modified 注释 | V10, C4.4 |
| v3-24 | `templates/task.template.md` | frontmatter 加 module_impact | V5 |
| v3-25 | `templates/.req-meta.schema.json` | 加 module_aliases | V4 |
| v3-26 | `templates/quickfix-log.schema.json` | v3 schema 全字段 | V11, C4.1 |
| v3-27 | `templates/task-snapshot.schema.json` | 新建 | C4.2 |
| v3-28 | `templates/close-req-rewrite-partial.template.md` | 新建 | V8 |
| v3-29 | `templates/close-req-verification-audit.template.md` | 新建 | V12 |
| v3-30 | `templates/step-0-5-audit.template.md` | 新建 | V16, V17 |
| v3-31 | `requirements/closed/<req>/feature-removal-log.md` | 模板新建 | C4.4 |
| v3-32 | `config/doc-update.yml` | 加 `rewrite_break_even_threshold` | V14 |
| v3-33 | `scripts/quickfix-structural-words.txt` | 新建（V12 红色信号词表） | V12 |
| v3-34 | `INVARIANTS.md` | 大量新增/修订（见 §14.9） | 全 |
| v3-35 | `tests/fixtures/d13-v3/` | 11 case 端到端 fixture | V15 |
| v3-36 | `tests/run-d13-v3.sh` | 总入口 | V15 |

### 14.9 INVARIANTS 影响汇总（替代 §12.5）

| INVARIANT | 状态 | 内容 |
|---|---|---|
| I-CT2 | 修订 | 不变（v1 §12.5 描述错误已修正） |
| I-CT9 | 新增 | close-task step 0.5 必须先于 task PM 视图 commit |
| I-TT1 | 不变 | （现有 task worktree invariant） |
| I-TT2 | 新增 | task worktree `docs/modules/` 不允许被修改（snapshot 隔离） |
| I-CR10 | v3 修订 | close-req step 0 入口 dirty gate（替代 v2 描述） |
| I-CR11 | v3 修订 | close-req step 2 rewrite 必须在 temp worktree，失败 force 清理 |
| I-CR12 | v3 修订 | stale checkpoint 三层验证（req + HEAD 可达 + stage） |
| I-CR13 | 新增 | rewrite mode 输入按 git topo order，不允许 wall clock |
| I-CR14 | 新增 | rewrite 必须在 temp worktree |
| I-CR15 | 新增 | close-req step 1 后任何步骤失败保留 active/、stage 不进 closed/ |
| I-CR16 | 新增 | part-commit 必须配套 audit 文件 |
| I-CR17 | 新增 | close-req step 0.5 必须先于 step 1（写 close-report 之前） |
| I-CR18 | 新增 | close-req step 1.5 必须先拿 `refs/locks/close-req-active` |
| I-FT1 | 新增 | feature_id 不可变（一旦写入 modulespec 不允许再生） |
| I-TS1 | 新增 | dispatch 的 task 必须 module_impact 存在且无 unknown confidence |
| I-QF1 | 新增 | close-req 入口老 quickfix > 5 → 必须先走 /quickfix-backfill |
| I-QF2 | 新增 | quickfix-summary.md 是 derived，PM 修改无效（rebuild from jsonl） |

### 14.10 实施前 pre-flight（替代 §12.8）

D13 v3 动手前必须先做（含 v2 §12.8 残留）：

- [ ] **跑 round 4 autoplan**：覆盖 §十四 全套（重点验 V3 公式完备性 + step 0.5 三分类边界 + C4.2 snapshot lock 边角 case + 多 worktree 锁的 race）；通过才进 Phase C 实施
- [ ] **V14 token break-even 实测**：跑 §14.5.1 测量 phase（adminconsole4 一个真实 req，settlement vs rewrite 双跑），确定 `rewrite_break_even_threshold` 配置默认值
- [ ] **V15 fixture skeleton 先建**：11 个 fixture 目录骨架 + 至少 case-01 / case-07 / case-10 三条 happy path 跑通；其余 fixture 在 Phase C 实施时逐步补
- [ ] **grep 测试套件**（v2 §12.8 残留）：`grep -rn "settlement|对账|SKIP_DOC_UPDATE|cleanup_status|half-close|skip-doc-update" tests/ scripts/tests/` 估算改动量；v3 加 grep 新词：`needs-modulespec-update|module_impact|feature_id`
- [ ] **C2 V6 isolation 模拟**：手动跑一次 close-req 走到 rewrite 中断（kill -9）→ 验证 temp worktree 清理路径不留残
- [ ] **C4.2 snapshot 占空间评估**：adminconsole4 现有 modulespec 总文本量；如果 >5MB 一份则 reconsider symlink + freeze ref 策略

### 14.11 v3 完成后

1. 跑 **round 4 autoplan** 验 v3（焦点：V3 公式覆盖度 + V6 temp worktree 残留 + step 0.5 三分类边界 + C4.2 snapshot 一致性 + 多 worktree 锁 race）
2. 通过后进 Phase C 实施（按改动清单 v3-01 → v3-36 顺序，分 PR）
3. round 4 仍有 critical → v4 设计循环

---

## 十五、Round 4 autoplan 评审结论（2026-05-12）

> **范围**：评 §十四 D13 v3 设计稿。
> **方法**：Codex 对抗视角 + Claude subagent 独立战略视角并行评审（CEO 阶段）。
> **关键发现**：两个独立 voice 高度一致 — 7/7 critical/high dimensions confirmed。v3 严重偏离 §12.1 token 痛点。

### 15.1 CEO 共识表（7/7 confirmed，0 disagreements）

| # | 维度 | Claude 视角 | Codex 视角 | 共识 |
|---|---|---|---|---|
| 1 | 是否锚定 §12.1 token 痛点？ | NO（F1：17 主任务里只 V14 直接服务痛点） | NO（#1：从"减 N 次 token"漂成"建 modulespec 事务系统"） | **CONFIRMED — v3 drifted, must re-anchor** |
| 2 | scope 标定合理？ | NO（F7：18-29h 工程税 / ~$15 年节省） | NO（#2：30 分钟/req 节省要 36-58 req 才回本，还可能被 quickfix 填表吃回去） | **CONFIRMED — over-engineered for single PM** |
| 3 | 替代方案充分探索？ | NO（F9：settlement+batch 未回看，能拿 80% 节省 / 20% 复杂度） | NO（#3：必须给 batch-settlement 一节） | **CONFIRMED — dismissed by inertia** |
| 4 | §14.6 quickfix 实时写 modulespec 矛盾 §12.1？ | YES 矛盾（F11：每次 quickfix=1 次 modulespec 写入，N=0 task 5 quickfix 比 D13 砍之前更多写） | YES 矛盾（#4：N 次 doc-update → 1 次 close-req rewrite 的目标被 quickfix 后门吃掉） | **CONFIRMED — internal contradiction** |
| 5 | §14.7 V16/V17 step 0.5 + 锁对单 PM 合适？ | NO（F12：纯过度工程，1 年触发 <5 次） | NO（#5：把低频竞态产品化，§14.7.5 自己承认罕见还加锁脚本） | **CONFIRMED — cut V17, simplify V16** |
| 6 | V10 feature_id hash 注入 modulespec 文本？ | NO（F13：modulespec 每 feature 顶 4 行机器元数据） | NO（#6+#7：sidecar 替代；hash 不稳跟 immutable 自相矛盾） | **CONFIRMED — move to sidecar** |
| 7 | V3 merge 函数 5 类 CONFLICT 门？ | NO（F3：典型 AI 过度形式化，砍到 1 类） | NO（#8+#9：把正常修改误判冲突；砍到 2 类） | **CONFIRMED — over-formalized** |

### 15.2 详细 finding 全表

**Claude subagent（13 findings）**：

| # | 严重度 | 章节 | 一句话 |
|---|---|---|---|
| F1 | critical | §14.0 | 17 主任务里仅 V14 直接服务 §12.1 痛点；其他 16 个解 v3 自己引入的子问题 |
| F2 | high | §14.0 | 4 条隐含 premise 全脆弱（N≥5/req / 多 worktree 常发生 / rename 真问题 / PM 读 hash） |
| F3 | critical | §14.2.1 | V3 merge 5 类 CONFLICT 门是 AI 过度形式化；PM 不读公式，要的是 10 分钟审完 rewrite |
| F4 | high | §14.4.1 | V10 feature_id hash + canonical normalize 中文标点折叠歧义会偶发漂移 |
| F5 | high | §14.7 | V16/V17 + git ref 锁对单 PM 是基础设施级 over-engineering |
| F6 | medium | §14.3.3 | V8 part-commit 三选门 99% 时间 PM 是 accept all，多 audit 模板纯表演 |
| F7 | critical | §14.8 | 17 任务 / 36 改动 / 17 invariant / 18-29h 工时 vs 单 PM 一年 ~$15 token 节省 |
| F8 | high | §14.10 | pre-flight 顺序倒置：先工程层验证再产品层验证 → 应反过来 |
| F9 | high | §十二/§十四 | settlement+batch 替代方案被 §十二 v2 一笔带过 v3 完全没回看 |
| F10 | critical | §13.7→§13.10→§14.6 | quickfix 重定位仓促反转，PM 原话只表达行为期望，AI 拆成 4 点意图盖整章 |
| F11 | critical | §14.6 | quickfix 实时写 modulespec 与 §12.1 直接矛盾（quickfix N 次 = 后门吃 D13 收益） |
| F12 | critical | §14.7 | step 0.5 + git ref 锁对单 PM 是 over-engineering |
| F13 | high | §14.4.1+§14.6.4 | feature_id / origin_req / last_modified HTML 注释让 modulespec 每 feature 顶 4 行机器元数据 |

**Codex（10 findings）**：

| # | 严重度 | 章节 | 一句话 |
|---|---|---|---|
| 1 | critical | §14.0/§14.8 | v3 漂移成事务系统；V14 应变硬闸门，未实测前不允许实施 V1-V17 |
| 2 | critical | §14.8/§14.9 | 18-29h 对单 PM 不成比例；每 req 净省 30 分钟也要 36-58 req 回本 |
| 3 | high | §14.5.1 | V14 提了 break-even 但未评估 settlement+batch 替代（可拿 80% 节省 / 20% 复杂度） |
| 4 | critical | §14.6 | quickfix 实时写 modulespec 正面冲突 §12.1；要么改名（不再叫 rewrite-only）要么默认 decision log |
| 5 | high | §14.7/§14.7.5 | step 0.5+git ref lock 把低频竞态产品化；改成 close-req 时检测 main 前进+fail+让 PM 重试 |
| 6 | high | §14.4.1/§14.6.4 | feature_id/origin_req hash 注释污染 modulespec 文本；改 sidecar `.index.json` |
| 7 | medium | §14.4.1 | hash 算法跟 "feature_id 不可变" 自相矛盾；用生成式 ID 不要假装 anchor hash 稳定 |
| 8 | critical | §14.2.1/§14.7.2 | V3 merge 把正常修改误判冲突；应是三方字段 patch（expected_old/new/current） |
| 9 | high | §14.2/§14.7 | 5 类 CONFLICT_* gate 形式化过度；收敛到 2 类（破坏性需 PM / 字段补充自动合并） |
| 10 | medium | §14.6.1/§14.6.5 | quickfix schema 把轻量修正变成小型 PRD；保留 summary/module/needs_update 三字段 |

### 15.3 verdict（两 voice 一致）

**v3 不可全量 ship，必须 scope reduction 到 MVP。**

候选 v3' MVP（两 voice 各自提的，高度重合）：

| 任务 | 保留？ | 简化方向 |
|---|---|---|
| V1（task→module 脚本） | ✅ | 简化版（merge 输入必要） |
| V2（topo order） | ✅ | 简化（一行约定，不要单独脚本） |
| V3（merge 函数） | ✅ 大砍 | 5 类 CONFLICT → 1-2 类；砍 worked example A-E |
| V4（module rename） | ❌ | 缓 v4 |
| V5（module_impact 强 lint） | ✅ 降级 | warn 不阻断 dispatch |
| V6（temp worktree 隔离） | ✅ | 保留（C2 critical 修复） |
| V7（mutation 边界） | ✅ | 保留（dirty gate + checkpoint） |
| V8（part-commit） | ❌ | 砍，reject any module → 整体 abort |
| V9（stale checkpoint） | ✅ 降级 | 二层验证（HEAD 可达 + req 一致），砍 mismatched-stage |
| V10（feature_id hash） | ✅ 改 sidecar | `.feature-index.json`，不进 modulespec 正文 |
| V11（schema 12 字段） | ✅ 大砍 | 砍到 4 字段（module/feature_anchor/change_type/needs_modulespec_update） |
| V12（V12 二次验证） | ❌ | 砍（红色信号词噪声多于信号） |
| V13（downgrade + /quickfix-backfill） | ✅ 降级 | 一次性脚本，不必新 skill |
| V14（token break-even） | ✅✅ 核心 | 升硬闸门：未实测前不允许实施 |
| V15（11 fixture） | ✅ 大砍 | 砍到 3 fixture（success/fail-retry/no-residue） |
| V16（多 req 并行） | ✅ 大砍 | 单行 fetch+提示替代 step 0.5 三分类 |
| V17（同 req 跨 task） | ❌ | 砍 |
| C4.1（schema 扩展） | ✅ 大砍 | 砍到 4 字段（见 V11） |
| C4.2（snapshot lock） | ❌ | 砍（quickfix 不实时写 modulespec） |
| C4.3（applied/unapplied） | ❌ | 砍（C4.2 砍了自然消失） |
| C4.4（origin_req 归因） | ✅ 改 sidecar | 同 V10 |
| C4.5（quickfix-summary.md） | ❌ | 砍（jsonl 已够） |

**v3' = ~9 任务 / 估 ~10 工时**（vs v3 17 任务 / 18-29 工时）。

### 15.4 Decision Audit Trail（CEO Phase 部分）

| # | Phase | Decision | Classification | Principle | Rationale |
|---|---|---|---|---|---|
| 1 | CEO P0.5 | 跑 Claude subagent + Codex 双 voice（独立审 plan file） | Mechanical | P6 | 标准 dual voice |
| 2 | CEO 整轮 | 不静默 auto-decide，全部 critical findings surface 给 PM | User Challenge | — | 两 voice 一致挑战 PM §13.10/§13.11 拍板的方向（quickfix 实时写 / V17 close-task step 0.5）→ surface |
| 3 | CEO 整轮 | 暂停其余 phase 直 PM 处理 premise gate | Mechanical | — | 当 v3 整体 anchor 被两 voice 一致挑战，继续跑 Eng/DX phase 等于评一个不该实施的设计 |
| 4 | CEO premise gate | **D1 痛点重定位：(b)+(c) 时延+注意力**（不是 token 经济） | **User Decision** | — | PM 2026-05-12 拍板：§12.1"token 浪费"的字面表述被 AI 帮助修辞过；真痛是每次 close-task 等 doc-update 跑完+审 diff 拖沓 +连续 task 节奏被打断 |
| 5 | CEO premise gate | **D2 v3 方向：v3' MVP 9 任务 / ±10h** | **User Decision** | — | PM 2026-05-12 拍板：按 §15.3 表 scope reduction；v4 设计稿写完后跑 round 5 autoplan 验 |

### 15.5 D1 痛点重定位的 downstream 影响

D1 把 §12.1 anchor 从 "token 经济" 改成 "时延 + 注意力切换"。**影响 v3' MVP 设计**：

| 任务 | v3 原假设 | D1 后调整 |
|---|---|---|
| V14（break-even） | token 经济计算 | 改"PM 注意力 break-even"——单次集中审 rewrite vs N 次零散审 settlement 的认知负担；token 数字降为次要参考 |
| V3（merge 函数） | 公式确定性给 token 节省正当性 | 改"PM 审 rewrite diff 时心理负担"——同字段冲突门必须降到最少（PM 一次集中审，门多 = 心理负担大） |
| V11（schema） | 字段全为了 AI 准确消费 | 改"PM 填 quickfix metadata 的注意力税"——字段必须最小，每多一个就是 PM 一次 quickfix 多一道填表 |
| V6/V7（隔离边界） | 工程鲁棒性 | 不变（D13 主流程仍是 close-task 不写 modulespec、close-req 一次性） |
| 整体路线 | rewrite-only | rewrite-only 仍合理（一次集中处理 vs 多次零散打断）；batch-settlement 替代方案不再优于 rewrite 因为 batch 仍是"零散多 diff"的 PM 视角 |

**关键洞察**：D1 让 "rewrite vs settlement" 的取舍逆转——
- 之前（按 token 痛点）：rewrite 比 settlement 节省，但 break-even 要 N≥2，N=1 反而贵
- 现在（按时延+注意力痛点）：rewrite 不论 N 都更优（PM 工作流体感"一次集中"vs"N 次打断"）；token 数字成本可承受

→ **D13 rewrite-only 方向其实更合新痛点定位**。v3 走偏在"5 类 CONFLICT 门 + 实时写 modulespec + multi-worktree 全套"这种自我引入的副复杂度，不在 D13 大方向。

---

## 十六、D13 v3' MVP 设计（2026-05-12 PM 拍板）

> **状态**：基于 D1+D2 拍板 + §15.3 表。9 任务 / ±10h 估。本节只写 outline + 关键决策；v4 设计稿按本 outline 展开。
> **替换关系**：§十四 v3 全集作废（仅作历史归档保留），实施按本节 + 后续展开稿。
> **下一步**：PM 拍 outline 后展开各任务 → 跑 round 5 autoplan 验 → Phase C 实施。

### 16.1 v3' MVP 9 任务清单

**Foundation（保留 §14.1）**

| 任务 | 描述 | 调整 |
|---|---|---|
| **W1**（旧 V1） | task→module 映射脚本 | 简化版：直接读 task md frontmatter `module_impact`，不交叉验证 diff |
| **W2**（旧 V2 简化） | 全局时间序定义 | **一行约定**（"按 git topo order 应用 patch"）；不要单独脚本 `req-event-order.py`，需要时 W1 内部 `git log --topo-order` |

**C1 核心 — merge 函数（大砍版）**

| 任务 | 描述 | 调整 |
|---|---|---|
| **W3**（旧 V3 大砍） | merge 函数 + 1 类 CONFLICT 门 | 砍 5 类→ 1 类：`CONFLICT_REFERENCE_MISSING`（"PM 视图说改 X，但 base 里没 X"），统一询问门：(a) 改成新建 (b) 选其他 feature (c) skip。砍 `case behavior-only`（用 modify 覆盖）+ `case null`（过滤逻辑非 merge case）。砍 worked example A-E 共 100 行（AI 自我说服式写作）。merge_payload 改成三方字段 patch：`expected_old/new/current`，只有 current 已被改成第三值才真冲突 |

**C2 — 隔离 worktree + 边界（保留核心）**

| 任务 | 描述 | 调整 |
|---|---|---|
| **W4**（旧 V6） | 隔离 temp worktree/branch 内 rewrite | 不变（CR-2 critical 修复，工程必要） |
| **W5**（旧 V7） | close-req mutation 边界 | 保留：dirty gate + checkpoint 在 step 1.5；砍 part-commit（V8 砍） |
| **W6**（旧 V9 降级） | stale checkpoint 检测 | 二层验证（HEAD 可达 + req 一致），砍 mismatched-stage（罕见且让 PM 介入比静默清理累） |

**C3 — schema 完整化（最小集）**

| 任务 | 描述 | 调整 |
|---|---|---|
| **W7**（旧 V11+C4.1 大砍） | quickfix-log schema 最小集 | 砍 12 字段到 **4 字段**：`module / feature_anchor / change_type / needs_modulespec_update`。砍 feature_id（W8 走 sidecar）/ target_origin_req / recorded_in_req / modulespec_patch / supersedes / applied / affected_paths / confirmed_by/at（PM 单人审计无价值）。注意 V13 老 quickfix downgrade 也大砍——quickfix-backfill 改成一次性脚本不必新 skill |
| **W8**（旧 V10+C4.4 改 sidecar） | feature_id + origin_req sidecar | 不进 modulespec 正文。`docs/modules/.feature-index.json` 存（feature_anchor → feature_id + origin_req + last_modified_at）。AI rewrite 时读 sidecar 对齐；PM 看 modulespec git diff 是干净的产品语言。砍 modulespec H3 下 4 行 HTML 注释 |

**横切**

| 任务 | 描述 | 调整 |
|---|---|---|
| **W9**（旧 V15 大砍 + 多 worktree 单行替代） | 测试 fixture + 多 req 警告 | fixture 砍 11 → 3（success / fail-retry / no-residue end-to-end）。多 worktree 整套（V16/V17/git ref 锁/step 0.5 三分类/AI 助理合并）砍成 **一行 close-req 入口检测**：`git fetch origin && git diff <req-base>..origin/main -- docs/modules/` 非空 → 提示 PM "main 上 modulespec 有改动，要先 pull 还是继续 close？"；PM 决策即可，无锁、无三分类、无 audit。close-task 不做（V17 砍） |

**总计**：9 任务（W1-W9）。估 ~10-12h 工程实施 + ~5h v4 设计稿展开 + round 5 autoplan ~3h = ~18-20h。

### 16.2 砍掉的 v3 任务（vs §14.0）

| 砍 | 理由 |
|---|---|
| V4（module rename） | §14.2.3 自承认低频；进 v4 候选 |
| V5（dispatch gate 阻断） | 降级 warn 不阻断（W7 已含 lint 但只 warn） |
| V8（part-commit 三选门） | 99% PM accept all；reject 一个 → 整体 abort 简单 |
| V12（红色信号词二次验证） | 噪声多于信号；PM 在 rewrite diff 自审够了 |
| V17（close-task step 0.5） | 单 PM 同 req 跨 worktree 罕见；rare race 不该建基础设施 |
| C4.2（snapshot lock） | quickfix 不实时写 modulespec，无 snapshot 需要 |
| C4.3（applied/unapplied drift） | C4.2 砍后自然消失 |
| C4.5（quickfix-summary.md） | jsonl 已够；PM 想看 `cat quickfix-log.jsonl \| jq` 即可 |
| §14.7.5（git ref 锁） | 单 PM 不需基础设施级锁 |

### 16.3 quickfix 行为变化（vs §14.6 / §13.10）

**§13.10 PM 原话回看**：

> "我 quickfix 修改的时候，实际上就是想要修改原型，同时修改 modulespec，甚至我修改的还可能是之前某个 req 的产物，我需要你帮我同时在 req 中记录。"

**v3 AI 解读**：拆 4 点意图 → 整章 C4.1-C4.5（实时写 + snapshot + drift + 归因 + summary）。

**v3' 重解读**（两 voice 一致建议）：PM 表达的是**期望**（quickfix 别让 modulespec 永远落后），不是**机制要求**（每次实时写）。最简落地：

| PM 期望 | v3 机制 | v3' 机制 |
|---|---|---|
| "quickfix 别让 modulespec 落后" | quickfix 实时写 modulespec | quickfix 写结构化 metadata（W7 4 字段）→ close-req rewrite 时统一消费，与 task PM 视图同等地位 |
| "可能改的是之前某个 req 的产物" | C4.4 origin_req HTML 注释 + target_origin_req 字段 | W8 sidecar 存归因；W7 metadata 可选 free-text "改的是哪 feature"（PM 视图友好） |
| "我需要你帮我同时在 req 中记录" | C4.5 quickfix-summary.md derived view | jsonl 本身就在 `requirements/active/<req>/`；PM 想看就 grep |

**净效果**：v3' 仍满足 PM §13.10 意图（quickfix 不让 modulespec 落后），但不引入 quickfix→modulespec 直写带来的所有 snapshot / drift / applied 区分子问题。

### 16.4 INVARIANT 收敛（vs §14.9 17 条）

砍到 **8 条**：

| INVARIANT | 内容 | v3 来源 |
|---|---|---|
| I-CR10 | close-req step 0 dirty gate | 保留 |
| I-CR11 | rewrite 必须在 temp worktree（W4） | 保留 |
| I-CR12 | stale checkpoint 二层验证（HEAD + req） | 降级（去掉 mismatched-stage） |
| I-CR13 | rewrite 输入按 git topo order | 保留 |
| I-CR15 | close-req step 1 后任何失败保留 active/、stage 不进 closed/ | 保留 |
| I-CR16 | close-req 入口 main diff 非空 → 提示 PM（替代 V16/V17 全套） | 新简化 |
| I-CT2 | task worktree clean / 分支存在（原有，v1 描述错误已修） | 不变 |
| I-QF1 | 老 quickfix 数量超阈值 → 走一次性 backfill 脚本 | 降级（不必新 skill） |

砍掉：I-CR14（V6 已含）、I-CR17（V16 step 0.5 砍）、I-CR18（git ref 锁砍）、I-CT9（V17 砍）、I-TT2（C4.2 snapshot 砍）、I-FT1（feature_id 改 sidecar）、I-TS1（V5 降级 warn）、I-QF2（C4.5 砍）、I-CR16-old（part-commit 砍）。

### 16.5 改动清单收敛（vs §14.8 36 项）

收到 **~15 项**：

| 类别 | 项目 |
|---|---|
| 脚本（新建） | W1（req-module-impact.py 简化版）、W4（隔离 temp worktree 脚本）、W7（quickfix-log schema lint） |
| skill（改） | doc-update §8 rewrite mode + W3 1 类 CONFLICT、quick-fix skill 加 4 字段 metadata + 调 doc-update settlement（不是直写 modulespec）、close-req 加 dirty gate + checkpoint + main diff 提示、close-task 维持现 D13 主流程不写 modulespec |
| skill（砍） | task-execute snapshot 读改回常规 git checkout、req-stage-gate half-close 检测砍 |
| 模板 | quickfix-log v3' minimal schema、feature-index.json sidecar |
| 测试 | 3 个核心 fixture（success / fail-retry / no-residue） |
| INVARIANT | INVARIANTS.md 加 I-CR10-16 + I-QF1（按 §16.4） |

### 16.6 pre-flight 重排（vs §14.10）

**产品层 pre-flight 先**（F8 修复）：

1. [ ] **N 分布统计**：adminconsole4 历史 10 个 req 平均 task 数 / quickfix 数。若 N=1 占 >50% → 触发 D13 整体 reconsider（rewrite-only 假设 N≥2 才合理；但 D1 时延+注意力痛点下 N=1 也仍有 close-task 不打断意义）
2. [ ] **PM 注意力 break-even（替代 token break-even）**：对一个真实 req 主观计时——D13 模式（task close 静默，close-req 一次集中审）vs 旧 settlement 模式（每 task close 都审 diff），PM 主观工作流体感打分。决定 W3/W4/W5 是否值得做
3. [ ] **PM 痛点二次确认**：跑一次后端到端再问 PM "(b)+(c) 还是真痛点吗，还是用了几次发现痛在别处"
4. [ ] **§13.10 quickfix 期望确认**：跑一两个 quickfix 走 v3' "metadata 不实时写 modulespec" 路径，PM 主观体感 OK 吗

**工程层 pre-flight 后**（继续 §14.10 部分）：

5. [ ] **grep 测试套件**：见 §14.10
6. [ ] **W4 isolation 模拟**：rewrite 中断 → temp worktree 清理验证
7. [ ] **W7 schema lint 测试**：4 字段必填 / null 字段拒绝

### 16.7 v3' 完成后

1. PM 拍 §十六 outline 后，按 W1-W9 展开详设计稿（每任务一节，类似 §十四 但密度减半）
2. 跑 **round 5 autoplan** 验 v3'（focal：D1 痛点是否真锚定 / W3 1 类 CONFLICT 是否够 / W7 4 字段 schema 是否够 / I-CR16 单行替代是否足）
3. round 5 通过 → 进 Phase C 实施（按 §16.5 改动清单分 PR）
4. round 5 仍 critical → v4 设计循环

---

## 十七、D13 v3' MVP 详设计稿（2026-05-12）

> **版本**：v3' MVP 详稿（基于 §十六 outline 展开）。
> **关系**：§十四 v3 全集作废仅作归档；本节是要 ship 的设计。
> **写作密度**：比 §十四 减半——每任务=问题+设计+关键决策+实施清单；不写 worked example（PM 不读，AI 实现时按 §十四 v3 已有的算法但裁简）。
> **状态**：待 PM 拍 + round 5 autoplan 验。

### 17.0 v3' 总图 + D1 痛点显式回锚

**§12.1 痛点重述（D1 拍板后）**：

> **真痛**：每次 close-task 等 doc-update 跑完 + PM 审 diff 拖沓；连续 task 节奏被打断；PM 注意力切换成本高。token 数字只是症状，不是病因。

**v3' 设计原则**（D1 downstream）：

1. **rewrite-only 仍正确**：close-task 不写 modulespec = 让 PM 在 close-task 不被 doc-update 打断；close-req 一次集中审 = 把"审 diff"的注意力税合并到一处
2. **rewrite diff 审 PM 心理负担最小化**：merge 函数冲突门必须最少（W3 砍 5 类 → 1 类）；schema 字段必须最少（W7 砍 12 → 4）；modulespec 视觉不被机器元数据污染（W8 sidecar）
3. **不为低频 case 建基础设施**：multi-worktree race / module rename / part-commit / quickfix realtime 都进 v4 候选不进 v3'
4. **工程鲁棒性边界仅保留 critical**：W4 隔离 worktree（CR-2 修复）+ W5 边界锁死 + W6 stale 检测——这些是 close-req 失败不留半状态的工程地板，不可妥协

**9 任务对 D1 痛点贡献矩阵**：

| 任务 | 对 (b)+(c) 时延+注意力痛点贡献 | 对 D13 工程地板贡献 |
|---|---|---|
| W1 task→module 脚本 | 中（rewrite 输入构造前提） | 中 |
| W2 topo order 约定 | 低（确定性顺序） | 高 |
| W3 merge 函数 + 1 类 CONFLICT | **高**（决定 PM 审 rewrite diff 体验） | 高 |
| W4 隔离 temp worktree | 低 | **高**（close-req 失败安全） |
| W5 close-req 边界 | 低 | **高**（mutation 顺序锁死） |
| W6 stale checkpoint 二层 | 低 | 中 |
| W7 quickfix schema 4 字段 | **高**（每次 quickfix PM 填表注意力税） | 中 |
| W8 sidecar feature_id | **高**（modulespec 视觉纯净） | 低 |
| W9 fixture + 多 worktree 单行 | 低 | 中（fixture）/ 高（单行替代 V16/V17） |

**总投入**：~10-12h 工程 + ~5h v3' 详设计 review + round 5 autoplan ~3h = ~18-20h（vs v3 估 40-60h）。

**总收益**（PM 主观估）：每 req close 体感从"零散 N 次小审 + 时延等"变"一次集中审 + 期间静默"；按一年 50 req 估，PM 每次省 5-15 分钟注意力 → 一年省 4-12 小时 PM 工时 + 不可量化的"连续 task 节奏"工作流体感升级。

### 17.1 Foundation — W1 + W2

#### 17.1.1 W1 — task→module 映射脚本（简化版）

**接口**：

```bash
scripts/req-module-impact.py <req-id> [--include-quickfix] [--format json|md]
```

**输入**：
- `<req-id>`：active 或 closed
- `--include-quickfix`：是否合并 quickfix metadata（默认 false，rewrite mode 调用时 true）

**输出**（JSON）：

```json
{
  "req": "R-2026-001",
  "tasks": [
    {"task": "T1", "modules": ["module-log", "module-filter"]}
  ],
  "quickfixes": [
    {"commit": "<sha>", "modules": ["module-log"]}
  ],
  "modules_touched": {
    "module-log": {"tasks": ["T1"], "quickfixes": ["<sha>"]},
    "module-filter": {"tasks": ["T1"], "quickfixes": []}
  }
}
```

**数据源**（顺序不可变）：
1. task：`requirements/.../tasks/T*.md` 的 frontmatter `module_impact:` 字段
2. quickfix：`requirements/active/<req>/quickfix-log.jsonl` 的 `module` 字段
3. **不跑 diff 反推**：信号噪声大；缺字段就脚本退非零 + 报告缺哪个 task/quickfix（PM 补完再跑）

**vs §14.1.1 V1 砍掉什么**：

- 砍 `--since <commit>` 参数（rewrite 总是从 req base 起，不需要切片）
- 砍 `source: "task-spec module_impact field"` 这种 source 字段（PM 不读）
- 砍 alias 解析（W8 sidecar 走，本脚本只输出 raw module 名）

**实施清单**：
1. `scripts/req-module-impact.py` 新建（≤80 行 Python）
2. `tests/scripts/test-req-module-impact.py` 覆盖：正常 / 缺 module_impact / 多 module / 含 quickfix
3. W3/W5/W9 在内部 import 用

#### 17.1.2 W2 — 全局时间序约定

**约定（一行）**：

> rewrite mode 输入合并按 `git log --topo-order req-branch` 顺序应用；wall clock / `committer time` 不参与。

**实操**：在 W1 输出基础上，rewrite mode 通过 `git log --topo-order --pretty=format:"%H %s"` 列 req 分支 commits，按拓扑顺序匹配 `[task-close]` / `[quick-fix]` commits，组装 patch 序列。

**vs §14.1.2 V2 砍掉什么**：

- 砍 `scripts/req-event-order.py` 单独脚本（W1 内部用 git log 直接拿，不必新脚本）
- 砍"并行 commit 不可比 → 进 V16/V17 step 0.5" 跨 reference（v3' 不做 step 0.5，已 merge 进 req 分支后顺序就唯一确定）

**实施清单**：
1. `skills/doc-update/SKILL.md` §8 加一句话约定
2. `INVARIANTS.md` I-CR13：rewrite 输入合并按 `git log --topo-order` 顺序
3. W1 脚本输出列表本来就按 topo order

### 17.2 W3 — merge 函数（大砍版 + 1 类 CONFLICT）

#### 17.2.1 公式

> **merge** `M(base, [patch_1, patch_2, ...]) → new_modulespec`

```
M(base, patches):
  state = base_features  # dict: feature_anchor → feature payload

  for patch in patches (already topo-ordered, W2):
    for (op, anchor, payload) in patch.entries:
      apply(state, op, anchor, payload)

  return assemble(state)  # render back to modulespec markdown
```

**`apply(state, op, anchor, payload)`** —— 操作只剩 3 类：

```
match op:
  case add:
    if anchor in state:
      → "你想新加 X 但 X 已存在" 进统一询问门
    else:
      state[anchor] = payload

  case modify:
    if anchor not in state:
      → CONFLICT_REFERENCE_MISSING 进统一询问门
    else:
      state[anchor] = three_way_merge(state[anchor], payload)

  case remove:
    if anchor not in state:
      → CONFLICT_REFERENCE_MISSING 进统一询问门
    else:
      del state[anchor]
```

**砍掉的 v3 op**：
- `behavior-only` → 改用 `modify` + `payload` 只填 `behavior` 字段
- `null` → 不是 op，是过滤逻辑（quickfix `module=null` 不进 patches list）

#### 17.2.2 三方字段 patch — `three_way_merge`

**关键改进**（vs §14.2 V3）：避免"任何字段值变化都触发冲突"误报。

每个 patch entry 字段写法：

```json
{
  "anchor": "列表筛选",
  "op": "modify",
  "payload": {
    "fields": {
      "sort_default": {
        "expected_old": "时间倒序",
        "new": "时间正序"
      },
      "behavior": {
        "expected_old": null,           // patch 来源没填这个字段
        "new": null
      }
    }
  }
}
```

**`three_way_merge(state_value, patch_value)`** —— 字段级：

```
three_way_merge(current, patch):
  result = current.copy()
  for field, change in patch.fields:
    if change.new is None:
      continue                          # patch 没填这个字段，不动
    if current[field] == change.expected_old:
      result[field] = change.new        # 正常修改
    elif current[field] == change.new:
      continue                          # 已经是新值（前一个 patch 改过），idempotent
    else:
      → CONFLICT_REFERENCE_MISSING（field-level）
        "本 patch 期望 {field} 是 {expected_old}，但实际是 {current}，进询问门"
  return result
```

**核心语义**：
- 正常修改（`current == expected_old`）→ 静默应用，不打扰 PM
- 重复应用同一个 patch（`current == new`）→ idempotent，跳过
- 第三种值（`current` 既非 `expected_old` 也非 `new`）→ 真冲突，进门

vs v3 §14.2.1 `merge_payload`："old 非 null 且 new 不同就触发 CONFLICT" 把"PM 视图说改排序倒→正"这种正常 modify 误报成冲突。v3' 用 `expected_old` 把"PM 视图描述的 base 状态" + "本 patch 的新值"双轨表达，让 merge 函数知道"什么是正常 modify"。

**`expected_old` 从哪来**？task-spec / quick-fix 生成 patch 时 AI 注入：读当前 modulespec → 把要改字段的当前值填进 `expected_old`，PM 视图描述新值填 `new`。PM 不需要填 `expected_old`（AI 自动读 base）。

#### 17.2.3 唯一询问门：`CONFLICT_REFERENCE_MISSING`

**触发**：
- `modify` / `remove` 时 anchor 不在 state（feature 找不到）
- `add` 时 anchor 已在 state（feature 已存在还想加）
- `three_way_merge` 时字段值是第三种（不是 expected_old 也不是 new）

**统一询问门**（PM 看到的是 3 个选项，不是 5 种 CONFLICT 类型表）：

```
检测到 patch 跟当前 modulespec 对不上：
  feature anchor "列表筛选"，字段 sort_default
  本 patch 期望旧值：时间倒序
  当前 base 值：时间随机（被别的 req 改过）
  本 patch 新值：时间正序

PM 选：
  (a) 用 patch 新值（覆盖 base 当前）
  (b) 保留 base 当前（skip 本 patch entry）
  (c) PM 调（自己写一个第三方）
```

**不再有的**（v3 §14.2.1 砍掉）：
- CONFLICT_ADD_EXISTING / CONFLICT_MODIFY_MISSING / CONFLICT_REMOVE_MISSING / CONFLICT_BEHAVIOR_MISSING / CONFLICT_FIELD_CHANGE 五类 → 全部归 `CONFLICT_REFERENCE_MISSING`
- 每类 3-4 个选项 → 统一 3 选项 (a/b/c)
- v3 worked examples A-E（100 行）→ v3' 不写 worked example

#### 17.2.4 关键决策

- **不要 feature_id 入门检测**：W8 sidecar 持 feature_id，但 W3 merge 函数操作单元是 `anchor`（H3 标题文本）。W8 sidecar 用于 anchor 改名时把"列表筛选" → "列表过滤" 映射到同一个 feature_id，避免误报 add/remove 一对组合。本节 merge 函数 PM 视角只看 anchor。
- **idempotent 是核心**：W7 quickfix metadata 不立即写 modulespec（§16.3），但 rewrite 重跑（PM 决策修后 retry）时同一个 patch 不能产生不同结果——`current == new` 路径保证 idempotent。
- **询问门 PM 决策不写回 metadata**：PM 在 close-req rewrite 时选 (a)/(b)/(c)，决策应用进当次 rewrite 输出，不改 task PM 视图 / quickfix-log。下次 close-req（不会有，本 req 已 close）或后续 req 同样路径会再走，但因为本 req 已 close 后 modulespec 状态变了，下次 patch 不会撞同冲突。

#### 17.2.5 实施清单

1. `scripts/merge-modulespec.py` 新建 — `M(base_path, patches_json) → new_modulespec_text`
2. `skills/doc-update/SKILL.md` §8 改：调 W3 merge；遇 `CONFLICT_REFERENCE_MISSING` 暂停，PM 答题，决策应用
3. `skills/task-spec/SKILL.md` 加："PM 视图生成 patch 时 AI 自动读 base 当前值填 `expected_old`"
4. `skills/quick-fix/SKILL.md` 同上（quickfix metadata 含 patch 时 AI 读 base）
5. `tests/merge/test-three-way.py` 覆盖：normal modify / idempotent / 真冲突 (三种值) / add-existing / modify-missing / remove-missing

### 17.3 W4 + W5 + W6 — 隔离 worktree + close-req 边界

#### 17.3.1 W4 — 隔离 temp worktree/branch 内 rewrite

**问题**（继 §14.3.1 V6）：rewrite 写 modulespec 文件 + 可能产生 untracked / event log 半写。`git reset --hard` 救不全。

**设计**（不变 §14.3.1）：rewrite 全程在隔离 temp worktree + temp branch，成功 → ff merge 回 req worktree；失败 → `git worktree remove --force` 一刀切。

**精确流程**：

```bash
# close-req step 2（rewrite 包裹）：

# 1. 创建 temp
TMP="$REPO_ROOT/.tmp/close-req-rewrite-$REQ-$(date +%s)"
git worktree add -b "close-req-rewrite/$REQ-$(date +%s)" "$TMP" "$REQ_BRANCH"

# 2. 在 temp 内跑 rewrite
cd "$TMP"
python scripts/merge-modulespec.py docs/modules/<module>.md patches.json > new-modulespec.md
# PM 审 diff（per-module，但不分批 commit—— v3' 砍 V8 part-commit）
# PM accept all 才 commit；reject any → exit 1（V8 砍后的简化）

# 3. 成功路径
cd "$TMP" && git add docs/modules/ && git commit -m "doc-update rewrite for $REQ"
cd "$REQ_WORKTREE" && git merge --ff-only "close-req-rewrite/$REQ-..."
git worktree remove "$TMP" --force
git branch -D "close-req-rewrite/$REQ-..."
# 继续 close-req step 3+

# 4. 失败 / 取消 / PM reject 任一 module
cd "$REQ_WORKTREE"
git worktree remove "$TMP" --force
git branch -D "close-req-rewrite/$REQ-..."
exit 1  # req 保留 active/、stage=7、worktree 干净
```

**关键决策**：
- temp branch 命名前缀 `close-req-rewrite/` 固定 → 残留扫描可枚举（W6 用）
- temp worktree 路径用 `.tmp/`（项目内不污染 home）
- ff merge 强制不 merge commit；如 ff 不成（req worktree 期间被改）→ 报错让 PM 处理（应该不会发生，I-CR10 dirty gate 保证）

**实施清单**：
1. `scripts/close-req-rewrite-isolated.sh` 新建（流程脚本）
2. `scripts/close-req.sh` step 2 调用此脚本
3. `tests/close-req/test-rewrite-isolation.sh`：rewrite 中断 → temp worktree 删干净 + req worktree 不动

#### 17.3.2 W5 — close-req mutation 边界

**完整 close-req 流程（v3' 精确化，替代 §14.3.2 V7）**：

```
[阶段 P — pre-mutation read-only]
  step 0    入口 dirty gate：req worktree git status --porcelain 必须空
  step 0.5  main diff 提示（v3' I-CR16）：
            git fetch origin main &&
            git diff "$REQ_BASE..origin/main" -- docs/modules/ |
            非空 → 提示 PM "main 上 modulespec 有改动: <list modules>。
                             (a) pull main 先合 (b) 继续 close（rewrite 时按本 req base） (c) abort"
            （没有 V16 三分类、没有 V17、没有 git ref 锁）

[阶段 Q — mutation]
  step 1    写 close-report.md（commit 到 req 分支）
  step 1.5  CHECKPOINT：
            git rev-parse HEAD > .runs/close-req-checkpoint
            echo "{ts,head,req,phase:pre-rewrite}" >> events/close-req.jsonl
  step 2    W4 隔离 rewrite
            成功 → checkpoint phase: post-rewrite
            失败 → req 留 stage=7、close-report 已 commit、modulespec 未变
  step 3    实现深度变更检查
  step 4    active → closed/ 移动 + commit
  step 5    merge req → main + push
  step 6    清理 .runs/close-req-checkpoint
```

**关键决策**：
- step 0.5 用 `git diff` 行级 diff 提示，不跑 V3 公式三方合并、不分类 A/B/C、不 AI 提议合并方案。PM 决定 pull / 继续 / abort 三选即可。
- step 1 close-report 先 commit 是必要：rewrite 失败时 PM 看 close-report 知道这次准备 rewrite 什么，下次 retry 直接进 step 1.5（skip step 1）
- 砍 V8 part-commit：PM 在 W4 内审到任一 module reject → 整体 abort → close-req 失败回 active/。**v3' 不允许半合并状态**。

**实施清单**：
1. `scripts/close-req.sh` 重排步骤（dirty gate + main diff 提示 + checkpoint + W4 调用 + retry 入口）
2. `skills/close-req/SKILL.md` 步骤改写
3. `INVARIANTS.md`：
   - I-CR10：close-req step 0 dirty gate
   - I-CR11：rewrite 必须在 temp worktree（W4）
   - I-CR13：rewrite 输入按 git topo order
   - I-CR15：close-req step 1 后失败保留 active/、stage 不进 closed/
   - I-CR16：close-req step 0.5 main diff 提示门
4. `tests/close-req/test-mutation-boundary.sh` 覆盖每个失败时机的状态保证

#### 17.3.3 W6 — stale checkpoint 二层验证

**问题**（继 §14.3.4 V9 简化）：checkpoint 文件存在不等于"真的上次失败 retry"——cancel-req 后 / reset 后可能残留。

**v3' 二层验证**（砍 v3 三层的 mismatched-stage）：

```python
def detect_stale_checkpoint():
    cp = read('.runs/close-req-checkpoint')
    if not cp:
        return None

    # 验证 1：req 匹配
    if cp.req != current_req_id():
        return ('cross-req-stale', cp)  # 自动清理 + 继续

    # 验证 2：HEAD 可达性
    if not git_is_ancestor(cp.head, current_branch_head()):
        return ('orphaned', cp)         # 自动清理 + 继续 + audit

    return ('valid-retry', cp)          # PM 选 retry / abort
```

**处理映射**：

| 检测 | 入口动作 |
|---|---|
| None | 正常 close-req |
| valid-retry | "上次 close-req 在 phase=<X> 中断，retry / abort（清理）" |
| cross-req-stale | 自动清理 + 一行 audit + 继续 |
| orphaned | 自动清理 + 一行 audit + 继续 |

**砍**：v3 §14.3.4 的 mismatched-stage（"checkpoint 存在但 req 不在 stage=7"）—— 罕见 + 让 PM 介入比静默清理累。如果真碰到，按 cross-req-stale 处理（清掉 + 继续）。

**实施清单**：
1. `scripts/close-req.sh` 入口加 `detect_stale_checkpoint` 函数
2. `scripts/cancel-req.sh`（如存在）配套清理 `.runs/close-req-checkpoint`
3. `tests/close-req/test-stale-checkpoint.sh` 覆盖 3 种结果

### 17.4 W7 + W8 — quickfix schema 4 字段 + feature_id sidecar

#### 17.4.1 W7 — quickfix-log.jsonl schema 最小集

**问题**（继 §14.4.2 V11 大砍）：v3 schema 12 字段每次 quickfix PM 填表，注意力税爆。D1 痛点是时延+注意力 → schema 必须最小。

**v3' schema（每行 4 字段必填 + 2 字段自动）**：

```json
{
  "ts": "2026-05-12T10:23:00Z",            // 自动（commit time）
  "commit": "<quick-fix commit sha>",        // 自动
  "module": "module-log",                    // PM 选（base 现有 module 列表，可选 null = 纯文案）
  "feature_anchor": "列表筛选",                // PM 选（base 现有 feature anchor 列表，或新建）
  "change_type": "modify",                   // PM 选 add/modify/remove
  "needs_modulespec_update": true            // PM 拍 true/false
}
```

**字段说明**：

| 字段 | PM 工作 | AI 工作 |
|---|---|---|
| ts / commit | — | 自动注入 |
| module | 选（下拉，含 null 选项） | 列 base 现有 modules |
| feature_anchor | 选或写 | 列本 module 现有 anchors（含 "新建 feature" 选项） |
| change_type | 选 add/modify/remove | 默认推 modify |
| needs_modulespec_update | 拍 true/false | 默认推 true if module≠null else false |

**砍掉的 v3 12+ 字段**：

| 砍的字段 | 砍理由 |
|---|---|
| `schema_version` | v3' 是初版，未来加再说；现在没有跨版本兼容压力 |
| `summary` (free text) | commit message 已有；jsonl 不重复 |
| `feature_id` | W8 sidecar 走 |
| `change_kind` / `modulespec_patch` | rewrite 时由 AI 生成 patch（读 base + summary + diff），不让 PM 填 |
| `target_origin_req` | W8 sidecar 持，PM 不必填 |
| `recorded_in_req` | 隐含 = quickfix 所在 req（active req） |
| `supersedes` | 罕见；rewrite 时 AI 检测连续改同 feature |
| `affected_paths` | git diff 自带，jsonl 不重复 |
| `confirmed_by` / `confirmed_at` | PM 单人单 commit time 已包含 |
| `applied` | v3' quickfix 不实时写 modulespec，无 applied 概念 |

**rewrite mode 怎么消费**（doc-update §8 改）：

```
for qf in quickfix_log where needs_modulespec_update=true:
  # AI 读 quickfix commit diff 推断 patch:
  diff = git_show(qf.commit, '--', 'prototypes/')
  summary = git_show(qf.commit, '--format=%B', '--no-patch')
  patch = ai_infer_patch(
    module=qf.module,
    feature_anchor=qf.feature_anchor,
    change_type=qf.change_type,
    diff=diff,
    summary=summary,
    base_modulespec=read('docs/modules/<module>.md')
  )
  # patch 跟 task PM 视图 patch 同等地位进 W3 merge
```

**关键决策**：
- AI 推断 patch 而不是 PM 填 → 让 PM 工作流"快快做完 quickfix" 而不是"填表 5 字段每次"。AI 偶尔推错 → 在 W3 merge 阶段进 `CONFLICT_REFERENCE_MISSING` 询问门，PM 看到时再修正。
- `needs_modulespec_update` 让 PM 显式拍：纯文案改 quickfix（如改个按钮文字）PM 选 false，不进 rewrite；产品决策类 quickfix（改默认排序）选 true，进 rewrite。**这一个字段把 PM 意图直接表达，无需 AI 检测 V12 红色信号词**。

**实施清单**：
1. `templates/quickfix-log.schema.json` 写最小集（4 必填）
2. `skills/quick-fix/SKILL.md` step 4 commit 前加 4 字段 inline 表单（AI 推默认值 PM 拍 OK）
3. `scripts/lint-quickfix-log.py` 4 必填 lint，commit hook
4. `tests/quick-fix/test-schema-minimal.py` 覆盖：必填校验 / module=null 合法 / needs=false 合法

#### 17.4.2 W8 — `.feature-index.json` sidecar

**问题**（继 §14.4.1 V10 + §14.6.4 C4.4 改 sidecar）：feature_id + origin_req + last_modified 是 AI 维护的元数据，PM 不读。注入 modulespec HTML 注释让 PM 视图变机器索引载体。

**v3' 设计**：sidecar 文件 `docs/modules/.feature-index.json` 持元数据，modulespec 文件保持纯人读。

**schema**：

```json
{
  "schema_version": "v1",
  "features": {
    "module-log": {
      "列表筛选": {
        "feature_id": "a3f2c8",           // stable hash（首次 add 时算，永不重算）
        "origin_req": "R-2025-098",        // 首次 add 时的 req
        "last_modified_req": "R-2026-001", // 最近改的 req
        "last_modified_at": "2026-05-12T10:23:00Z"
      },
      "导出 CSV": {
        "feature_id": "5d8e21",
        "origin_req": "R-2026-001",
        "last_modified_req": "R-2026-001",
        "last_modified_at": "2026-05-12T14:05:00Z"
      }
    }
  }
}
```

**索引键**：`module-name + feature_anchor`（H3 标题文本）→ 元数据。

**feature_id 算法**：

```
feature_id = blake2b(canonical_module + '/' + normalize(feature_anchor))[:12]
  首次 add 时算并写入 sidecar；后续 anchor 改名时 sidecar 保持原 id（key 改名）
```

**anchor 改名怎么办**：sidecar 内 key 同步改名（W3 rewrite 时如果 PM 在询问门选"PM 调"改了 anchor → sidecar key 跟着改，feature_id 不变）。无需 alias 表（V4 砍）：H3 anchor 是 source of truth + sidecar key 同步即可。

**AI 怎么用 sidecar**：
- W1 task→module 映射：不用 sidecar
- W3 merge 函数：不用 sidecar（操作 anchor 文本）
- close-req rewrite 输出新 modulespec：sidecar 同步更新（add → 新 entry / modify → last_modified_* 更新 / remove → delete entry + 一行 `requirements/closed/<req>/feature-removal.log` audit）
- quickfix metadata 填表：AI 列 base 现有 anchor 时读 sidecar（按 module 过滤），不重复扫 modulespec H3
- 历史归因：PM 想问 "这个 feature 是哪个 req 加的" → `jq` sidecar

**关键决策**：
- sidecar `.gitignore` 不忽略：进版本控制，跟 modulespec 一起 commit
- modulespec 文件不再有 HTML 注释 `<!-- feature_id ... -->`：PM 看 diff 清爽
- sidecar PM 不读：但可看（机器友好 + 偶尔查询）

**实施清单**：
1. `templates/feature-index.schema.json` 新建
2. `scripts/update-feature-index.py` 新建：rewrite 后调用，diff sidecar
3. `skills/doc-update/SKILL.md` §8 rewrite 输出后调
4. `skills/quick-fix/SKILL.md` 4 字段表单 anchor 选项从 sidecar 读
5. `tests/sidecar/test-feature-index.py` 覆盖：add/modify/remove/rename anchor 同步

### 17.5 W9 — 横切（3 fixture + 多 worktree 单行替代）

#### 17.5.1 三 fixture 详定

**取舍**（vs §14.5.2 V15 11 fixture）：v3' 砍到 3 个核心 e2e fixture。其余 8 个 fixture 进 round 5 autoplan 通过后再补。

**fixture 目录结构**：

```
tests/fixtures/d13-v3prime/
├── case-01-rewrite-success/
│   ├── README.md
│   ├── input/
│   │   ├── base-modulespec/docs/modules/module-log.md
│   │   ├── feature-index.json (W8 sidecar)
│   │   ├── req-meta.json
│   │   ├── tasks/T1.md (含 module_impact)
│   │   ├── tasks/T2.md
│   │   └── quickfix-log.jsonl (2 条 needs_modulespec_update=true)
│   ├── expected-output/
│   │   ├── new-modulespec/docs/modules/module-log.md
│   │   ├── new-feature-index.json
│   │   └── audit.md
│   └── run.sh
├── case-02-rewrite-fail-retry/
└── case-03-no-residue/
```

**3 个 fixture 各覆盖**：

| # | 场景 | 验证什么 |
|---|---|---|
| 01 | 成功 happy path（2 task + 2 quickfix，正常 modify + 1 add，无冲突）| W1 模块映射 / W2 topo order / W3 公式 + 3 类 op / W4 隔离 worktree ff merge / W7 schema 消费 / W8 sidecar 同步 |
| 02 | rewrite 中途 PM reject 一个 module → 整体 abort → retry 成功 | W4 失败 force 清理 / W5 close-report 已 commit 但 modulespec 未变 / W6 checkpoint phase=pre-rewrite valid-retry / retry skip step 1 |
| 03 | rewrite 全程无残留（kill -9 模拟）| W4 temp worktree 强制清理 / 主 worktree 不动 / `.runs/close-req-checkpoint` 三层验证后清掉 |

**fixture 形态**：每个 case 是小型 git 仓 fixture（pre-built），`run.sh` 跑 `close-req` + 比较 expected-output。

**run.sh 模板**：

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# setup
rm -rf .work && cp -r input .work
cd .work && git init -q && git add . && git commit -q -m "fixture init"

# trigger close-req
bash ../../scripts/close-req.sh <req-id> --non-interactive --auto-accept

# diff against expected
diff -r docs/modules/ ../expected-output/new-modulespec/docs/modules/
diff feature-index.json ../expected-output/new-feature-index.json
```

**砍掉的 v3 fixture**（8 个进 v4 候选）：
- case-04 PM 部分接受 → V8 砍了
- case-05 change_type=remove e2e → 包含在 case-01 的扩展
- case-06 老 quickfix downgrade → 一次性脚本测试，不必 fixture
- case-07/08/09 多 worktree A/B/C → V16/V17 砍了
- case-10 quickfix 实时写 → C4.2 砍了
- case-11 quickfix 改历史 req 产物 → C4.4 砍 HTML 注释方案后无需 fixture

#### 17.5.2 多 worktree 单行替代（V16/V17 砍后）

**替代 §14.7 整节**：

```bash
# close-req step 0.5（W5 已含，本节是它的实现细节）：

git fetch origin main
REMOTE_DIFF=$(git diff "$REQ_BASE..origin/main" -- docs/modules/)

if [ -n "$REMOTE_DIFF" ]; then
  echo "⚠️ main 上 modulespec 有改动："
  git diff "$REQ_BASE..origin/main" -- docs/modules/ --name-only
  echo ""
  echo "PM 选："
  echo "  (a) pull main 先合 (推荐 if 关联 req)"
  echo "  (b) 继续 close（rewrite 按本 req base，merge 时可能冲突 PM 解）"
  echo "  (c) abort（先去研究 main 改了啥）"
  read -p "选 a/b/c: " CHOICE
  case "$CHOICE" in
    a) git pull origin main; exit 0 ;;
    b) ;; # 继续
    c) exit 1 ;;
  esac
fi
```

**vs v3 §14.7 整套砍掉的**：
- step 0.5 三分类 A/B/C → 砍
- AI 三方 merge 算法 → 砍（PM 自己看 diff 一行决策即可）
- AI 冲突分类器（functional / cosmetic / 语义） → 砍
- AI 提议 2-3 合并方案 → 砍
- close-task step 0.5 / V17 全套 → 砍
- git ref `refs/locks/close-req-active` 锁 → 砍
- audit 模板 `step-0-5-audit.template.md` → 砍
- I-CR17 / I-CR18 / I-CT9 invariant → 砍

**关键决策**：
- 单 PM 工作流 + 多 worktree 真冲突时 PM 已经记得自己在干什么（不像团队场景 PM 不知道同事改了 main）；让 PM 看 git diff 一眼即可决策，框架不替 PM 想
- 真发生 (b) 后 merge 冲突 → PM 用熟悉的 git merge 工具解（不必 framework 给 AI 助理合并）；如果 PM 体感真痛 → round 5 autoplan 后补 V16 强化版

**实施清单**：
1. `scripts/close-req.sh` step 0.5 实现（≤30 行）
2. `INVARIANTS.md` I-CR16：close-req step 0.5 main diff 提示门
3. `tests/close-req/test-step05-main-diff.sh` 覆盖：empty diff（自动跳过）/ 非空 diff PM 选 a/b/c

### 17.6 改动清单（替代 §16.5 简表）

| # | 文件 / skill | 操作 | 关联任务 |
|---|---|---|---|
| **vp-01** | `scripts/req-module-impact.py` | 新建（≤80 行） | W1 |
| **vp-02** | `scripts/merge-modulespec.py` | 新建（W3 公式实现） | W3 |
| **vp-03** | `scripts/close-req-rewrite-isolated.sh` | 新建（W4 流程） | W4 |
| **vp-04** | `scripts/close-req.sh` | 重排：dirty gate + step 0.5 main diff + checkpoint + W4 调 + retry 入口 + stale 二层验证 | W5+W6 |
| **vp-05** | `scripts/cancel-req.sh` | 清理 `.runs/close-req-checkpoint` | W6 |
| **vp-06** | `scripts/lint-quickfix-log.py` | 新建（W7 schema 4 必填 lint） | W7 |
| **vp-07** | `scripts/update-feature-index.py` | 新建（W8 sidecar 同步） | W8 |
| **vp-08** | `skills/doc-update/SKILL.md` | §8 改：调 W3 merge + temp worktree（W4） + topo order（W2） + sidecar 同步（W8） + quickfix patch AI 推断（W7） | W3+W4+W2+W7+W8 |
| **vp-09** | `skills/quick-fix/SKILL.md` | step 4 commit 前加 4 字段表单（AI 推默认值 PM 拍）；砍 v2 自由文本 log；不写 modulespec | W7 |
| **vp-10** | `skills/task-spec/SKILL.md` | 加：生成 PM 视图 patch 时 AI 读 base 填 `expected_old`；保持 module_impact frontmatter（不砍 lint 但降级 warn） | W3 |
| **vp-11** | `skills/task-execute/SKILL.md` | 步骤 2.1：维持 D13 主流程（task 不写 modulespec）；砍 §14.6.2 C4.2 snapshot 读路径（v3' 直接读 docs/modules/） | — |
| **vp-12** | `skills/close-task/SKILL.md` | 维持 v2：merge + 归档，不调 doc-update；不加 step 0.5（V17 砍） | — |
| **vp-13** | `skills/close-req/SKILL.md` | 步骤改写（按 W5 流程） | W5 |
| **vp-14** | `skills/req-stage-gate/SKILL.md` | 简化 stage 6→7 gate：砍 half-close detection（v2 已砍，v3' 不变） | — |
| **vp-15** | `templates/quickfix-log.schema.json` | 新建（W7 4 字段） | W7 |
| **vp-16** | `templates/feature-index.schema.json` | 新建（W8 sidecar） | W8 |
| **vp-17** | `INVARIANTS.md` | 加 I-CR10 / I-CR11 / I-CR12 / I-CR13 / I-CR15 / I-CR16 / I-QF1（共 7 条新增；I-CT2 不变） | 全 |
| **vp-18** | `tests/fixtures/d13-v3prime/` | 3 个 e2e fixture 目录 | W9 |
| **vp-19** | `tests/scripts/test-req-module-impact.py` | W1 单测 | W1 |
| **vp-20** | `tests/merge/test-three-way.py` | W3 单测 | W3 |
| **vp-21** | `tests/close-req/test-rewrite-isolation.sh` | W4 测试 | W4 |
| **vp-22** | `tests/close-req/test-mutation-boundary.sh` | W5 测试 | W5 |
| **vp-23** | `tests/close-req/test-stale-checkpoint.sh` | W6 测试 | W6 |
| **vp-24** | `tests/quick-fix/test-schema-minimal.py` | W7 单测 | W7 |
| **vp-25** | `tests/sidecar/test-feature-index.py` | W8 单测 | W8 |

**总计 25 项**（vs v3 §14.8 36 项，砍 11 项；其中大多数是合并 + 砍掉 v3 的过度工程）。

### 17.7 INVARIANTS（替代 §16.4 表）

| INVARIANT | 守卫点 | 内容 |
|---|---|---|
| **I-CR10** | `close-req.sh:enter` | close-req step 0 入口 dirty gate：req worktree `git status --porcelain` 必须空 |
| **I-CR11** | `close-req.sh:step2` | rewrite 必须在 temp worktree（W4 流程），失败 `git worktree remove --force` 清理 |
| **I-CR12** | `close-req.sh:enter` | stale checkpoint 二层验证（req + HEAD 可达性）；mismatched-stage 砍 |
| **I-CR13** | `doc-update/SKILL.md:§8` | rewrite 输入合并按 `git log --topo-order` 顺序 |
| **I-CR15** | `close-req.sh:step1+` | close-req step 1 后任何失败保留 active/、stage 不进 closed/、close-report 已 commit 可 retry |
| **I-CR16** | `close-req.sh:step0.5` | close-req step 0.5 main diff 提示门：远端 docs/modules/ 有改动必须显式让 PM 选 a/b/c |
| **I-CT2** | `task-execute / close-task` | （不变）task worktree clean / 分支存在 / req 分支存在 / req worktree 存在 |
| **I-QF1** | `close-req.sh:enter` | 老 quickfix（无 v3' schema） > 5 → 提示 PM 走一次性 `scripts/quickfix-backfill.sh` |

**共 8 条**（vs v3 §14.9 17 条，砍 9 条）。

### 17.8 pre-flight（替代 §16.6）

**产品层 pre-flight 先**（必跑，未过不进工程实施）：

| # | check | 通过标准 |
|---|---|---|
| **P1** | **N 分布统计**：adminconsole4 近 10 个 closed req 统计 task 数 + quickfix 数 | 50% req 有 N≥2 task or quickfix → D13 大方向成立；若 N=1 占 >70% → 触发 reconsider（D13 主流程对单 task req 仍有 close-task 不打断 + 集中审 close-req 价值，但收益降） |
| **P2** | **PM 注意力 break-even**：对一个真实 req 主观计时——D13 路径（close-task 静默，close-req 一次集中审）vs 旧 settlement 路径（每 task close 都审 diff）。PM 主观打分两种工作流 | D13 路径主观分 ≥ 旧路径 → 通过 |
| **P3** | **PM 痛点二次确认**：跑 P1+P2 后，问 PM "(b)+(c) 时延+注意力 是 D13 该解的真痛吗？还是用了几次发现痛在别处" | PM 主观确认 (b)+(c)；如改答其他 → 重新 design |
| **P4** | **W7 4 字段填表体感**：跑两个真实 quickfix 走 v3' 4 字段表单。PM 主观评 "填表注意力税" | ≤ 30 秒 / quickfix → 通过；超 → reconsider 字段数 |

**工程层 pre-flight 后**（P1-P4 通过才跑）：

| # | check | 通过标准 |
|---|---|---|
| **E1** | grep 测试套件：`grep -rn "settlement\|对账\|SKIP_DOC_UPDATE\|cleanup_status\|half-close\|skip-doc-update" tests/ scripts/tests/` | 列出受影响测试 → 估算改动量 |
| **E2** | W4 isolation kill 模拟：手动 `kill -9` rewrite 中间 → 验 temp worktree 清理路径 | temp worktree 删干净 + req worktree 不动 |
| **E3** | W7 schema lint 测试：4 必填 / null 合法 / 多字段拒绝 | 全 pass |
| **E4** | W8 sidecar 同步测试：add/modify/remove/anchor rename | 全 pass |

**特别约定**：P1+P2+P3 通过的判定门 **不是 AI 决，是 PM 主观决**。AI 输出数据，PM 看完拍。这是为了避免 v3 那种"AI 把 round 3 评审反馈过度形式化"再发生——本节产品层 pre-flight 必须 PM 亲手过。

### 17.9 v3' 完成后

1. **PM 拍 §十七**（如需微调按本对话再补）
2. **跑 round 5 autoplan** 验 v3'（focal：D1 时延+注意力痛点是否真锚定 / W3 1 类 CONFLICT 询问门 PM 体验 / W7 4 字段 + AI 推断 patch 路径 / I-CR16 单行 main diff 提示是否足够替代 V16/V17）
3. **跑 P1-P4 产品层 pre-flight**：N 分布 + break-even + 痛点确认 + 填表体感
4. P1-P4 通过 → E1-E4 工程层 pre-flight
5. 全过 → Phase C 实施（按 §17.6 25 项分 PR；推荐顺序：vp-01/02（W1+W3） → vp-15/16（schema） → vp-03/04（close-req 流程） → vp-08/09（skill 改） → vp-18 fixture → vp-17 INVARIANTS）
6. 任一 pre-flight 失败 → v4 设计回合




