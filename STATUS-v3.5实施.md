# v3.5 实施进度

> **新窗口续接入口**。读完此文档即可知道当前位置 + 下一步。
> 维护约定：每完成一阶段更新本文件（~10 秒）。

---

## 当前位置（2026-05-01）

阶段 **1 + 2 + 3 + 4 + 4.5a 完成**，全测试套件 0 失败：

```
（本次新增）
            feat(structure-schema): 工程结构约束 schema + derive 派生 + CLAUDE.md.tmpl 加段（4.5a 框架）
092eb72     feat(sync-req-docs): worktree 文档同步（git show 绕 index）+ check-task-scope implicit deny
（前序，已落 main）
dc85ba3     test(baseline-21): 21 条 test 字符串对齐 v3.5 SKILL/template 演化
74dc53f     feat(fixture-v2): 双文件 v2 fixture + 7 smoke 测试
88bcc6e     fix(parser-migrate): 4 处剩余解析点迁移到 _lib.task_parser
dc848d9     fix(task-transition): 用 read_section 跨文件查找替换旧 regex
2c9ec03     feat(parser): shared task parser v1/v2 双兼容 + 25 单测覆盖
97f8d61     docs(plan): v3.5 实施计划与设计文档族 + 四轮 review 沉淀
d131557     feat(task-execute): run-bg.sh watchdog + stall 检测协议升级
```

修复 4 个 P0/P1 bug + parser 基础设施 + v2 fixture + test/SKILL 全对齐 +
worktree 文档同步（git show 绕 index）+ check-task-scope implicit deny +
工程结构约束 schema 框架（4.5a）。总测试 **218 通过 / 0 失败**。

| Bug | 状态 |
|---|---|
| P0-1 task 卡在「执行中→待验收」 | ✅ 已修 |
| P0-2 hook 不识别新格式状态值 | ✅ 已修 |
| P0-3 close-req / cancel-req 漏新格式 task | ✅ 已修 |
| P1-5 build-execution-prompt 拿错 worktree | ✅ 已修 |
| P1-7 fixture 还用旧单文件 | ⏸ 阶段 3 |

---

## 下一步：阶段 4.5b（detect-project-structure.py + framework 第三档）

详见：`实施计划-实现程度与格式对齐.md` 阶段 4.5（行 153 起）；4.5 整体已拆 a/b/c。

### 阶段 4.5a 已完成（schema 框架）
- `templates/工程结构约束.schema.json`（plan 用 yaml；改 json 是为了保 zero-dep——PyYAML 不在 stdlib，结构等价）
- `scripts/derive-structure-templates.py`：schema → 两份派生 markdown 模板；含 `--check` 模式做 golden 校验（CI / 测试用）
- `templates/工程结构约束-prototype.md` + `工程结构约束-system.md`（派生产物，含 AUTO-GENERATED marker）
- `templates/CLAUDE.md.tmpl` 加 `## 工程结构约束` section + `{{STRUCTURE_CONSTRAINTS}}` placeholder + framework 第三档说明
- 9 条 golden test：`tests/test-structure-schema.sh`

**4.5a 范围严格收口**：不动 detect / init-project / task-spec SKILL（留给 4.5b/c）。

### 阶段 4 已完成（全部）
- `scripts/sync-req-docs.sh`：`git show <req-branch>:<path> > <dest>` 同步项目级文件 + req 目录递归 → 不写 `.git/index.lock`，多 worktree 并发安全；append `req_docs_synced` 事件含 `file_count` / `hash` / `req_branch`
- `scripts/create-task-worktree.sh` 末尾调用 sync（首次同步）
- `skills/task-execute/SKILL.md` 加入口步骤 2.4（启动前兜底再 sync 一次，防止 worktree 创建后 PM 又改 req 文档）
- `scripts/check-task-scope.py` 加 `implicit_deny`：项目级 `DESIGN.md` / `CLAUDE.md` 永远拒；req 目录内非自己 task 的文件永远拒；自己的 PM 视图 / 工程合同允许（即使 allowlist 不命中也能 commit 自己）
- 新增测试：`tests/test-sync-req-docs.sh`（6 条）+ `tests/test-check-task-scope.sh`（7 条）

**新窗口验证基线**：`bash tests/run-all.sh` → 应看到 209 / 0。

**实施中的坑**：
1. 数组 + `set -u` 在 macOS bash 3.x 下空数组触发 unbound → 改成换行分隔字符串积累
2. shell 字符串里 `$VAR` 直接接中文括号 `）` 时，多字节字节落入变量名扩展 → 用 `${VAR}` 显式 brace 包围
3. `task-events.py find_repo_root` 用 cwd 探测，跨主仓调用必须 `cd "$WORKTREE"` 包住

### 4.5b/c 待做

| 子阶段 | 内容 | 估时 |
|---|---|---|
| **4.5b detect** | `scripts/detect-project-structure.py`（用 `git ls-files` 而不是 `pathlib.glob` 防大仓性能）+ framework 第三档（PM-AI-Workflow 这种生成器 / 纯工具仓不走 prototype/system 二元）+ 5 E2E 测试 | ~45 分钟 |
| **4.5c 接入** | `init-project` SKILL 改造（新项目 / 已有项目 / framework 三分支）+ `task-spec` §5 双源读取（项目级 + req 级冲突阻断 critical T13） | ~60 分钟 |
| **4.5d 延期** | T15/T16 LLM eval（外部 judge 跑 36k 行场景）记 TODOS，等 judge 就绪再跑 | 不做 |

**估时**：plan 4.5 整段 0.5-1 天，已落 4.5a；剩 4.5b/c 预期 ~1.5-2 小时。

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
| 阶段 3b | 0.5 天 | ~30 分钟 | ~16x |
| 阶段 4 | 0.5 天 | ~45 分钟 | ~10x |
| 阶段 4.5a | — | ~30 分钟 | — |
| 阶段 4.5b/c | 0.5-1 天 | 预期 ~1.5-2 小时 | ~3-5x |

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
| 3b | 21 条 baseline test 字符串对齐 v3.5 演化 | ✅ 完成 |
| 4 | worktree 文档同步（git show 绕 index）| ✅ 完成 |
| 4.5a | 工程结构约束 schema + 派生 + CLAUDE.md.tmpl 段 | ✅ 完成 |
| 4.5b | detect-project-structure.py + framework 第三档 | ⏸ 下一步 |
| 4.5c | init-project / task-spec SKILL 接入双源 | ⏸ |
| 5 | 实现程度三阶段流程 | ⏸ |
| 6 | task-plan 按字段拆（Python 决策表）| ⏸ |
| 7 | task-spec 双源改造 | ⏸ |
| 8 | 格式统一前置 + 校验 + stale | ⏸ |
| 9 | PM 可见度（req-status + STATUS.md）| ⏸ |
