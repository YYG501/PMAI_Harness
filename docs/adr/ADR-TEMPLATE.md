<!--
# 本仓 ADR 模板
#
# 用法：
#   cp docs/adr/ADR-TEMPLATE.md docs/adr/ADR-D<N>.md
#   把 <尖括号占位符> 全部填掉
#   到 docs/adr/INDEX.md 加一行索引
#
# 命名约定：
#   ADR-D<N>.md  ← 直接复用 D 编号（不另起 ADR-NNNN）
#   D-编号定义在 RUNTIME.md / docs/design/ 各设计文档里
#
# 何时用 ADR vs D-* 设计文档：
#   - D-* 设计文档（docs/design/*.md）：大改 / 多 vp / 需要 §0 痛点锁防 review 膨胀 → 完整 §0-§7 结构
#   - ADR（本目录）：单点决策 / 记录"为什么砍了 X / 选 A 不选 B" → 1 页 4 段
#
# 为什么有 ADR：见 docs/design/gsd-借鉴-实施方案.md §1 #1
-->

# ADR-D<N>: <决策标题（简短一行）>

> **状态**：Accepted / Superseded by ADR-D<X> / Deprecated
> **日期**：<YYYY-MM-DD>
> **作者**：PM + AI
> **关联**：<原 design 文档路径 / 关联 D-编号 / commits / 等>

---

## 背景

<当时面对什么问题；为什么需要做这个决定；有哪些约束。1-3 段散文，PM + AI 都能读懂。>

<必要时引用：>
- 相关 commit：`<short-hash>`
- 相关 req：`requirements/active/<req-id>/`
- 相关 design：`docs/design/<file>.md`

## 决策

<最终决定怎么做。1-2 段。简洁、可执行。>

<如果有候选方案被否决，列出：>
- 否决 A：<原因>
- 否决 B：<原因>

## 后果

**正向**：
- <好处 1>
- <好处 2>

**代价 / 风险**：
- <代价 1>
- <代价 2>

**触发重新评估的条件**（什么时候这个决定应被推翻）：
- <条件 1>

---

**End of ADR-D<N>**
