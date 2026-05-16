# P5-mini Benchmark 报告

**目的**：在投入 vp-01 → vp-12 实施序列前，验证 v3.2 方案"AI 输出 `(old, new)` patch 数组 + uniqueness 约束 + str.replace 应用"的可行性。

**日期**：2026-05-15
**用时**：~50 min（含用例构造 + verify.py + 8 次推理 + 报告）

---

## 1. 结果

```
P5-mini results: 8/8 pass (100%)
  ✓ case-01  patches=1  uniq_ok=1  overlap=0   (字段加约束 / 简单)
  ✓ case-02  patches=2  uniq_ok=2  overlap=0   (字段加约束 / 复杂：单位+范围+业务规则联动)
  ✓ case-03  patches=1  uniq_ok=1  overlap=0   (新增字段 / 简单)
  ✓ case-04  patches=2  uniq_ok=2  overlap=0   (新增 / 复杂：2 字段 + 业务规则补条)
  ✓ case-05  patches=1  uniq_ok=1  overlap=0   (删字段 / 简单)
  ✓ case-06  patches=2  uniq_ok=2  overlap=0   (删字段 / 复杂：枚举 + 业务规则联动)
  ✓ case-07  patches=1  uniq_ok=1  overlap=0   (改角色权限 / 简单)
  ✓ case-08  patches=1  uniq_ok=1  overlap=0   (改角色权限 / 复杂：角色拆分 + 别名保留)
```

**关键统计**：
- 首次成功率：**8/8 (100%)**
- 共生成 11 个 patch，0 个 uniqueness 失败、0 个重叠
- 0 次 retry（首次即 pass）
- 0 次进入兜底分支 (a/b/c)

---

## 2. 这个数字**不**等于真实使用成功率

必须老实说明：

### 2.1 合成偏差（最大偏差源）

- 8 个用例的 modulespec 是**我（同一个 LLM）现造的**，措辞风格、字段命名规范、空行处理都是同一套品味
- 答 patch JSON 的也是我，"心里有答案"（构造 expected 时已经想过最优 patch）
- 真实使用中：modulespec 是 PM 多月累积、`task-execute` 推 quickfix-log 时也用了不同语境，"出题方 ≠ 答题方"

**结论**：8/8 是**上界估计**。

### 2.2 modulespec 规模偏差

- 合成用例每个 modulespec **20-30 行**
- 真实 modulespec 估计 **100-300 行**，"必填" / "可选" / "格式" / "默认" 这类短语会**大量重复**
- → uniqueness 约束难度真实场景比合成高

**预期影响**：AI 首次 patch 可能因 old context 不够长导致 uniqueness 失败，但 3 次 retry 应该能补对（prompt 显式提示"加更多 context 行直至 old 在文件中唯一"）。

### 2.3 quickfix-log 措辞偏差

- 合成 quickfix-log 我写得很清晰："新增 discount 字段，可选，最长 20 字符"
- 真实 PM 手写的 quickfix-log 可能模糊："加个 discount"
- AI 需要从 commit diff **推**字段细节

**预期影响**：复杂场景 (case-04 / case-08) 的真实失败率会比合成更高。

---

## 3. 真实使用成功率的合理推测

| 维度 | 上界（合成） | 中位估计（真实） | 下界（恶劣场景） |
|---|---|---|---|
| 首次成功率 | 100% | **70-85%** | 50% |
| 3 次 retry 后成功率 | 100% | **88-95%** | 75% |
| 触发兜底 (a/b/c) 的频率 | 0% | **5-12%** | 25% |

v3.2 §6.1 门槛是"3 次 retry 内成功率 ≥ 85%"。**中位估计稳过，下界不过**。

---

## 4. 设计层发现（结构性的，独立于成功率）

跑下来对 v3.2 §3.3 / §5 / §10 附录 A 有几条调整建议：

### 4.1 prompt 必须显式提示"old 至少含 1 个 \n"

case-04 我自己差点写了"- 升级套餐立即生效，降级套餐在下一周期生效"作为 old，单行不含 \n，会被 verify.py 拒绝。**约束 2（"至少 1 行"）必须在 prompt 第一段显式写**，不能让 AI 凭直觉。

附录 A 的草稿 prompt 已经提到"≥ 1 个完整行（含 \n）"，需要在 vp-04 实现时强化为粗体 + few-shot 示例。

### 4.2 frontmatter 不能让 AI patch

case-01 我作为 AI 一开始想把 frontmatter 的 `last_modified_req` / `last_modified_commit` 也写成 patch，但这两值是**机械的、可程序计算的**。如果让 AI 输出 frontmatter patch：
- AI 可能写错 commit hash（要看 commit-diff.md 末尾的 context 段）
- 多一个失败点

→ verify.py 现在已实现"AI 输出 body patch、程序应用后再 rewrite frontmatter"。**v3.2 §3.1 / §4.2 / 附录 A 都需要明写这条**："AI patches 不要碰 frontmatter，frontmatter 由程序在 apply 后写"。

