# §9.7 跨 skill 共享原则

> 本文件是 [`PM-VIEW-RULES.md`](../PM-VIEW-RULES.md) §9.7 的物理拆分。配套阅读：[`input-flow.md`](./input-flow.md)（§9.1 - §9.6 输入流约束 / 双文件 lazy sync 等）。下文中 §9.X 引用一律指向 `input-flow.md`。

**描述风格规则跨 skill 适用范围**：[`writing-rules.md`](./writing-rules.md) §3.12「描述风格规则」适用于所有 PM 视图产出（PRD / task spec / 飞书发布前文案 / brief / analysis），由 `scripts/check-prd-hierarchy.py` lint 类 2 全篇兜底机械违规。新违规词按 writing-rules.md 顶部「如何补新规则」5 步反馈循环 SOP 补入。

1. **`.engineering.md` 仅工程合同链路读**：PM 视图 skill（design 探索段 / prd-writing / task-plan / task-spec PM）一律 ❌ 不读任何 `.engineering.md`（§9.1 / §9.2）

2. **`docs/DESIGN.md` 在 PM 视图链路保留必读但分级**（按 §9.1 各 skill 行）：
   - `task-spec` PM 视图（first-gen + revise）：🟡 章节 grep（按 task 涉及功能 grep 相关章节，§9.1.1）
   - `task-spec` 工程合同：🟢 全文必读
   - `task-plan`：⚪ 按需（视觉决策不影响 task 拆分粒度）
   - `task-execute`：🟢 强制 cat 全文（视觉一致性护身符）
   - `close-task`：🟢 全文必读（PM 反馈第四类反推沉淀目标）
   - `prd-writing`：🟢 全文必读
   - **不可整体砍**：DESIGN 是 PM 反馈第四类（视觉规范）沉淀地（§9.4），不同 skill 按不同强度引用

3. **`prototype/` 反向校验场景按 §9.3.1 grep 强约束**：仅 task-execute 例外（实现参考全文读）

4. **章节匹配场景按 §9.1.1 grep 强约束**：prd.md 在 first-gen 整文件读 / revise grep

5. **`PM-VIEW-RULES.md` 步骤 0 读 1 次/会话，后续步骤不重读**

6. **PM 反馈四类分流的读取分工**（§9.4）：
   - `task-spec` 读"同模块已完成 task 的 PM 反馈"前三类（正向规则 / 反向约束 / 决策记录）→ 落到当前 task 对应章节
   - `close-task` 步骤 1.5 读"本 task 的 PM 反馈"第四类（视觉规范）→ 反推沉淀到 `docs/DESIGN.md`
   - `prd-writing` **不读** `## PM 反馈` 段；prd-writing 读 task PM 视图的 `^## (📋 功能清单|🎯 关键产品决策|✅ 验收清单)` 三段是另一个目的（抽功能需求），与 §9.4 PM 反馈分流读法**不同读法 / 不同来源段**，不冲突

7. **closed/ 旧 task 读取边界**：扫描 `requirements/closed/**/tasks/*.md` 时，**只读 `## PM 反馈` 段**抽反馈条目；**不读**顶部 frontmatter / 元信息段落 / 任务卡表格的字段布局（v1 历史格式，新 task 按 v2 模板生成；混读会触发 task-spec 步骤 10.6 字段校验拦截重写）
