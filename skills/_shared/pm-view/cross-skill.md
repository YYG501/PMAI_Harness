# §9.7 跨 skill 共享原则

> 本文件是 [`PM-VIEW-RULES.md`](../PM-VIEW-RULES.md) §9.7 的物理拆分。配套阅读：[`input-flow.md`](./input-flow.md)。

1. **PM 视图不读工程合同文件**：活跃链路不再生成 `.engineering.md`；若历史文件仍存在，PM 视图 skill 一律不读。

2. **`DESIGN.md` 是视觉单一来源**：
   - `design`：全文必读，用于范围与视觉草图约束。
   - `build`：动手前全文必读。
   - `review` / 视觉门：全文必读并对截图校验。
   - landed 后自动文档编译：只在 build 验收并落地主线后，且视觉规范类反馈需要沉淀时修改；build-close 恢复入口复用。

3. **最终 build target 证据检查按 `input-flow.md` §9.3.1 执行**：范围确认和规格对账按概念 grep，用于识别实现缺口；不得从代码或原型反向删改已确认需求。build 做实现参考时可读相关组件全文。

4. **章节匹配按 `input-flow.md` §9.1.1 执行**：grep 0 命中不能自动判定功能已砍，必须列关键词并追问或改用模块索引定位。

5. **`PM-VIEW-RULES.md` 每会话读 1 次**：后续步骤引用拆分文件即可，不反复整份塞 context。

6. **PM 反馈只在收敛点进入长期基线**：build / review 期间，只有当前批准模块与任务内、且不改变产品基线或模块模型的小范围调整可修改结果并记录 accepted delta；产品级变化回 Proposal，模块模型变化回 design。落地主线后由自动文档编译按视觉、术语、跨功能规则、模块规格归位；没有 active work 且只是补录已确认的 TODO、术语、跨模块规则、项目理路或 main 现状纠错时才走 record。

7. **历史 task 只作归档证据**：如果迁移或考古必须读取 `requirements/**/tasks/*.md`，只读 PM 反馈或验收结论，不把其字段布局、状态名、任务编号带回活跃流程。
