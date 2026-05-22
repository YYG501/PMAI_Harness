# PM-AI-Workflow

PM AI 工作流框架的**生成器**仓库。

最终输出物：一份给 PM 单人使用的 LLM 协作工作流模板。

> 旧仓（参考用，不复用流程）：`${LEGACY_REPO_ROOT}`

---

## 这是什么

把"PM 用 AI 做产品/业务工作"的循环固化成可复制的工作流：每个业务项目用一份生成的模板初始化，PM 通过一组 slash skill（`/new-req` `/task-confirm` `/task-execute` …）推进 req（需求）和 task（任务），框架负责状态机、worktree 隔离、文档同步、护栏。

定位是 **PM 单人生产力工具**，不是团队 SOP / CI 平台 / 多租户基础设施。

---

## 依赖

| 工具 | 必需性 | 用途 |
|---|---|---|
| **Claude Code** | 必需 | 主要 AI 协作入口（slash skill 在这里跑） |
| **gstack** | 必需 | `/qa` `/review` `/codex` 等子流程依赖；`init-project.sh` 入口会检测 | 
| **git** ≥ 2.30 | 必需 | worktree 是核心隔离机制 |
| **python3** ≥ 3.10 | 必需 | scripts 大多用 python（zero-dep stdlib） |
| **bash** ≥ 4 | 必需 | scripts 入口语言（macOS 自带 3.x 已知坑见 INVARIANTS） |
| **codex CLI** | 可选 | 默认执行器；不装走 `cursor-agent` / `claude` / `manual` |

未装 gstack 时 `init-project.sh` 会直接报错并指向 `https://github.com/garrytan/gstack`。

---

## 快速开始

> **TTHW 期望**：从 init-project 跑通到落第一个 `brief.md` 草稿 ≤ 30 分钟。
> init-project 自身 ~10 秒（拷贝 + git init + commit）；其余时间是 PM 思考第一个需求。

### 1. 初始化新业务项目

**必须在本仓（PM-AI-Workflow）根目录运行**。生成器自身不能用作业务项目仓。

```bash
cd ${REPO_ROOT}
bash scripts/init-project.sh --help          # 看完整用法 + 参数 + 例子
bash scripts/init-project.sh \
  <project-name> \
  <target-dir> \
  "<background>" \
  [prototype|system|custom|unknown]
```

参数：
- `<project-name>` — 业务项目名（也是 git 仓的名字）
- `<target-dir>` — 业务项目落地路径（**不能已存在**）
- `<background>` — 一句话项目背景（写进生成的 CLAUDE.md）
- `<project-intent>` — 工程结构意图（默认 `unknown`）：
  - `prototype` — Next.js 单页原型 / Demo 仓
  - `system` — 完整业务系统（多模块、有后端契约）
  - `custom` — PM 自由编辑骨架
  - `unknown` — 探测兜底档（先 init，跑通后再分类）

成功后业务仓已 `git init` 并完成首个 commit，下一步在业务仓里运行 `/new-req` 启动第一个需求。

> **5 分钟你会看到**：业务仓目录已建（`.claude/scripts/` `.claude/skills/` `.claude/agents/` `templates/` `CLAUDE.md` `requirements/` 等）+ 一个 init commit；终端打印「下一步：cd <target> && /new-req」。

可量测 TTHW（从空项目到第一个 `status-view.py` 可识别的 active req）：

```bash
bash scripts/measure-tthw.sh
```

### 2. PM 在业务仓里的日常循环

```
/new-req          → 起一个 req（需求）
  ↓
/req-stage-gate   → 推进 req 阶段（analysis → PRD → gap-check → implementation-design → plan → spec）
  ↓
/task-confirm     → PM 同意启动一个 task → 输出新窗口启动指令
  ↓ （PM 开新窗口）
/task-execute     → 在新窗口里跑 codex 执行 task
  ↓ （task 状态全程「执行中」 — commit 不切状态）
/task-submit      → task agent commit + 呈交验收信息块
  ↓ （PM 在 task 窗口决策：通过 / 打回；打回不切状态，AI 直接修代码）
                  → PM 通过 → 转「已完成」
  ↓ （PM 在 req 窗口）
/close-task       → 归档 runtime + 删 task worktree
  ↓
/close-req        → 整个 req 收尾，并入主分支
```

