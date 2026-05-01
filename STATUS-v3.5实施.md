# v3.5 实施进度

> **新窗口续接入口**。读完此文档即可知道当前位置 + 下一步。
> 维护约定：每完成一阶段更新本文件（~10 秒）。

---

## 当前位置（2026-05-01）

阶段 **1 + 2 + 3 + 4 + 4.5（全段，含 d 修订）完成**，全测试套件 0 失败：

```
（本次新增）
            feat(structure): 4.5d.3 + 4.5d.4 req 级深度变更段 + task-spec §5 prose 合并
cc352d9     feat(structure): 4.5d.2 派生模板 prose 段 + custom 档（PM 自由编辑）
f85a03f     refactor(structure): 4.5d.1 删除 framework 档（YAGNI，PM 否决）
6cfc0af     feat(structure-inject): inject + init-project 接 intent + task-spec §5 双源（4.5c）
9255782     feat(detect-structure): 5 档判定 + git ls-files 扫描（4.5b）
790c659     feat(structure-schema): 工程结构约束 schema + derive 派生 + CLAUDE.md.tmpl 加段（4.5a 框架）
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
工程结构约束 schema 框架（4.5a）+ detect 4 档判定（4.5b/d.1）+
inject 注入 + init-project 4 选项（含 custom）+ task-spec §5 prose 合并（4.5c/d.1/d.4）+
派生模板 prose 深度指引（4.5d.2）+ req 级深度变更段（4.5d.3）+ close-req 同步提示（4.5d.3）。
总测试 **254 通过 / 0 失败**。

| Bug | 状态 |
|---|---|
| P0-1 task 卡在「执行中→待验收」 | ✅ 已修 |
| P0-2 hook 不识别新格式状态值 | ✅ 已修 |
| P0-3 close-req / cancel-req 漏新格式 task | ✅ 已修 |
| P1-5 build-execution-prompt 拿错 worktree | ✅ 已修 |
| P1-7 fixture 还用旧单文件 | ⏸ 阶段 3 |

---

## 下一步：阶段 6（task-plan 按字段拆 task — 整段废弃方向）→ 阶段 7（task-spec 改造）

⚠️ plan 阶段 6（derive-task-types.py）已被 PM 否决（task 拆分由 PM 决定，不机械算）。阶段 7.1（PM 视图永远 PRD 等级）已在阶段 4.5c 的 task-spec SKILL §5 文档里隐含锁定；7.2 / 7.3 已被 4.5d.4 prose 合并实现。

**阶段 5/6/7 实质上已被 4.5d 整体替代**。下一步应该是阶段 8（格式统一前置 + 校验 + stale）或阶段 9（PM 可见度 / dashboard）。

## 下一步：阶段 4.5d 已完成 → 阶段 8 / 阶段 9（需 PM 决定优先级）

PM 修正 v3.5 plan 阶段 5/6 设计方向后，三层结构为：
- **项目级**（CLAUDE.md「## 工程结构约束」）：prototype/system/custom/unknown 四档；prototype/system 派生模板含代码组织 + 实现深度 prose 指引；custom 是 PM 自由编辑骨架。**不强制 enum 字段表**——AI 读自然语言段落做实现指引
- **req 级**（solution.md「本轮实现深度变更」）：默认空，仅在 req 改造代码架构时显式列出（自由文本段落）；close-req 同步项目级
- **task 级**：PM 在 task-plan 自己拆，文档永远 PRD 等级；工程合同 §5 按合并后深度生成实现指引

⚠️ 之前 plan 阶段 5/6 的 8 字段表 + derive-task-types.py 设计**整体废弃**（PM 否决：8 维度不通用 + 强制结构化破坏 PM-DX 渐进精神）。改用 prose 段落 + 三档 + custom 兜底。

### 阶段 4.5d.3 已完成（req 级「实现深度变更」段 + close-req 同步提示）
- `templates/solution.md.tmpl`：在「✅ 验收标准」与「📁 历史档案」之间加 `## 🔧 本轮实现深度变更` section，默认填「无变更」（自由文本，不是字段表）
- `skills/req-solution/SKILL.md`：步骤 3 章节顺序加「11. 🔧 本轮实现深度变更」+ 何时填指引（99% req 都填「无变更」）
- `skills/close-req/SKILL.md`：加步骤 2c：检查 req 级深度变更段，非「无变更」时呈交两段（req 级原文 + 项目级当前）+ 给 PM Y/N 选择是否同步项目级；AI **不自动改**项目级 CLAUDE.md（手改 = PM 长期决策落地，AI 不抢）
- 9 条新测试：`tests/test-depth-change-section.sh`（模板 section 存在 + 默认无变更 + 注释含规则；req-solution SKILL 章节顺序 + 何时填指引；close-req 步骤 2c + 跳过条件 + Y/N 选择 + 不自动改项目级）

