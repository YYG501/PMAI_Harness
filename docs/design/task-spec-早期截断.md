# 设计：task-spec 早期截断（防 task 双轮废）

> 状态：设计中（PM 走查后决定实施方向）
> 创建：2026-05-09
> 触发：DX 审计 P0-7（活体证据：req-001 task-003 v1+v2 双轮废）
> 决定项：实施方向（A / B / C / 不实施）+ 优先级

## 一、活体证据（不要绕过）

### 1.1 task-003 v1（2026-04-28 废弃）

- 范围：产品访问管理 → 产品详情页 → Tab 1 双视图 + 多证 Drawer + 双模态 Dialog
- 废弃理由：「task-003 实现整体质量很低」
- PM 反馈记录：仅 1 条（"/qa 没完整跑，找到 2 个 CRITICAL bug + 4 个 deferred"）
- 处理：代码 merge 进 req 保留底稿，但**不走 doc-update / 模块规格沉淀**；后续重做

### 1.2 task-003 v2（2026-05-06 废弃）

- 范围：与 v1 同（重做版）
- 实施详细度：
  - §🎯 关键产品决策 **18 项**（含每项当前选择 + 备选方案 + 共同理由）
  - §📐 产物预览 **175 行 ASCII 框图**（详情页布局 / 部门视图 / 许可证视图 / Drawer / 4 种弹窗 + 关键交互说明 8 条）
  - §📋 功能清单 **8 节**（树形列表 + Drawer + 4 种弹窗 + dangling + a11y）
  - GSTACK 全审：CEO / Eng（4 跑，6→8/10）/ Design（4 跑，7→9/10）= **CLEAN，0 unresolved**
  - VERDICT 摘录：「ENG + DESIGN CLEARED — active spec 通过架构 / 测试 / 视觉层全审查；可进入 task-confirm」
- 废弃理由：「重做后仍不满意」（一句话，无具体反馈）

### 1.3 PM 在 close-report.md §遗留问题 1 的反思

> task-003 范围（产品详情页 Tab 1 双视图 + 多证 Drawer + 双模态 Dialog）未正式验收完成，代码留在 main 上但缺 doc-update 和模块规格沉淀。**后续需要新 req 重新设计这块（建议从「租户管理员看许可证 → 部门额度的下钻路径」重新做信息架构）。**

PM 自己用「重新做信息架构」措辞，暗示问题不在实现细节，在拆分边界 / 信息架构层级。

## 二、续接 doc 初步方向 vs 真根因诊断

### 2.1 续接 doc 写的初步方向

> 根因（待验证）：task-spec 阶段写的工程合同 PM 看不出"做出来会长什么样"，要等 task-execute 跑完才能验收。
>
> 初步设计方向：
> - task-spec 写完 .engineering.md 后，强制要求 "PM 用一句话描述 demo 时会看到什么"
> - 与工程合同 .acceptance section 做 lint 对齐，不一致则不放行进 stage 6

### 2.2 这个根因和证据不一致

- v2 task-003 的 §📐 产物预览本身就是 175 行 ASCII 框图——已经超过"一句话 demo"的颗粒度，PM 完全看得见 demo 长什么样
- v2 task-003 过了 GSTACK Eng + Design 全审 8-9/10 PASS，0 unresolved——任何 review 角度的"看不见"都被填满
- 仍然废 → 看见的不是 demo 视觉，而是**整个范围 demo 起来太多**

如果根因真是"PM 看不见 demo"，加"一句话 demo 描述"对 task-003 的命运没影响——v2 PM 在 task-spec 阶段已经对着 175 行框图明确点了 task-confirm。

### 2.3 真根因诊断

**一个 task 包含 ≥3 段独立可 demo 的业务流时，PM 在 task-spec 阶段无法预判验收结果。**

task-003 v2 包含 6 段独立可 demo 业务流：
1. 部门视图 + 视图切换 segmented control
2. 许可证视图（同 schema 但根行结构不同）
3. 「额度明细 Drawer」（多证按证分组多 section）
4. 「分配额度弹窗」（多额度类型多 input + 实时预览）
5. 「取消分配弹窗」多证模式（multi-select + 连带预览）
6. 「取消分配弹窗」单证模式（直接预览）+ dangling / 失效证 UI

每段独立可在原型 demo 一段业务流。PM 走完 6 段会反馈 6 个不同方向的修订（部分相互矛盾）；PM 在 task-spec 阶段看 18 个决策也无法在脑子里跑 6 段 demo 的兼容性。

**反向佐证**：task-001（许可证仓库改造）+ task-002（产品列表 + Pool/Access 派生）每个只含 ~2 段业务流，都正常 close。

