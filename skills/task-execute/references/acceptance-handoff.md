# 步骤 11 详细：呈交 PM 验收（信息包 + 输出块 + 引导反推）

> 本文件是 `skills/task-execute/SKILL.md` 步骤 11 的物理拆分。主 SKILL 步骤 11 入口仅留触发说明 + 指向本文件的引用。commit 后默认自动呈交，PM 不需手动敲 `/task-submit`；task 状态全程「执行中」，commit 不切状态。

## 11.1 组装验收信息包

读两文件：
- PM 视图主文件（`.md`）：「📌 任务卡」/「📐 产物预览」/「✅ 验收清单」/「📁 历史档案」最新执行日志 / 业务层偏差表
- 工程合同（`.engineering.md`）：§1 推荐 review 工具 / §9 工程层验收清单 / §10 文档偏差 / §11 自审记录

收集 diff：
```bash
REQ_BRANCH=$(jq -r '.req_branch // empty' .req-meta.json 2>/dev/null \
  || git symbolic-ref --short HEAD | sed -E 's/^task-[0-9]+-/req-/' \
  || echo "main")
git diff --stat "$REQ_BRANCH"..HEAD
```

读事件流的 review_completed 条目（PM 在验收期间已跑过 review 时才有）：
```bash
python3 .claude/scripts/task-events.py list "$TASK_FILE" --type review_completed
```
- 有事件 → 自审结果末尾追加 PM 已跑的工具及结论（如 `/review pass`）
- 无事件 → 不在主体显示，仅末尾「⚙️ 可选深度审查」提示存在性

判断 task 类型（UI / 非 UI），按 task-submit §步骤 2 同样信号判定（任一命中即 UI）：
- task 描述涉及前端/页面/组件/界面/UI/view/component
- 工程合同 §1「推荐 review 工具」字段含 `/design-review` 或 `/qa`
- PM 视图「📐 产物预览」section 含 ASCII 线框图

## 11.2 输出验收信息块

**UI 类 task**（含 dev server 走查指引 + 多视角链接，AI 按 task 描述推断具体路径与 query params）：

```
═══════════════════════════════════════
📋 Task 验收：task-NNN-<slug>
═══════════════════════════════════════

🌐 走查链接（dev server 持续在 :<port>，PM 可在浏览器走查任意视角）：
  • <视角 1 描述>: http://localhost:<port>/<path>?<params>
  • <视角 2 描述>: http://localhost:<port>/<path>?<params>
  ...

📝 改动摘要：
[最新执行日志「**改动摘要：**」一行]

📊 Diff 摘要（vs <REQ_BRANCH>）：
[git diff --stat 输出]

🔍 自审结果：
[工程合同 §11 最新一条要点；如 PM 已跑 review，附 review_completed 事件结论]

✅ 验收清单（PM 主路径走查）：
- [ ] 条件 1
- [ ] 条件 2
[逐条来自 PM 视图 §✅ 验收清单]

📄 文档偏差：
PM 视图：[历史档案中的偏差或"无"]
工程合同：[§10 内容或"无偏差"]

请走查后回复：通过 / 打回（附反馈）

──────────────────────────────────────
⚙️ 可选深度审查（PM 自取所需，非必跑）：
  /review              — 代码审查 task 分支 vs req 分支的 diff
  /qa                  — 功能测试 dev server（需 browse；UI task 推荐）
  /design-review       — 对照 DESIGN.md 检查视觉一致性（需 browse；UI task 推荐）
跑完贴结论我会机械追加自审记录 + append 事件（I-RV3）。
═══════════════════════════════════════
```

**非 UI 类 task**：去掉「走查链接」段，加「📂 代码变更」段（关键 diff / 测试结果摘要），「⚙️ 可选深度审查」区块只列 `/review`（不含 `/qa` `/design-review`），其余结构同上。

## 11.3 走查时引导 PM 反推上游文档偏差

PM 看原型 / 看 diff 时若发现 brief / analysis / solution（PM 视图）/ prd / module 规格等上游文档写错，提醒 PM 在 task PM 视图「📁 历史档案 → 业务层偏差」表填一行（默认空，多数 task 不填）。close-task 调 `/doc-update` 时会扫这段 + 工程合同 §10，逐条确认改原文。

不要让 PM 只在对话里说偏差而不落表 —— 会丢。
