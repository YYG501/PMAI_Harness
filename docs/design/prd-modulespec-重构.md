# PRD / modulespec 体系重构

> 状态：v1 方案 + autoplan 评审 + v1.1 stage 术语修正 + Q1-Q4 全部已拍 + D4/D8/D10/A2 AI 自决 / **§十二 D13 rewrite-only modulespec 维护方案待 PM review**
> 日期：2026-05-11（v1 / autoplan / v1.1 同日迭代）
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

## 十二、rewrite-only modulespec 维护方案（D13，**待 PM review**）

> **状态**：PM 倾向选 B（2026-05-11），但要求先写进文档再决定动手。本节供 review。
> **如果 PM 通过 D13**，本节会替换 §3.2 / §四 / §五 相关章节，对设计文档影响巨大。

### 12.1 决策背景

PM 观察到：一个 task 完成后，后续 task 或 quickfix 可能修改之前 task 的工作。settlement mode（task close 时立即写 modulespec）下，同一处会被反复覆盖、重复沉淀。

PM 提议：**改成 rewrite-only**——task close 时不写 modulespec，等 req close 时一次性 rewrite。

### 12.2 新工作流（rewrite-only）

```
stage 6（task 执行期间）
  ├ task A close → 只 merge + 归档，不写 modulespec
  ├ task B close → 同上
  ├ quickfix    → 改原型 / 文档不动 modulespec（跟原 quick-fix:152 一致）
  └ ... 所有 task 完成

stage 6 → 7 gate
  └ req-stage-gate 检查：所有 task 已 close + worktree 清理
     （无半关闭检查——因为没有半关闭概念了）

stage 7（req close）
  └ /close-req 执行：
     ├ 步骤 1   写 close-report.md
     ├ 步骤 1.5 砍（无 SKIP marker 要分流）
     ├ 步骤 2   ★ 必跑 doc-update rewrite mode
     │         收集本 req 所有 task 的 PM 视图功能清单 + quickfix 原型变更
     │         按模块聚合 → 整段 rewrite 到 docs/modules/<module>.md
     │         PM 审 diff（默认逐章节）
     ├ 步骤 3   实现深度变更检查
     └ 步骤 4   归档 req + merge req 分支到 main
```

### 12.3 砍掉的机制清单

D13 通过则砍这些（整套）：

| 机制 | 位置 | 影响 |
|---|---|---|
| **settlement mode** | `skills/doc-update/SKILL.md` §1.7 | doc-update 不再被 close-task 调用 |
| **对账模式** | `skills/doc-update/SKILL.md` §1.5 / §1.6 | task close 时不再做行级对账 |
| **半关闭机制** | `skills/close-task/SKILL.md` §38-67 `--skip-doc-update` flag | 整套砍：flag + reason 参数 + SKIP_DOC_UPDATE marker + cleanup_status 字段 + 人工 Cleanup TODO section |
| **req-stage-gate 半关闭检测** | `skills/req-stage-gate/SKILL.md:308-344` C2 half-close detection | 砍掉：stage 6→7 gate 简化为"所有 task 已完成 + merged + worktree cleaned" |
| **D8 覆盖率统计** | `skills/close-req/SKILL.md` step 2a | 自然消失（D13 通过后 D8 失去监控对象） |
| **`/close-task` 调 `/doc-update`** | `skills/close-task/SKILL.md` 步骤 2 | 直接 merge + 归档，不调 doc-update |

doc-update 自身保留：
- **rewrite mode**（§8）—— 留下作为 close-req 必跑路径
- **保险机制 + 失败处理 + 多模块 atomic merge**（§1.7.3）—— 这些 rewrite mode 也需要

### 12.4 跟之前决议的交互

| 决议 | D13 通过后变化 |
|---|---|
| **Q1 双解析器** | 仍需要——rewrite mode 跑 doc-update 时要能读 adminconsole4 老 modulespec 8/10 节做对照 |
| **Q1 增量迁移（b）** | 触发点变成"req close 时 rewrite mode 把涉及到的模块从老格式 rewrite 到新格式"——更干净 |
| **Q2 软防线 a/b** | 不变（仍要 prd-writing 加硬规则 + modulespec 顶部刺眼提示） |
| **Q3 prd-writing 最小改** | 不变 |
| **Q4 PRD on-demand 实测** | **PRD 派生时机要重新评估**——main 分支 modulespec 永远是上一次 close-req 的最终状态；active req 期间在主分支跑 prd-writing 看不到本 req 的改动（git 工作流正常行为，但 PM 心智要适应） |
| **D4 跨模块依赖标注** | 不变（仍写 `依赖：module.feature [r/w/event]`）|
| **D8 覆盖率统计** | 自然失效，整段砍 |
| **D10 typed optional blocks** | 不变（rewrite mode 写入这些 blocks） |
| **A2 术语公约小数** | 不变 |

