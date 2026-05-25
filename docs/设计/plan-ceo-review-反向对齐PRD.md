# D-ii：plan-ceo-review 反向对齐 PRD 集成 (v0 stub)

> **状态**：草稿 v0 stub —— **§0 未共写**（D4 B 分组：3 D-* 中第 2 个；待 PM 共写 §0 后展开 §1+）
> **日期**：2026-05-24
> **作者**：PM + AI

---

## §0 原始痛点（**待 PM + AI 共写**）

### §0.1 痛点（待写）

**PM 表述（待 dig）**：
> "我确实会使用 ceoplan 来审核 prd"（本会话 2026-05-24）

PM 已确认有用 `/plan-ceo-review` 审 PRD 的行为，但具体卡点未澄清。

### §0.2 触发场景（待 PM 提供 EVIDENCE）

候选场景（待 PM 选 / 补充）：

| # | 候选场景 | EVIDENCE |
|---|---|---|
| 1 | Stage 3 PM 看到推荐 review 名单，但仍要手动打 `/plan-ceo-review`，不顺 | [TBD] |
| 2 | review 结论反向回填 PRD 无机制；PM 看完 review 还得手改 PRD | [TBD] |
| 3 | review 发现重大问题 → PRD 要回 stage 3 重做 / 闸门没强制 | [TBD] |
| 4 | ceoplan 是 CEO 视角，跟 prd-writing 默认产出风格冲突 | [TBD] |

→ **D5 (Round 2) 阶段 PM 中断 AUQ + clarify 后转重组讨论；具体卡点待回到本设计共写时落定**

### §0.3 根因（待写）

**初步假设**（v0 stub，**未锁定**）：

`/plan-ceo-review` 是 PM 自跑 review 工具，现仓 I-RV1 / I-RV2 边界规定：
- review 工具 PM 自跑、AI 不自动调
- 事件流 (`task-events.py append plan_review_completed`) 仅作审计、不当 gate
- review 结论反向回填 PRD 无机制

PM 觉得有问题 = 这个边界可能在某些场景不够好用。具体哪个场景待 §0.1 / §0.2 共写。

### §0.4 不解决什么（待写）

候选（待 PM 选 / 补充）：

- ❓ `/plan-ceo-review` 自动跑（强行调起）—— 违反 I-RV1 边界
- ❓ review 结论作 Stage 3 → 4 推进闸门（强 gate）—— 违反 I-RV2 边界
- ❓ 跨 PRD / review 实时同步（看完 review 立刻 update PRD）

→ 这些是**架构红线**还是**待挑战的限制**，待 PM 共写时拍。

---

## §1+ 方案主体（**待 §0 锁后展开**）

可能的方案候选（v0 stub，未拍）：

- **A 入口便捷化**：Stage 3 确认门展示推荐 + 提供"现在跳过去跑 X"的 chat 短链（不是自动调起，是更顺的 manual prompt）
- **B 反向回填机制**：PM 自跑 ceoplan 后，AI 提示 "结论有几条要回填 PRD，要不要 inline 改"
- **C 软闸门**：review NEEDS_REVISION 时 stage 3→4 推进确认门多一行 warning（PM 仍可推进，不是 hard gate）
- **D 跟 v3 体验包装层复用**：把"还要不要再讨论一轮 PRD"作为 Stage 3 → 4 的体验包装层入口（PM 视角"discuss PRD"），AI 后台跑 ceoplan / 不跑

→ 待 §0 锁后由 plan-eng-review 走

---

## §X Review Findings

（待 plan-eng-review 跑 D-ii 自己时填）

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-24 | v0 stub 创建（D4 Round 2 B 分组）| 等 §0 共写 |

---

**End of D-ii v0 stub**
