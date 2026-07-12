<!-- 共享方法论 · 一致性扫描（设计依据 / build target / landed truth 对账）。
     被 /pmai-design 与统一 finalize 调用；/pmai-build-close 仅在兼容恢复时复用同一逻辑。
     目标：不静默吞掉规格，也不把每个机械差异都升级成 PM 问题。 -->

# 共享方法论：一致性扫描

设计依据、build target 和正式文档会漂移：实现可能漏掉已确认规则，文档也可能漏掉已经落地主线的页面或状态。这份扫描把三者重新对齐，**不静默吞、不盲目重写**。

它不是第二条工作流。design 收口时做轻量扫描；PM 定稿后的最终检查和 landed 后文档编译按同一套口径执行。机械缺口自动处理，只有产品模型岔路、不可逆动作或要改变 PM 已确认方向时才打断 PM。

---

## 什么时候扫

- **design 决定闭合** → 对 `spec.md`、决定、相关页面 / 源码证据和项目底座做轻量对账，再提交建造依据。
- **build 迭代产生已接受变化** → 记入 `accepted_deltas`、递增 `design_revision` 并使旧证据失效；此时不提前改正式文档。
- **PM 定稿进入 final_check** → 对最终 commit 与 approved source、accepted deltas 做完整目标适配检查。
- **实现进入 main** → 基于 landed diff 和文档影响地图更新正式文档；文档失败保留 `landed/docs_pending`，只续跑文档。

简单到一两行的小改、纯文案错字，不用每次都扫——AI 临场判断改动是否触及字段 / 规则 / 概念 / 状态，触及了才扫。

---

## 怎么扫（三步）

### 第一步 · 定位改动点

从 context pack、landed diff 或当前设计改动中列出扫描锚点：对象、动作、状态、权限、页面、术语和规则。

### 第二步 · grep 相关文档

拿锚点去规范性来源、build target 和文档落点里搜：

- **规格** `docs/modules/<模块>/spec.md` —— 最终目标要求如何定义？
- **build target**：合同 `target.paths` 与 `project.yml` 入口对应的源码 / 接口 / 数据层 —— 最终 commit 实际实现了什么？
- **DESIGN.md** —— 涉及视觉 / 组件的，DESIGN 里的约定还对得上吗？
- **术语表** `PRODUCT.md` 业务术语表 —— 改了某个词，有没有近义词散落各处该统一？

可以借框架现成脚本辅助（都是 advisory、`|| true`，不阻塞）：

```bash
# 索引漂移：docs/ 实存文档 vs docs/INDEX.md（顶层文档漏挂）
python3 "$PMAI_HOME/scripts/check-state-index-drift.py" "$REPO_ROOT" || true
```

脚本只覆盖机械可查部分；设计依据、实现和文档之间的语义对账仍靠 AI 搜索、阅读与验收证据。

### 第三步 · 按决定类型处理

每处不一致按共用 `decision-policy` 分类：

1. **机械缺口**：索引漏挂、术语漏同步、已落地页面缺文档落点 → 自动修并在影响地图标记 covered。
2. **实现偏离已批准依据**：没有 accepted delta 支撑 → final_check 失败，回 `iterating` 补实现或回 design 重新拍板；不得拿实现反改规格掩盖问题。
3. **已接受变化**：有明确 PM 证据 → 写 `accepted_deltas`，更新 source hash / revision，旧验收证据失效；实现落地主线后再统一编译文档。
4. **真实产品模型冲突**：两个现行规则无法同时成立，或需要推翻 PM 已确认方向 → 说明冲突依据并立即让 PM 拍板。

需要 PM 决策时用业务语言，不出内部状态词。例：

```
对了一下已确认规则和最终结果，有一处会改变产品含义，需要你定：

1. 已确认规则是“额度超限时拦截并说明原因”，最终结果只有通用报错。是补齐说明，还是确认规则改为通用报错？
```

---

## 四、统一 finalize 的两次对账

### 4.1 final_check：先验证，再落地主线

- 逐项核对 approved source、accepted deltas 与最终 commit；
- prototype 走任务路径、页面 / 弹窗、状态、视觉和交互验收；product 走仓库测试、类型 / 构建、接口 / 数据和风险适配检查；
- 已确认条款在 build target 中找不到时，不删规格：没有 accepted delta 就回 `iterating`；需要改产品模型则回 design；
- 完整 required checks 通过且证据绑定当前 source hash 与 implementation commit，才进入 landing。

### 4.2 landed：只编译 main 已有事实

- 从 main 的 landed diff、build contract、accepted deltas 和验收证据生成文档影响地图；
- `spec-writing` 用“落地主线后的目标对账”模式分类实现差异；
- 每个新增或改变的对象、动作、状态、权限、页面、术语都有 covered 或带理由的 no-change；
- `spec.md` 只保留当前有效的最终目标，历史留在 Git 与 `decisions.md`；
- build target 与规格不一致时先分类：符合、accepted delta、实现遗漏、无依据实现；只有 accepted delta 可以改变规格目标；
- 文档失败只记录 `landed/docs_pending`，不回滚或重复 merge。

---

## 边界（守红线）

- **不形成第二条流程**：design 与 build/finalize 内部调用，不要求 PM 手动运行扫描或 close。
- **不把每个 finding 都抛给 PM**：机械项自动处理；只有真实产品模型岔路、one-way door 或改变 PM 明确方向才打断。
- **不拿实现覆盖决定**：build target 缺少已确认条款时先判漏实现或 accepted delta，绝不静默删规格。
- **不提前写正式文档**：iterating 期间只更新合同与证据；正式文档只在 landed 后编译。
