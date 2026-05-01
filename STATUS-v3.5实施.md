# v3.5 实施进度

> **新窗口续接入口**。读完此文档即可知道当前位置 + 下一步。
> 维护约定：每完成一阶段更新本文件（~10 秒）。

---

## 当前位置（2026-05-01）

阶段 **1+2+3a 完成**：

```
（本次新增）
            feat(fixture-v2): 双文件 v2 fixture + 7 smoke 测试
（前序，已落 main）
88bcc6e     fix(parser-migrate): 4 处剩余解析点迁移到 _lib.task_parser
dc848d9     fix(task-transition): 用 read_section 跨文件查找替换旧 regex
2c9ec03     feat(parser): shared task parser v1/v2 双兼容 + 25 单测覆盖
97f8d61     docs(plan): v3.5 实施计划与设计文档族 + 四轮 review 沉淀
d131557     feat(task-execute): run-bg.sh watchdog + stall 检测协议升级
```

**修复 4 个 P0/P1 bug** + parser 基础设施 + v2 fixture + 总测试 **177 通过 / 21 baseline 失败**（与 3a 改动无关）。

| Bug | 状态 |
|---|---|
| P0-1 task 卡在「执行中→待验收」 | ✅ 已修 |
| P0-2 hook 不识别新格式状态值 | ✅ 已修 |
| P0-3 close-req / cancel-req 漏新格式 task | ✅ 已修 |
| P1-5 build-execution-prompt 拿错 worktree | ✅ 已修 |
| P1-7 fixture 还用旧单文件 | ⏸ 阶段 3 |

---

## 下一步：阶段 3b（21 条 baseline 失败修复）

⚠️ **STATUS 之前对阶段 3 框架描述有误**。实查后：5 个失败 suite **没一个调用 fixture**，21 条失败本质是 **test grep 字符串 vs SKILL.md / 模板内容漂移**。3a（fixture v2）单独完成、独立无副作用，已落本次 commit。3b 是单独的逐条修复工作，与 fixture 无关。

### 3a 已完成
- `fixture_create_task_v2`（双文件，PM 视图表格 + `.engineering.md` §10/§11）
- 旧 `fixture_create_task` 保留作 v1（双轨直到双模式上线后清理；见 TODOS Q3）
- `tests/test-fixture-v2.sh` 7 条 smoke：detect_format / get_status / get_branch / read_section §10+§11 / task-transition 端到端 → 全绿
- 注册到 `run-all.sh`

### 3b 待做（5 个 suite × 21 条失败）

每条要二选：**test 字符串过期**（更新 test）/ **SKILL 真丢规格**（回退或补回 SKILL）。**禁止用 grep 改 SKILL 把真规格删了**。

| Suite | 失败数 | 表面失败模式 |
|---|---|---|
| `test-task-spec.sh` | 8 | 找不到「用户使用流程」/「步骤 6.5」等 section；找不到旧字段 `**所属模块：**`（已改 v2 表格） |
| `test-task-plan.sh` | 7 | 步骤号偏移（`步骤 3` → 现在是 `步骤 2`，多了 step 0）|
| `test-doc-update.sh` | 3 | 找旧 inline 字段 `**所属模块：**` / `**所属模块章节：**`；找不到 Batch 3 TODO marker |
| `test-task-pm-feedback.sh` | 1 | 找不到 `改 task.md`（措辞已变） |
| `e2e/test-full-task-loop.sh` | 2 | 措辞漂移（`Stage 5 只写 task-plan.md` 等）|

**新窗口验证基线**：`bash tests/run-all.sh` → 应看到 177 / 21（如不一致先排查）。

**估时**：1-2 小时，逐条决策，不能批量 sed。

---

---

## 实施中发现的坑（spot-check 没预料到，避免新窗口重新踩）

### 坑 1：task-transition.py 已有 v1/v2 字段解析（line 16-30）

阶段 1 不需要替换字段解析层，**只迁移 section 检查段**。改动比 plan 估的小。