### 2.4 现有 task-plan 反模式覆盖盲区

task-plan/SKILL.md §2.2 已有反模式 A-E：
- A 纯前置 / B 横切质量 / C 共生对 / D 同文件串行 / E 模块归属

**没有反模式 F**：单 task 包含多段独立可 demo 业务流（"超粒度 task"）。

启发式 "单 req > 7 / 单模块 > 3 时审查" 没救 task-003：req-001 总 task = 3，单模块（产品访问管理）= 2 task，全在阈值内。

## 三、方向比较

### 方向 A：task-plan 阶段反模式扩容（事前防御）

**做什么**：
- 在 `skills/task-plan/SKILL.md` §2.2 加「反模式 F：超粒度 task」
- 判别启发式："列出 task 验收时需要 PM 在原型上 demo 的业务流条数；≥3 段 → 触发审查"
- 步骤 2.4 拆分后自检清单加第 6 项：「这个 task 验收时需要 PM demo 多少段独立业务流？≥3 段 → 回 §2.2 反模式 F 处理」

**收益**：
- 事前阻断 task-003 这种超粒度 task 进入 task-spec
- 一次拆对，不用走 task-spec → execute → 废弃 → 重做的循环（v1+v2 = 8 天浪费）

**成本**：
- task-plan 反模式扩容 + 反模式自检清单加一行（10 行 SKILL 改动）
- 模板 task-plan.md.tmpl §四 自检状态摘要加反模式 F 行
- 加测试用例（反模式 F 触发条件 + 拆分启发式）

**风险**：
- "≥3 段独立业务流"的判定本身需要 prose-as-judgment，不是机械计数（PM 续接 doc memory 里就警告过 "judgment 要 pattern 沉淀，不要机械化"）
- 部分 task 难以提前列出"段数"（如基础设施 task）

**证据契合度**：✅ 高 — 直接命中 task-003 的真根因（拆分粒度过大）

### 方向 B：task-spec 早期截断 demo 一句话（事后兜底）

**做什么**（PM 续接 doc 初步方向）：
- task-spec 写完后强制 PM 写"一句话描述 demo 时会看到什么"
- 与 §✅ 验收清单 / §📐 产物预览 做 lint 对齐
- 不对齐则不放行进 task-confirm

**收益**：
- 兜底机制，对方向 A 漏掉的超粒度 task 二次拦截
- 强制 PM 在 task-spec 阶段就把 demo 路径在脑里走一遍（思考触发器）

**成本**：
- task-spec/SKILL.md 加新步骤（已经 525 行）
- 模板 task.md.tmpl 加「demo 一句话」字段
- "lint 对齐"具体怎么实现：是 prose 对齐（AI 比对）还是结构对齐（grep 关键词）？前者不可靠 / 后者太脆

**风险**：
- task-003 v2 的 §📐 产物预览已经有 175 行 + §✅ 验收清单 + 关键交互说明——PM 即使再加一句话 demo，仍会写"详情页 Tab 1 看到双视图 / Drawer / 4 种弹窗"——这一句话本身没让 PM 改判，因为 PM 当时就同意做这么多
- "一句话 demo" 是症状层补丁，不阻断超粒度 task；只是给超粒度 task 多一层文档表面

**证据契合度**：⚠️ 低 — task-003 v2 已经过详细 spec + 全 review，再加一句话不能改命

### 方向 C：方向 A + B 都做（事前防御 + 事后兜底）

- 方向 A 阻断绝大多数超粒度 task 在 task-plan 阶段
- 方向 B 给方向 A 漏判的 case 二次兜底

**成本**：A + B 之和（约 1.5 天）

**风险**：
- "demo 一句话" 字段如果实施得粗（无 lint 对齐），变成 PM 例行复制粘贴的 boilerplate
- 双重保护可能让 PM 在 task-spec 阶段产生"已经审过了"的 false confidence

### 方向 D：不实施（保留续接 doc 待验证状态）

- 把 task-003 双轮废归因为 PM 该 req 信息架构本身不清晰，不是 framework 问题
- 现有反模式 A-E + 单 req 总数 > 7 启发式 + GSTACK 全审已经够用，不需要新机制
- 等下一次类似事故再决定（采样不足 N=1，过早泛化风险）

**风险**：N=1 的反例代价是 8 天浪费 + req close 时跳 prd-writing；下次再遇等不起。

## 四、推荐方向

**方向 A 单做（不做 B）**。理由：