### 阶段 4.5d.4 已完成（task-spec §5 双源 → prose 合并）
- `skills/task-spec/SKILL.md` 步骤 9 §5 子段重写：
  - A 层 4 档行为表（prototype/system/custom/unknown，custom 是 4.5d.2 新加）
  - B 层 三态行为：「无变更」/ 留空 / 含变更（自由文本，不是 enum）
  - **删除原 5×2 双源冲突表 + 阻断逻辑**：冲突已由 PM 在 close-req 步骤 2c 决定，task-spec 不再做机械检测
  - 拼接结果模板三段：「工程结构约束（A 层）」+「本轮实现深度变更（B 层）」+「具体实现要求」
- 6 条新测试：`tests/test-task-spec-prose-merge.sh`（4 档行为 + B 层三态 + 不冲突阻断 + fallback 不阻断 + 三段拼接模板 + PM 手填路径）
- 同步修订 inject-structure 测试（T13a 改成 prose 合并断言；T13b 改成无冲突阻断断言）

### 阶段 4.5d.2 已完成（prose 派生模板 + custom 档）
- `scripts/derive-structure-templates.py`：加 `DEPTH_GUIDANCE`（prototype/system 各 7 条 prose 深度指引：数据层 / 权限 / API 契约 / 测试 / 边界态 / 多端 / 演示路径）；`render_template` 输出三段：代码组织 + 实现深度指引 + 约定；新增 `_render_custom_template` 派生 PM 自由编辑骨架
- 新增 `templates/工程结构约束-custom.md` 派生模板（PM 自由 prose 编辑骨架）
- 重新派生 prototype/system 模板（含 prose 深度指引）
- `scripts/inject-structure-segment.py`：`VALID_INTENTS` 加 `custom`；render_segment 走 custom 分支读 custom 模板；load_template 的 drop 逻辑更通用化（连续吞开头注释行 + 第一空行）
- `scripts/init-project.sh`：参数校验加 `custom`
- `skills/init-project/SKILL.md`：步骤 1 选项加 `custom`（带场景说明）
- `templates/CLAUDE.md.tmpl`：placeholder 注释更新到 4 档说明
- 测试：inject 12/12（新增 T11e custom 写骨架 / T11f prose 包含数据层+权限层）；structure-schema 12/12（新增 prototype/system/custom 三模板的 prose / 骨架校验）

### 阶段 4.5d.1 已完成（删 framework 档）
- 「framework」是探测兜底档，PM 不会选用（本框架目标是 PM 单人业务工具，非 framework 项目仓）
- 6 文件清理 + 测试调整：detect / inject / init-project / task-spec / CLAUDE.md.tmpl / 测试 framework 引用全删，本仓自检从 framework 改判 unknown
- 测试：detect 6/6（test_framework_project → test_non_product_repo_falls_to_unknown；test_self_repo_is_framework → test_self_repo_is_unknown）；inject 10/10（T11b inject framework 改成「拒绝 framework intent」）

### 4.5d 全段完成（d.1/d.2/d.3/d.4 全部）

整段 4.5（探测档）+ 4.5d 修订（PM 否决 8 字段方向后重做）已闭合。下一步根据 PM 决定走阶段 8 / 阶段 9 / 别的优先级。

