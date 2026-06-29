# §9.7 跨 skill 共享原则

> 本文件是 [`PM-VIEW-RULES.md`](../PM-VIEW-RULES.md) §9.7 的物理拆分。配套阅读：[`input-flow.md`](./input-flow.md)。

1. **PM 视图不读工程合同文件**：活跃链路不再生成 `.engineering.md`；若历史文件仍存在，PM 视图 skill 一律不读。

2. **`DESIGN.md` 是视觉单一来源**：
   - `design`：全文必读，用于范围与视觉草图约束。
   - `build`：动手前全文必读。
   - `review` / 视觉门：全文必读并对截图校验。
   - `build-close`：只在 build 验收后，且视觉规范类反馈需要沉淀时修改。

3. **`prototype/` 反向校验按 `input-flow.md` §9.3.1 执行**：范围确认、模块规格修订、反向 PRD 按概念 grep；build 做实现参考时可读相关组件全文。

4. **章节匹配按 `input-flow.md` §9.1.1 执行**：grep 0 命中不能自动判定功能已砍，必须列关键词并追问或改用模块索引定位。

5. **`PM-VIEW-RULES.md` 每会话读 1 次**：后续步骤引用拆分文件即可，不反复整份塞 context。

6. **PM 反馈分流只在 build-close 或 record 沉淀**：build / review 期间的 PM 反馈先用于改 demo；build 验收后需要长期沉淀的内容在 build-close 里按视觉、术语、跨功能规则、模块规格四类分流；未 build 但要写长期基线时走 record。

7. **历史 task 只作归档证据**：如果迁移或考古必须读取 `requirements/**/tasks/*.md`，只读 PM 反馈或验收结论，不把其字段布局、状态名、任务编号带回活跃流程。
