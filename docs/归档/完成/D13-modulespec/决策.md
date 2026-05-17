# ADR-D13: modulespec 维护方案 — close-task 不调 doc-update，close-req 末统一 rewrite

> **状态**：Accepted
> **日期**：2026-05-16（final 落地）
> **作者**：PM + AI
> **关联**：
> - 方案文档：[`docs/design/modulespec-重写方案.md`](../design/modulespec-重写方案.md)（D13 final，含 §0 痛点锁 + autoplan round 7 三 phase + 18 polish）
> - 决策路径归档：[`docs/design/prd-modulespec-重构.md`](../design/prd-modulespec-重构.md)（v2-v3.2 完整路径，§十七/十八/十九 已标作废）
> - 验证：[`docs/design/d13-验证脚本.md`](../design/d13-验证脚本.md)
> - Commits：c6d15d2 (vp-1) → 133c32d (vp-2) → 9f4389b (vp-3) → dc4cdc2 (RUNTIME 同步)

---

## 背景

**痛点**：每个 task close 都跑一遍 `/doc-update` settlement mode 把功能清单沉淀进 `modulespec.md` → **N 次 doc-update × 单次完整启动成本** = 真实 token 浪费 + PM 时间重复 + AI 工作重复。

PM 原话（2026-05-11，`prd-modulespec-重构.md` §12.1）：

> "不是 modulespec 有陈旧痕迹，而是 **token 浪费**。浪费来源 = N 次 doc-update × 单次完整成本（skill 指令加载 + modulespec 读 + PM 视图读 + AI 推理 + 写回）。"

**EVIDENCE**（ExampleConsumerApp dogfood 2026-05-16 实证扫）：

| req | task 数 | doc-update 启动次数 |
|---|---|---|
| req-001 | 2 | 2 |
| req-002 | 2 | 1（task-001 "无偏差 no-op" 也付完整启动成本）|
| req-003 | 5 | 3 |
| **合计** | **21 task** | **~19 次启动** |

启动成本 = SKILL 指令重载（~几 K token） + modulespec 全文读（几千行） + AI 推理 + PM 看 chat 输出。即使 task 偏差表是"无偏差 no-op"也付完整成本。

**根因**：`skills/close-task/SKILL.md` Phase 1 步骤 1 默认调 `/doc-update` settlement mode → 每 task 启动一次完整 doc-update SKILL 流程 → **启动成本 × task 数累加**。

**决策路径（5 版绕弯教训）**：v2 §12.2（最简正解 ~2h）→ v3 §十四（14-21h）→ v3' §十七（9-10h）→ v3'.1 §十九（30-38h）→ v3.2（12-15h）→ v3.3（3-4h）→ **回归 v2 §12.2（D13 final ~2h）**。教训：autoplan 评审默认不读现有 SKILL 实现会持续给设计加东西；PM 根因质疑（"难道不是因为 X 吗"）是回归正确方向最快路径。

## 决策

把 modulespec 维护从「每 task close 调一次」改成「close-req 末统一聚合 rewrite」。**N 次合并成 1 次**。

**vp-1**（`skills/close-task/SKILL.md`）：
- Phase 1 步骤 1 改成"不调 doc-update（永久；删 `--skip-doc-update` flag 整套）"
- 保留步骤 0 task md ↔ 原型对齐（polish-3）

**vp-2**（`skills/close-req/SKILL.md`）：
- 步骤 1.5 触发条件从"≥2 SKIP marker"改为"任何 task 关闭都默认聚合 rewrite"
- 单 task req 也调 doc-update rewrite mode
- 保留 PM 决议三选项（rewrite / patch / skip），默认 rewrite

**vp-3**：测试 + 文档同步 + 砍机制清单全套清账

**为什么不需要 overlay 文件 / patch JSON / sidecar metadata**：`skills/task-execute/SKILL.md:290` 步骤 2.1 已实现「同模块前 task PM 视图 + 工程合同两文件都读」。后续 task 不只读旧 modulespec，**还读同模块前面 task 的 PM 视图（含功能清单 + 业务偏差表）** → 前 task 改了什么会自动落进后续 task 视野，不需要新建中间表达。

**为什么不留 `--doc-update-now` override**：ExampleConsumerApp 实证 5 月时间窗里 PM 0 次"task close 时想立刻看 sediment"场景。保留 override 是"以防万一"的过度设计 → 代码维护两条路径 + 措辞冲突。删 override 后实现路径唯一，文档自洽。哪天真出现该诉求再加回不迟。

**否决的候选方向**：
- v3.x 的"按字段精确 patch + sentinel + sidecar JSON" → autoplan 评审漂移，30-38h，PM 根因质疑后砍
- "v1+v2 章节杂交防护机制" → §0.4 列入"不解决"（半 close 机制已存在覆盖）
- modulespec frontmatter `last_modified_req` metadata → 解决不了"v2 重做时真相源迁移"，属误诊

## 后果

**正向**：
- doc-update 启动次数：21 task ≈ 19 次 → **合并成 3 次**（每 req close 1 次 rewrite）
- token 节省可观测（下次跑真实 req 验证）
- close-task 流程显著简化（删半关闭机制 + SKIP marker + cleanup_status 整套）
- 测试基线 350 → 340（净删 10 个测试，全部正常归因：A1 skip-doc-update 6 个 + I-CT6 doc-diff 阻塞 1 个 + req-stage-gate half-close detection 1 个 + e2e/test-skip-doc-update-recovery.sh 2 个）

**砍掉的机制清单**（D13 final 全部已落）：
- `settlement mode` / `对账模式`（doc-update 不再被 close-task 调用）
- `--skip-doc-update` flag 整套（flag + reason + SKIP marker + cleanup_status + 人工 TODO 写入）
- `req-stage-gate` C2 half-close detection
- `doc-update §0.5` 沉淀风险判断

**doc-update 保留**：
- §8 rewrite mode（升为 close-req 默认调用路径）
- §1.7.3 多模块 atomic merge（rewrite mode 也依赖）

**代价 / 风险**：
- close-task 不再有"立刻看 modulespec 怎么变"能力（基于 PM 0 次诉求 EVIDENCE 决定不留逃生舱）
- close-req 单次 rewrite 工作量集中（vs 之前分摊到 N 次小 batch）；PM 一次审完整段 diff 时长更长
- 5 月时间窗 ExampleConsumerApp 实证 0 次"task 关闭时立刻 sediment"诉求；如果 PM 实际工作模式变化，本决策需重新评估

**触发重新评估的条件**：
- PM 出现"task close 时想立刻看 sediment"诉求 ≥ 1 次 → 加回 `--doc-update-now` override（参考 YAGNI 直到实证触发）
- close-req 末 rewrite 出现「大 batch 一次审太累 / 整段 rewrite diff 易看错」≥ 2 次 → 考虑加回 patch 模式作为 PM 决议三选项之一的默认
- doc-update rewrite mode 出现新的"启动成本累积"模式 → 重新审 D13 是否治标不治本

---

**End of ADR-D13**