### 阶段 4.5c 已完成（inject + init-project + task-spec 接入）
- `scripts/inject-structure-segment.py`：把工程结构约束段注入 CLAUDE.md，按 PM 选定的 intent（prototype / system / framework / unknown）写入对应内容；含 auto-detected 标，placeholder 已替换后二次 inject 拒绝（保护手填）
- `scripts/init-project.sh`：加 4th 参数 `<project-intent>`（合法值 prototype/system/framework/unknown），模板复制后调用 inject 自动写入「工程结构约束」段
- `skills/init-project/SKILL.md`：步骤 1 加询问「项目意图」（4 项信息）+ 步骤 2 改成 4 参数调用 + framework 档说明
- `skills/task-spec/SKILL.md`：步骤 9 内加 §5 双源拼接子段：A 层项目级（CLAUDE.md「## 工程结构约束」）+ B 层 req 级（solution.md「本轮实现程度」）+ 5×2 双源冲突表（critical T13：项目级 prototype + req 级完整系统 → 阻断）+ framework 档跳过 + 缺段 fallback 不阻断
- 9 条新测试：`tests/test-inject-structure.sh`（T11a/b/c inject 行为 + T12 PM 手填保护 + T13a/b/c 双源规则 + 2 接入校验）

### 阶段 4.5b 已完成（detect 五档判定）
- `scripts/detect-project-structure.py`：用 `git ls-files` 取 tracked 文件（性能 + 自动排除 .gitignore），fnmatch 命中 schema signals → 输出 5 档判定 + 置信度 + signal 证据
- 判定规则（`compute_judgment`）：
  - system signal ≥ 2 + prototype-friendly = 0 → **system**
  - system + prototype-friendly 共存 → **hybrid**
  - 仅 prototype-friendly 命中 → **prototype**
  - scan_roots 下无任何 ts/tsx → **framework**（生成器 / 工具仓）
  - 其余 → **unknown**
- brace 展开（`*.{ts,tsx}` → `*.ts` + `*.tsx`）手动实现，fnmatch 不带 brace
- 6 条 E2E 测试：`tests/test-detect-project-structure.sh`，含本仓自检（PM-AI-Workflow 判 `framework` 0.7）

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

### 4.5d 延期（不阻塞主线）

T15/T16 LLM eval（外部 judge 跑 36k 行场景验证）记 TODOS，等 judge 环境就绪再跑——本机没法直接运行。

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
| 阶段 4.5b | — | ~25 分钟 | — |
| 阶段 4.5c | 0.5 天 | ~40 分钟 | ~6x |
| 阶段 4.5d.1 | — | ~25 分钟 | — |
| 阶段 4.5d.2 | — | ~50 分钟 | — |
| 阶段 4.5d.3 | — | ~25 分钟 | — |
| 阶段 4.5d.4 | — | ~20 分钟 | — |

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
| 4.5b | detect-project-structure.py + framework 第三档 | ✅ 完成 |
| 4.5c | inject + init-project intent + task-spec §5 双源 | ✅ 完成 |
| 4.5d.1 | 删 framework 档（YAGNI，PM 否决）| ✅ 完成 |
| 4.5d.2 | 派生模板加 prose 深度指引 + custom 档 | ✅ 完成 |
| 4.5d.3 | req 级「实现深度变更」段（自由文本）+ close-req 同步 | ✅ 完成 |
| 4.5d.4 | task-spec §5 双源 → prose 合并（删冲突阻断）| ✅ 完成 |
| 5 | 实现程度三阶段流程 | ❌ 废弃（PM 否决 8 字段表，已被 4.5d 整体替代）|
| 6 | task-plan 按字段拆（Python 决策表）| ❌ 废弃（PM 自主拆 task）|
| 7 | task-spec 双源改造 | ❌ 废弃（已被 4.5d.4 实现）|
| 8 | 格式统一前置 + 校验 + stale | ⏸ 待 PM 决定优先级 |
| 9 | PM 可见度（req-status + STATUS.md）| ⏸ 待 PM 决定优先级 |