### 12.5 INVARIANTS 影响

需要重审的 INVARIANTS（参 `INVARIANTS.md`）：

| INVARIANT | 当前内容 | D13 后变化 |
|---|---|---|
| **I-CT2** | close-task 前置条件包括"doc-update 已完成" | 砍这条前置 |
| **I-CT3-5** | close-task 的 merge / 归档 / cleanup 顺序 | 不变 |
| **I-CT7-8** | 事件流证明状态机推进 + commit 时间戳防御 | 不变 |
| **I-CR**（1-9）| close-req 流程 | **新增一条**：close-req 必跑 rewrite mode 后才能 merge main |
| **I-TT**（1-3,5-7）| task status transition | 不变 |
| **I-CB10** | task 文件状态字段 / .req-meta.json stage 字段禁止直接编辑 | 不变 |

### 12.6 待 review 的开放问题

PM review 时要拍：

1. **rewrite mode 的 PM 工作量**：当前 rewrite mode 要 PM 逐章节审 diff。改成必跑后，**每个 close-req 都要审一遍**——PM 接受吗？还是简化成"默认全接受，PM 关心时才审"？

2. **跨 req 的连续修改**：req X close 后 modulespec 反映 req X 的最终状态。req Y 接着改同模块，task-spec 阶段读 modulespec 是 req X 的状态（正确）。**但 req Y 期间 task-spec 读什么知道"本 req 内之前 task 加了什么"**？
   - 答：从同 req 内已 close 的 task PM 视图主文件读（input-flow.md §9.4 第一类已规定）
   - 这跟当前框架行为一致，但要确认 input-flow.md 在 D13 下不需要改

3. **active req 期间在主分支跑 prd-writing**：
   - main 分支看到的是上一次 close-req 的状态（不反映 active req 内改动）
   - PM 需要 active req 内中间状态时怎么办？
   - 选项 a：接受这个 trade-off（main 分支 PRD 永远是 stable state）
   - 选项 b：prd-writing 增加 fallback——在 req 分支跑时合并读 modulespec + 本 req task PM 视图

4. **close-req 失败的 blast radius**：
   - 当前 close-task 失败影响单 task；D13 后 close-req 跑 rewrite 失败影响整个 req close
   - 建议：rewrite mode 设计严格 atomic（doc-update §1.7.3 已有 git temp branch 机制），失败时回滚到 close-req 前的状态

5. **测试套件影响升级**：
   - 不只 grep `project-prd / step 2a / step 2b`，还要 grep `settlement / 对账 / SKIP_DOC_UPDATE / cleanup_status / half-close` 等
   - 估算修改 N 个测试可能从 v1 估的"少数"变成"几十个"

### 12.7 D13 通过后 §五 改动清单的新增

如果 D13 通过，§五 16 项要再追加：

| # | 文件 / skill | 操作 |
|---|---|---|
| 21 | `skills/close-task/SKILL.md` | **大改**：砍 --skip-doc-update flag + 砍调 doc-update 步骤 + 砍 SKIP marker / cleanup TODO 整套 |
| 22 | `skills/doc-update/SKILL.md` | **大改**：砍 settlement mode（§1.7）+ 对账模式（§1.5/1.6）+ 沉淀风险判断（§0.5）；保留 rewrite mode（§8） |
| 23 | `skills/req-stage-gate/SKILL.md:308-344` | 简化 stage 6→7 gate：砍 half-close detection |
| 24 | `skills/close-req/SKILL.md` | 步骤 2 改为必跑 doc-update rewrite mode |
| 25 | `INVARIANTS.md` | 改 I-CT2 + 新增 I-CR 一条 |
| 26 | `templates/task.md.tmpl` / `templates/task.engineering.md.tmpl` | 砍 SKIP_DOC_UPDATE / cleanup TODO 模板 section |
| 27 | 测试套件 | 改所有依赖 settlement / 半关闭的测试 |

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