1. 证据契合度：方向 A 命中真根因；方向 B 是症状层补丁
2. 成本：方向 A ≈ 1 天，方向 B ≈ 0.5 天但收益不明确
3. v3.5 已多次提示反模式（D 同文件串行 / E 模块归属硬规则）一加一个准；扩反模式 F 是同模式
4. 方向 B 的 "lint 对齐" 实现路径不清晰，容易做成 boilerplate 字段
5. memory feedback "judgment 要 pattern 沉淀，不要机械化"——方向 A 的 ≥3 段判定要写成 prose pattern + 触发条件 + 决策模板，不写成阈值脚本

**例外情况**：如果 PM 觉得方向 A 的"段数计数"太主观，希望加机械兜底，那再做方向 B 当 backup（方向 C）。

## 五、方向 A 实施细节（PM 选 A 后再展开）

### 5.1 task-plan/SKILL.md §2.2 加反模式 F

```markdown
**反模式 F：超粒度 task（一个 task 含 ≥3 段独立可 demo 业务流）**

> 例：task-003 包含 ① 部门视图树形 ② 许可证视图树形 ③ 多证 Drawer
> ④ 分配额度弹窗 ⑤ 取消分配多证弹窗 ⑥ 取消分配单证弹窗 — 6 段独立业务流。

- 问题：单 task 验收时 PM 需在原型上 demo 多段业务流；多段 demo 间反馈方向相互
  影响 / 矛盾 → PM 修订决策易于在 task-execute 反馈循环里反复推翻 → 实证常见
  双轮废（task-003 v1+v2 双废，8 天浪费）
- 判断（prose pattern，不机械化）：
  - 列出 task 验收时 PM 需要在原型上 demo 的"独立业务流"条数（一个业务流 = 一组
    场景 1-2 步内完成的 user story；不同 entry / 不同 dialog / 不同 view 切换
    分别独立计）
  - **≥3 段 → 触发拆分审查**：默认按 user story 链条切成 sub-task；如有强依赖
    无法拆，必须在 task-plan §四 自检与状态摘要的反模式 F 行写"为什么不拆 +
    PM 验收方案"
  - **=2 段 → 边界情况**：如果两段在视觉上 / 数据上紧耦合（例如同 page 双视图
    切换共用 schema），允许合一个 task；否则拆
  - **≤1 段 → 默认通过**

**判别启发式**（用 §📐 产物预览 + §✅ 验收清单 反推）：
- 一个 task 的 §📐 产物预览 ASCII 框图数 > 3 个独立 view（含 dialog / drawer）
- 一个 task 的 §✅ 验收清单分组超过 5 个（如"主路径 / 边界路径 / 文案 / 视觉与
  可访问性 / Tab 切换 / dangling / 失效 ..."）
- 任一命中 → 强烈怀疑反模式 F，回头按本节判断重新拆
```

### 5.2 task-plan/SKILL.md §2.4 拆分后自检加第 6 项

```markdown
6. [ ] 这个 task 验收时需要 PM demo 多少段独立业务流？
   - 列出每段（"进 Tab 1 看双视图 / 点行钻取 Drawer / 分配额度 / ..."）
   - ≥3 段 → 反模式 F → 回 §2.2 处理（默认拆 sub-task；除非写明 PM 验收方案）
```

### 5.3 模板 task-plan.md.tmpl §四 加反模式 F 行

```markdown
| F | 超粒度 task | [未命中 / 命中（已处理）] | [命中时一句话拆分结论] |
```

### 5.4 测试用例

- `tests/test-task-plan.sh` 加：反模式 F 描述、判别启发式、自检第 6 项关键词
- 模板测试加：§四 自检状态摘要含反模式 F 行

### 5.5 文档更新

- 续接 doc 标 P0-7 完成 + commit hash
- skill-improve SKILL 加一句"反模式扩容是常见 skill 改进路径"作 reference

## 六、PM 决策表

| 决策项 | 选项 |
|---|---|
| **方向** | A 单做（推荐）/ B 单做 / A+B 都做 / D 不实施 |
| **如选 A**：判别 ≥3 段是 prose pattern 还是机械计数？| 默认 prose pattern（沉淀触发条件 + 决策模板）/ 备选机械（按 §📐 框图数 / §✅ 分组数）|
| **如选 A**：实施 commit 拆几个？| 单 commit（推荐）/ 拆 2 个（反模式扩容 / 测试用例 + 模板）|
| **如选 A**：是否回头给 task-003 v2 补一份反模式 F 复盘 evidence？| 写 `skill-feedback/task-plan-2026-05-09.md`（推荐）/ 不写 |

## 七、不在本设计范围

- task-spec 步骤本身的优化（已在 v3.5 ea2dc82 拆 references 后稳定）
- task-execute 反馈循环规则（已在 v4.5f 稳定）
- task-confirm 校验（不改动）
- close-task §0 task md / 原型对齐（已在 v4.5 落地）