### 坑 2：`---` 作 section 终结符

fixture 用 `---` 分隔 section（不是 `## ` heading）。原 `_extract_section` 只识别 `## ` 终结，**不识别 `---`**——导致 section 内容溢出到下一段。

修复：`_extract_section` 的 next_m 正则加 `^---+\s*$`：

```python
next_m = re.search(r"^(##\s+|-{3,}\s*$)", text[start:], re.MULTILINE)
```

加 2 个测试覆盖（`test_section_terminated_by_horizontal_rule` + `test_empty_section_terminated_by_hr_returns_empty`）。

### 坑 3：空 cell 返回 None vs 空字符串

V2 regex 会匹配只含空格的 cell（`| **状态** | |`），strip 后返回 `''`。caller 期望 None。

修复：`parse_field` 末尾 `value if value else None`。

---

## 文档导航（按读取顺序）

| 顺序 | 文档 | 作用 |
|---|---|---|
| 1 | 本文件 `STATUS-v3.5实施.md` | 当前进度（你现在读的）|
| 2 | `CLAUDE.md` | 项目章程 |
| 3 | `实施计划-实现程度与格式对齐.md` | 9 阶段计划（v3.5 / 7.3-10.2 天 / 含四轮 review 沉淀）|
| 4 | `阶段1-动手plan-parser-task-transition迁移.md` | 阶段 1 已完成（参考实施风格）|
| 5 | `设计-新两文件格式对齐.md` | 阶段 1-3 设计源 |
| 6 | `TODOS.md` | 4 项 v3.5 延迟决策（TD-1/2/3/4）|
| 7（废弃，不用读）| `设计-原型与系统双模式.md` / `实施计划-双模式与格式对齐.md` | 历史决策审计，不复用 |

---

## 新窗口续接命令

PM 在新窗口第一条消息：

> 继续 PM-AI-Workflow v3.5 实施。读 STATUS-v3.5实施.md 看当前进度，下一步阶段 3。

AI 收到后应该：
1. 读本文件
2. 读 `实施计划-实现程度与格式对齐.md` 阶段 3 段
3. 读 `设计-新两文件格式对齐.md` §四 4.3
4. 等 PM 确认开始（不擅自动手）

---

## 实施速度参考

| 阶段 | Plan 估时 | 实测 | 加速 |
|---|---|---|---|
| 阶段 1 | 1 天 | ~30 分钟 | ~16x |
| 阶段 2 | 0.5-1 天 | ~10 分钟 | ~30x |
| 阶段 3a | — | ~20 分钟 | — |
| 阶段 3b | 0.5 天 | 预期 1-2 小时 | ~3-4x |

加速原因：
- plan 详细到 API 签名 + 单测用例 + diff 草案
- 单测先写完整再实施 → 反馈快速
- spot-check 提前抓坑（25 个测试用例，第一次跑 24 过 + 1 fail，10 秒看到根因）

但 9 阶段累加后总耗时仍可能在 plan 范围内（**不要在 plan-eng-review 阶段就放飞乐观**）—— 后期阶段可能更复杂。

---

## 阶段进度表

| 阶段 | 内容 | 状态 |
|---|---|---|
| 1 | parser + task-transition 迁移 | ✅ 完成 |
| 2 | 4 处剩余解析点迁移 | ✅ 完成 |
| 3a | fixture v2（make_task_v2 + 7 smoke）| ✅ 完成 |
| 3b | 21 条 baseline 失败逐条修 | ⏸ 下一步 |
| 4 | worktree 文档同步（git show 绕 index）| ⏸ |
| 4.5 | 项目级工程结构约束（探测档）| ⏸ |
| 5 | 实现程度三阶段流程 | ⏸ |
| 6 | task-plan 按字段拆（Python 决策表）| ⏸ |
| 7 | task-spec 双源改造 | ⏸ |
| 8 | 格式统一前置 + 校验 + stale | ⏸ |
| 9 | PM 可见度（req-status + STATUS.md）| ⏸ |