并行：PM 想多个 task 同时跑，开多个新窗口跑 `/task-execute` 即可（v4 单窗口 lifecycle，git worktree 天然隔离）。

---

## 完整 Skill 命令汇总

按 PM 使用频率分组：

### 启动新工作

| Skill | 用途 |
|---|---|
| `/new-req` | 起一个新 req（带 brief） |
| `/project-solution` | 初始化 / 修订项目级 PROJECT 与 roadmap |
| `/quick-fix` | 不走 req 流程的小补丁（适合改文案、修小 bug） |

### 推进 req（需求级）

| Skill | 用途 |
|---|---|
| `/req-stage-gate` | 推进 req 阶段闸门（analysis → PRD → 实现设计 → plan → spec） |
| `/req-analysis` | 起草 / 修订 analysis.md |
| `/prd-writing` | 起草 / 修订 req 级 prd.md（WHAT） |
| `/implementation-design` | 起草 req 级 implementation-design.md（HOW） |
| `/task-plan` | 把 PRD + 实现设计拆成 task 清单 |
| `/task-spec` | 把单个 task 写成单文件 typed contract |

### 执行 task（任务级）

| Skill | 用途 |
|---|---|
| `/task-confirm` | PM 同意启动 task → 输出新窗口启动指令（不调任何 agent） |
| `/task-execute` | **新窗口里运行**：自动 cd worktree + 跑 codex |
| `/task-submit` | task agent 呈交验收信息块（兜底；默认由 task-execute 自动呈交） |
| `/task-status` | 多 task 状态总览（待启动 / 执行中 / 已完成） |
| `/close-task` | PM 验收通过 → 已完成 + 归档 runtime |

### 收尾 req

| Skill | 用途 |
|---|---|
| `/close-req` | req 完成，merge 进 main + 同步项目级文档 |
| `/cancel-req` | req 中止，回滚 worktree |

### 旁路 / 文档维护

| Skill | 用途 |
|---|---|
| `/doc-update` | 处理文档偏差 + 沉淀模块规格 |
| `/codebase-audit` | brownfield 项目代码现状审计 |
| `/publish-to-lark` | 把文档发布到飞书 |

### 框架内部（PM 不直接用）

| Skill | 用途 |
|---|---|
| `/init-project` | 业务项目脚手架（只在本仓使用） |

---

## 文档导航

| 文档 | 作用 |
|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | 项目章程（生成器的） |
| [`RUNTIME.md`](./RUNTIME.md) | 项目运行时状态（当前进度 / 已知坑 / 新窗口续接入口）|
| [`CHANGELOG.md`](./CHANGELOG.md) | 影响业务仓的改动记录（按 commit 时间倒序；业务仓 sync 前看顶部）|
| [`docs/归档/完成/DX-AUDIT-2026-05-08.md`](./docs/归档/完成/DX-AUDIT-2026-05-08.md) | 2026-05-08 DX 审计档案（已收尾，保留作历史）|
| [`INVARIANTS.md`](./INVARIANTS.md) | 框架不变量清单（I-CT / I-TT / I-AD 等编号约束） |
| [`TODOS.md`](./TODOS.md) | 待决项 / 延迟决策（v2/v4/UP/DX/Eng/TD-1~4） |
| [`框架同步-SOP.md`](./框架同步-SOP.md) | 生成器 → 业务仓 hotfix 同步流程 |
| [`docs/归档/完成/v0/`](./docs/归档/完成/v0/) | v0 原始档案（需求.md / 设计.md / 需求-v0-原始草稿.md；不再活跃，归档保留作历史）|
| [`docs/归档/完成/`](./docs/归档/完成/) | 历史设计文档（21 份，2026-04~05 阶段决策档案；v3.5 收口后归档） |

---

## 当前状态

v3.5 与 v4 task 执行架构（PM 手动新窗口 + 并行原生）已收口。2026-05-22 GSD-review 管线重构全包已落地：stage 3 PRD、req 级事件流、implementation-design、task 单文件 typed contract、PRODUCT-RULES / DESIGN gap-check、brownfield codebase-audit 等均已接入。

当前测试基线：`bash tests/run-all.sh` 为 394 通过 / 0 失败；`bash scripts/measure-tthw.sh` 实测 TTHW 约 2.0 秒。

**下一步重点**：去消费仓 ExampleConsumerApp 跑真实 req 端到端验证新管线。详见 `RUNTIME.md` 顶部「当前位置」。
