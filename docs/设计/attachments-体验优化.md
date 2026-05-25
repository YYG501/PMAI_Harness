# D-iii：attachments 体验优化 (v0 stub)

> **状态**：草稿 v0 stub —— **§0 未共写**（D4 B 分组：3 D-* 中第 3 个；待 PM 共写 §0 后展开 §1+）
> **日期**：2026-05-24
> **作者**：PM + AI

---

## §0 原始痛点（**待 PM + AI 共写**）

### §0.1 痛点（待写）

**PM 表述（待 dig）**：
> "我会有很多附件"（本会话 2026-05-24）

PM 已确认 attachments 数量多，但具体卡点未澄清。

### §0.2 触发场景（待 PM 提供 EVIDENCE）

候选场景（待 PM 选 / 补充）：

| # | 候选场景 | EVIDENCE |
|---|---|---|
| 1 | 每个 stage 都重复问"要不要纳入"，烦；PM 期望一次表态多 stage 复用 | [TBD] |
| 2 | 没 sub-folder：brief / analysis / solution 附件混在同一目录；PM 期望 `attachments/brief/` / `attachments/solution/` 拆分 | [TBD] |
| 3 | AI 选取 / 优先级不准；PM 上传 10 份附件，AI 不知该优先读哪些 / 跳哪些 | [TBD] |
| 4 | 附件大小 / 类型限制不明；PRD / SDK PDF 常超 10MB，pre-commit hook warn | [TBD] |

→ **D5 (Round 2) 阶段 PM 中断 AUQ + clarify 后转重组讨论；具体卡点待回到本设计共写时落定**

### §0.3 根因（待写）

**初步假设**（v0 stub，**未锁定**）：

现仓 attachments 机制：
- 1 个 `$ACTIVE_REQ_DIR/attachments/` 目录跨 stage 共用（`docs/归档/完成/attachments-机制.md`）
- 每个 stage 的 PM 视图 SKILL（new-req / req-analysis / prd-writing / task-spec）有同款 hook：
  - 写产出前扫 attachments/ 目录
  - 命中新文件 → 问 PM「要不要纳入本 stage 参考？说明重点」
  - 写完后追加 `## 📎 参考材料` section

PM 觉得"附件多"不顺 = 这个 mechanism 在某些场景不够好用。具体哪个场景待 §0.1 / §0.2 共写。

### §0.4 不解决什么（待写）

候选（待 PM 选 / 补充）：

- ❓ 附件大小 / 类型限制改造（current pre-commit hook 已 warn，可能不需要本设计动）
- ❓ 附件版本管理 / 跨 req 共享（多 req 共享同份 SDK 文档）
- ❓ AI 自动 OCR / 解析 binary 附件（image / pdf 内容直接给 LLM）

---

## §1+ 方案主体（**待 §0 锁后展开**）

可能的方案候选（v0 stub，未拍）：

- **A sub-folder 分类**：`attachments/brief/` `attachments/solution/` `attachments/shared/` 等子目录；hook 按 stage 只扫对应子目录
- **B 附件级 metadata**：`attachments/.meta.json` 记每个附件的 priority / scope / 摘要；hook 不再每个 stage 重复问，按 metadata 决策
- **C "一次表态多 stage 复用"**：PM 第一次回答"要不要纳入"时记录决策到 metadata；后续 stage 同款附件不再问
- **D 优先级问句改造**：hook 一次性列出新附件 + 让 PM 标"必读 / 可选 / 跳过"，AI 按标签决策

→ 待 §0 锁后由 plan-eng-review 走

---

## §X Review Findings

（待 plan-eng-review 跑 D-iii 自己时填）

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-24 | v0 stub 创建（D4 Round 2 B 分组）| 等 §0 共写 |

---

**End of D-iii v0 stub**