### 4.3 删除型 patch 的"末尾空行处理"是个坑

case-05 删 legacy_flag 段，old 要包含**段后那个空行 + 下一个 ###**之间的空行，否则删完会留多余空行。我写的：

```
old: "### legacy_flag\n- ...\n- ...\n\n"   ← 注意末尾 \n\n（含段后空行）
new: ""
```

如果 AI 写成 `old: "### legacy_flag\n- ...\n- ..."`（不含末尾空行），删完会留空行 → 不影响功能但 PM 审 diff 会看到无意义空行。

**建议**：prompt few-shot 加一个删除示例，明确教 AI 删整段时把段后空行一起 include。

### 4.4 verify.py 的"语义比对"局限

verify.py 用 `normalize` + 字符串相等比对。如果 AI 选择不同插入位置（例如 case-03 把 discount 插在 amount 之后而不是 status 之后），verify 会 fail —— 但语义其实等价。

**这是已知局限**：合成 benchmark 用例的 expected 是我钦定的，AI 走我没想到的合法路径会被误判。生产实现里 PM 是最终裁判（看 git diff），没有 expected。

→ 不影响本次"AI 能不能产出合法 patch"的判断，但 P5 全量 benchmark 要考虑"两个 expected 都算对"的 oracle 设计。

---

## 5. 决策

### 推荐：进 vp-01 实施序列，**但前置 P5 真实例补判**

**理由**：

1. **8/8 合成结果证明方案的"结构正确性"**：JSON 格式合法、uniqueness 约束可达、str.replace 应用可行、frontmatter 程序维护可行 —— 这些是**方案能不能成立的硬约束**，全部通过。

2. **真实成功率仍有 15-30% 不确定区间**：合成结果不能替代真实数据。但**这个不确定区间不影响开始实施**：
   - vp-01 / vp-02 / vp-03 / vp-05 / vp-07 这些任务**与 AI 准确率无关**（数据契约 / SKILL 骨架 / 锁 / 校验器 / apply 器）
   - 只有 vp-04（prompt）+ vp-06（retry）需要 AI 准确率信息

3. **建议节点**：
   - 现在：**进 vp-01 → vp-03**（4h，与 AI 无关的基础设施）
   - vp-04 写完 prompt 草稿后：**跑 P5 真实例补判**（PM 给 2-3 个真实 req → 单独窗口跑 patch，避免上下文污染）
   - 补判过线（3 次内 ≥ 85%）：继续 vp-05 → vp-12
   - 补判不过线：调 prompt 重跑；若 prompt 调到极限仍 < 85%，回头加 feature_id 锚定（部分 v3'.1 设计回归）

### 不推荐：直接全量铺开 vp-01 → vp-12

会在 AI 准确率未实测的情况下投入 vp-04 / vp-06 的实现，万一真实使用不达标，这两个 PR 要重做。

### 也不推荐：现在就跑 P5 全量（30 用例）

- 合成 30 用例不会比合成 8 用例多任何信息（同样的偏差）
- 真实 30 用例时间成本太大（PM 至少 1-2h 出数据 + 我跑 2h），且 vp-01-03 阶段不需要这个信息
- → 全量 benchmark 留到 vp-04 之后做"边写边验"

---

## 6. 附：用例难度自评

| Case | 难度（我作为 AI 答题时的认知负荷） | 卡点 |
|---|---|---|
| C01 | ★☆☆☆☆ | 无 |
| C02 | ★★★☆☆ | "元 → 分"是否要去掉"元"字 — 这是语义判断，不是机械改写 |
| C03 | ★★☆☆☆ | discount 插入位置选 status 后还是 amount 后 |
| C04 | ★★★☆☆ | promo_code 与 promo_discount_bps 顺序 / 业务规则 old 必须含 \n |
| C05 | ★★☆☆☆ | 删除段是否含段后空行 |
| C06 | ★★★☆☆ | 2 个 patch 都涉及 legacy_inapp 字符串，要保证不重叠 |
| C07 | ★☆☆☆☆ | 无 |
| C08 | ★★★★☆ | customer 拆分 + 弃用别名的措辞 — AI 可能直接删 customer 而不是保留为别名 |

**最大风险点**：C08 类的"语义改造"（不是字段微调，是结构重构）。真实使用中应该不常出现 —— PM 单人维护、变更增量小。

---

## 7. 下一步

1. ✓ P5-mini 报告完成
2. **进 vp-01**（quickfix-log 数据契约 + frontmatter 升级 schema，~0.5h）
3. **进 vp-02**（close-task SKILL：写 quickfix-log，不动 modulespec，~1.5h）
4. **进 vp-03**（close-req 入口锁，~1h）
5. **vp-04 完成后跑 P5 真实例补判**（PM 给 2-3 个真实 req）

按 vp 估时表，1-3 累计 4h，可以一鼓作气干完。
