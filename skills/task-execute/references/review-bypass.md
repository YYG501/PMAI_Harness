# 附录：PM 验收阶段跑 review（旁路 — 非必经）

> 本文件是 `skills/task-execute/SKILL.md` 末尾「附录」的物理拆分。

PM 在验收期间任意时刻可自跑 `/review` `/qa` `/design-review` 等 review 工具。AI 仍**不得**自行调用（I-RV1）—— 这条规则覆盖整个 task 生命周期，不限于实现阶段。

**PM 报告 review 结论后**（chat 里说"跑了 /review，pass，2 个 mechanical issue 已修"等），AI 机械执行：

1. 在工程合同 §11 自审记录追加一条（保留 PM 原话或转写）：
   ```markdown
   ### 自审 N - [YYYY-MM-DD HH:MM]
   **工具：** /review
   **结果：** pass（2 个 mechanical issue 已修复）
   **详细发现：**
   - F-001: 变量命名不一致 → 已修复
   - F-002: 缺少 null check → 已修复
   **遗留问题：** 无
   ```

2. append `review_completed` 事件作为审计痕迹（I-RV2）：
   ```bash
   python3 .claude/scripts/task-events.py append "<task-file>" \
     --type review_completed --tool "/review" --result "<pass|fail>"
   ```

**PM 跑完 review 后反馈"还有 X 需要修"**：和步骤 12 PM 打回路径一致 —— 写反馈到 PM 视图历史档案、修代码、追加 fix commit、重新呈交。

**禁止**（I-RV3）：先 append 后跑、跳过 PM 直接 append、AI 替 PM 跑 review 然后伪造结论。append 必须发生在 PM 明确报告结果之后。
