# ADR Index

> 本目录存放 PMAI framework 的单点决策记录（Architecture Decision Records）。
>
> **用途**：记录"为什么砍了 X / 为什么选 A 不选 B"这类单点决策，让 future-self 接续时不用 grep 半天。
>
> **不是什么**：
> - 不是大改 / 多 vp 方案 → 走 `docs/design/*.md`（按 [`_TEMPLATE-design-doc.md`](../design/_TEMPLATE-design-doc.md)，完整 §0-§7 结构）
> - 不是运行时状态 → 走 [`RUNTIME.md`](../../RUNTIME.md)（项目章程 / 当前位置 / 测试基线）
> - 不是 TODO 清单 → 走 [`TODOS.md`](../../TODOS.md)
>
> **服务对象**：主仓 framework 开发者（PM + AI）；**不进消费仓同步 SOP**，不给消费仓用

---

## 命名约定

- 文件名：`ADR-D<N>.md` 直接复用 D 编号（D-编号定义在 RUNTIME.md / docs/design/ 各设计文档里）
- 新建：`cp ADR-TEMPLATE.md ADR-D<N>.md` → 填模板 → 在本 INDEX 加一行

---

## 已有 ADR

| D 编号 | 标题 | 状态 | 落地日期 |
|---|---|---|---|
| [D13](./ADR-D13.md) | modulespec 维护方案 — close-task 不调 doc-update，close-req 末统一 rewrite | Accepted | 2026-05-16 |

---

## 历史决策未回填说明

**D1-D12 / D14-D15 + `docs/archive/design/` 21 份废稿未批量回填到 ADR 格式**。

理由（autoplan v2 CEO consensus + DX finding）：
- 真痛点 EVIDENCE 只举 D13 一条（PM 查 D13 "为什么砍 stage 5/6/7/8/9" 要翻 3 处）
- 机械回填 D2-D14 + archive 21 份 6 个月后大部分没人查 → 治理幻觉
- 跟 `docs/archive/design/` 21 份废稿处理一致：**触发式补**

**查不到决策根因时**：
1. 先 grep `docs/design/` 现役 5 份设计文档
2. 再 grep [`docs/archive/design/`](../archive/design/) 21 份历史归档
3. 再 grep `RUNTIME.md` / `TODOS.md` 散落决策
4. 找到对应决策后，**为该决策补一份 ADR**（按 ADR-D<N> 命名），加到本 INDEX 表

---

## 决策记录的 4 个容器（边界）

| 容器 | 何时用 |
|---|---|
| `docs/adr/ADR-D<N>.md`（本目录）| 单点决策 / 砍了 X / 选 A 不选 B / 1 页 4 段 |
| `docs/design/<feature>.md`（按 `_TEMPLATE-design-doc.md`）| 大改 / 多 vp / 需要 §0 痛点锁防 review 膨胀 |
| `RUNTIME.md` | 项目章程 + 当前位置 + 测试基线 + 最近活动 |
| `TODOS.md` | 延迟项 / TD-X 清单 / 触发条件 |

新决策按规模选容器；不要重复写 4 处。
