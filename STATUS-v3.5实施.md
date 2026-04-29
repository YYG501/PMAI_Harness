# v3.5 实施进度

> **新窗口续接入口**。读完此文档即可知道当前位置 + 下一步。
> 维护约定：每完成一阶段更新本文件（~10 秒）。

---

## 当前位置（2026-04-29）

阶段 **1+2 完成**，5 commits 落 main：

```
88bcc6e  fix(parser-migrate): 4 处剩余解析点迁移到 _lib.task_parser
dc848d9  fix(task-transition): 用 read_section 跨文件查找替换旧 regex
2c9ec03  feat(parser): shared task parser v1/v2 双兼容 + 25 单测覆盖
97f8d61  docs(plan): v3.5 实施计划与设计文档族 + 四轮 review 沉淀
d131557  feat(task-execute): run-bg.sh watchdog + stall 检测协议升级
```

**修复 4 个 P0/P1 bug** + 建立 parser 基础设施 + **27 单测**就位。工作区干净。

| Bug | 状态 |
|---|---|
| P0-1 task 卡在「执行中→待验收」 | ✅ 已修 |
| P0-2 hook 不识别新格式状态值 | ✅ 已修 |
| P0-3 close-req / cancel-req 漏新格式 task | ✅ 已修 |
| P1-5 build-execution-prompt 拿错 worktree | ✅ 已修 |
| P1-7 fixture 还用旧单文件 | ⏸ 阶段 3 |

---

## 下一步：阶段 3（fixture v2 重写）

详见：`实施计划-实现程度与格式对齐.md` 阶段 3 + `设计-新两文件格式对齐.md` §四 4.3

预期工作：
- `tests/helpers/fixture.sh` 加 `make_task_v2`（生成 PM 视图 + .engineering.md 工程合同双文件）
- 保留 `make_task_v1` 作 parser 双兼容性测试
- 改 5 个 baseline 失败 suite 用 v2 fixture
- 修复 P1-7（fixture 与新模板对齐）

**估时**：plan 0.5 天 / 实测预期 ~15-30 分钟（按阶段 1+2 的 ~16-30x 加速）

---

## 5 个 baseline 失败 suite（已知，留给阶段 3）

这些与阶段 1+2 改动无关，是 fixture vs skill 模板版本错配：

- `tests/test-task-spec.sh`
- `tests/test-task-pm-feedback.sh`
- `tests/test-task-plan.sh`
- `tests/test-doc-update.sh`
- `tests/e2e/test-full-task-loop.sh`

**新窗口验证 baseline**：
```bash
git stash --include-untracked  # 暂存当前 wip
bash tests/test-task-spec.sh  # 应该同样失败 → 确认是 baseline
git stash pop
```

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
| 阶段 3 | 0.5 天 | 预期 15-30 分钟 | ~10-30x |

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
| 3 | fixture v2 重写 | ⏸ 下一步 |
| 4 | worktree 文档同步（git show 绕 index）| ⏸ |
| 4.5 | 项目级工程结构约束（探测档）| ⏸ |
| 5 | 实现程度三阶段流程 | ⏸ |
| 6 | task-plan 按字段拆（Python 决策表）| ⏸ |
| 7 | task-spec 双源改造 | ⏸ |
| 8 | 格式统一前置 + 校验 + stale | ⏸ |
| 9 | PM 可见度（req-status + STATUS.md）| ⏸ |
