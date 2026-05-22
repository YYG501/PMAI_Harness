# RUNTIME（项目运行时状态）

> **职责**：当前进度 + 下一步入口 + 已知坑（运维入口；新窗口续接读这里）。
> **维护约定**：每完成一阶段更新本文件（~10 秒）；只留当前状态，已完成阶段的细节归档。
>
> 与 `README.md` / `CLAUDE.md` 的区分：
> - `README.md` = 产品介绍（一次写完，仓库门面）
> - `CLAUDE.md` = 项目章程（Claude Code agent 必读，行为规则 + 工程结构约束）
> - `RUNTIME.md`（本文件）= 运行时状态（动态更新；当前位置 + 已知坑 + 续接入口）

---

## 当前位置（2026-05-22）

**GSD-review 管线重构全包已落地** —— umbrella `docs/归档/完成/管线重构-GSD-review.md` §8 六步顺序全实施：

- **delta-7**（req 级事件流）：`scripts/req-events.py`（`decision` / `adjustment` 两类事件，落 `requirements/active/<reqid>/req-events.jsonl`）。
- **delta-2+4**（PRD/solution 对调）：`req-solution` → `/project-solution`（项目级，产 `docs/PROJECT.md` + `docs/roadmap.md`）；`/prd-writing` 前移 stage 3，产 req 级 `prd.md`。
- **delta-8**（实现设计视图）：`/implementation-design` + `templates/implementation-design.md.tmpl`，stage 5 拆 task 前产 req 级 HOW。
- **delta-3**（task-spec 重构）：task 双文件 → 单文件 typed contract（PM 确认区 / 执行区 / 审计区三区 + `task_format` 标记）；删 hash / reconcile / lazy-sync 整套机器。
- **delta-9**（跨功能产品规则）：`templates/PRODUCT-RULES.md.tmpl` + `DESIGN.md.tmpl` 升级；close-task selective promote；req-stage-gate stage 4 每 req 必跑 gap-check。
- **delta-1/5/6**（追加）：`/codebase-audit` brownfield 入口；req-analysis 全量 / 增量分析分支；close-req 步骤 2a 改为读 req-events `adjustment` 反推 PRD 成 as-built。

**§8 后续收尾（同日）**：

- **close-task 默认收尾**：PM 验收通过后默认走完收尾，仅「代码可能做错 / 需回退代码 / 范围变了」时才单独找 PM 确认；末尾给汇总 + PM 总审 diff。
- **modulespec 模板 9→5 章收敛**：活文档只留模块级内容，req 级章节移除。
- **一轮 DX 修复**：init-project skill 递归拷贝（修 references/ 漏拷）、入口脚本帮助 / 错误信息、read_section emoji 标题正则、sed 元字符 / 中文 slug 等 4 修。
- **`CONTEXT.md → PROJECT.md` 全量改名**：项目级文档与 GSD 命名层级对齐；消费仓一次性迁移脚本 `scripts/migrate-context-to-project.py`。

**测试基线**：`bash tests/run-all.sh` **395 / 0**；`_lib.state_test` **57 / 0**；`bash scripts/measure-tthw.sh` 实测 TTHW ≈ 2.0 秒。

**下一步**：去消费仓 `${CONSUMER_REPO_ROOT}` 跑真实 req 端到端验证新管线（stage 3 PRD → stage 4 gap-check → implementation-design → task-spec typed contract → close-task adjustment-promote → close-req PRD 反向对齐）。同步前按 `框架同步-SOP.md` 走流程；同步后在消费仓跑一次 `scripts/migrate-context-to-project.py`。

---

## 已知坑

当前无活跃的实施期已知坑 —— §8 全包已测 395/0。历史 v3.5 实施期发现的坑（parser section 终结符 / 空 cell 返回值 / macOS bash 3.x 空数组 unbound 等）见 `docs/归档/完成/RUNTIME-历史-v3.5与skill收敛.md`。

跨会话的工作方式 / 反模式沉淀见 memory（`MEMORY.md` 索引）。

---

## 文档导航

| 文档 | 作用 |
|---|---|
| `RUNTIME.md`（本文件）| 当前进度 + 下一步 + 已知坑 |
| `CLAUDE.md` | 项目章程（行为规则 + 工程结构约束）|
| `CHANGELOG.md` | 影响业务仓的改动流水（同步决策入口）|
| `框架同步-SOP.md` | 生成器 → 业务仓 hotfix 同步流程 |
| `INVARIANTS.md` | 框架不变量清单 |
| `TODOS.md` | 待决清单 |
| `docs/INDEX.md` | docs/ 全导航（设计中 / 已落地 / 已废弃）|
| `docs/归档/完成/RUNTIME-历史-v3.5与skill收敛.md` | v3.5 九阶段 + skill 读取收敛实施历史（本文件瘦身前内容）|

---

## 新窗口续接命令

> 继续 PM-AI-Workflow。读 RUNTIME.md 确认 GSD-review 管线重构全包已落地（395/0），告诉我下一步要做什么。

AI 收到后应该：
1. 读本文件确认当前位置
2. 等 PM 给具体方向（消费仓端到端验证 / 新一轮 review / 文档收口 等）
3. 不擅自启新阶段
