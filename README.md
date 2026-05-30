# PM-AI-Workflow

PM AI 工作流框架的**生成器**仓库。

最终输出物：一份给 PM 单人使用的 LLM 协作工作流模板。

产品定位真相源：[`PRODUCT.md`](./PRODUCT.md)。

> 旧仓（参考用，不复用流程）：`${LEGACY_REPO_ROOT}`

---

## 这是什么

PMAI 是面向 PM 的**产品上下文统一层**：它把产品文档、原型、反馈、决策和后续实现上下文接起来，让 AI 在每次协作时都知道这个产品是什么、已有原型长什么样、哪些规则和取舍已经确认。

PMAI 不和 Claude Design、design-html 或 Claude Code 比"谁更快生成第一版原型"。它更适合在方向逐渐明确后接管上下文、边界、文档和持续迭代：新需求基于已有产品上下文继续生长，PM 看着原型调整，原型确认后反向生成可评审 PRD 和 decision packet。

定位是 **PM 单人生产力工具**，不是团队 SOP / CI 平台 / 多租户基础设施。完整产品意义、非目标和成功标准见 [`PRODUCT.md`](./PRODUCT.md)。

**分发形态**：
- **全局安装**（默认推荐，单人多项目场景）：框架装到 `~/.pmai/`，22+ skill symlink 到 `~/.claude/skills/pmai-*`；任意 cwd 跑 `/pmai-init-project` 起新业务项目；`pmai upgrade` 一键升级所有项目自动跟随
- **`--local` 项目安装**（团队仓场景）：框架实体副本 commit 进业务仓 `.claude/`；队友 `git clone` 后 0 setup 即可用 `/pmai-*` skill；升级靠 `pmai upgrade --local <dir>` 或 cwd 内跑 `/pmai-upgrade` 自动重克隆+覆盖

---

## 如何使用？

> 当前命令说明反映现有框架能力。后续流程改造以 [`PRODUCT.md`](./PRODUCT.md) 的定位为准：PRD 应从"原型前重规格门"逐步转为"原型确认后的正式沉淀物"。

用户反馈：「希望加个批量审核功能，一次能审多个待审项。」

```
# 起项目（只跑一次，整个产品的根基）

/pmai-init-project    起业务项目（AI 跟你聊清做什么 / 为谁做，写 PROJECT.md）

# req 主流程（一个需求 = 一个 req，每步 PM 拍板推进）

/pmai-new-req "批量审核"   起 req + 一句话 brief
/pmai-req-stage-gate       → stage 1 · analysis（现状 / 约束 / 边界）
/pmai-req-stage-gate       → stage 2 · PRD（WHAT — 功能规格 / 用户故事）
/pmai-req-stage-gate       → stage 3 · 实现设计（HOW — 技术方案）
/pmai-req-stage-gate       → stage 4 · task plan（拆成 N 个 task）
/pmai-req-stage-gate       → stage 5 · task spec（每个 task 写成单文件 typed contract）

# task 子循环（每个 task 跑一遍；并行可开多窗口）

/pmai-task-confirm    PM 拍板启动一个 task → AI 给新窗口启动指令
/pmai-task-execute    新窗口里 codex 写代码（worktree 隔离 + 自动 commit）
/pmai-close-task      PM 验收通过 → 归档 task runtime

# req 收尾

/pmai-close-req       合主分支，整个需求闭环
```

PM 全程**只做决策**（方向 / PRD / 任务拆分 / 验收）；代码、commit、worktree 隔离、文档同步、状态机由框架兜。

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

未装 gstack 时 `init-project.sh`（起新业务项目）会直接报错并指向 `https://github.com/garrytan/gstack`。`pmai install` 本身不检 gstack —— 你可以先装 PMAI、需要起项目时再补装 gstack。

---

## 安装

PMAI 用全局 CLI 形态分发（参考 [`docs/设计/框架分发与全局安装.md`](docs/设计/框架分发与全局安装.md)）。一次性安装，全局生效。

### 一行安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash
```

或带 `--local <dir>` 跑项目级实体副本模式：

```bash
curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash -s -- --local /path/to/your/project
```

`install.sh` 做的事：
- 依赖检查（git / bash / python3）
- git clone PMAI 到临时位置（SSH 优先，失败自动 fallback HTTPS）
- 跑 `bash bin/pmai install [args]`（自动 clone 到 `~/.pmai/` + symlink skill 到 `~/.claude/skills/pmai-*`）
- install 末尾自动检测 shell（zsh/bash）+ 给 `~/.pmai/bin` 加 PATH 的 oneshot 命令
- 清理临时安装容器

### 手工模式（不走 curl）

如果你想自己 clone + 检查脚本再装：

```bash
# 1. clone 到临时位置
git clone git@github.com:YYG501/PMAI_Workflow.git /tmp/pmai-src

# 2. install
bash /tmp/pmai-src/bin/pmai install                       # default 全局
# 或：bash /tmp/pmai-src/bin/pmai install --local <dir>   # 项目级实体副本

# 3. 按 install 末尾的「📌 一步加 PATH」提示加 ~/.pmai/bin 到 PATH

# 4. 校验
pmai doctor    # 7 段自检
```

> 临时 `/tmp/pmai-src` clone 只是 installer 容器，装完可删；真正稳定的副本在 `~/.pmai/`（pmai 自己 clone 的，`pmai upgrade` 拉它）。

### 两种安装模式

| 模式 | 命令 | 消费仓内 framework | 跨机器 clone 消费仓 | 升级方式 |
|---|---|---|---|---|
| **default 全局**（推荐）| `pmai install` | 0（消费仓干净）| ❌ 失效（symlink 指 `~/.pmai/`）| `pmai upgrade` 或 `/pmai-upgrade` skill；所有消费仓自动跟 |
| **--local 项目级** | `pmai install --local <dir>` | 实体副本（~3MB）| ✅ 自含可用 | `pmai upgrade --local <dir>` 或 cwd 内 `/pmai-upgrade` skill 自动按 local 模式重克隆覆盖；需手动 commit + push |

**怎么选**：
- **单人多项目** → default 全局
- **团队共享仓**（队友不愿装 pmai CLI） → `--local`
- **CI / 离线机器 / 想锁定框架版本随项目走** → `--local`

**升级 / 卸载 / 状态**：

```bash
# 全局模式
pmai upgrade                          # 拉 main 最新（吃滚动版）
pmai upgrade --stable                 # 跳到最新 git tag（PM 打过的稳定 baseline）
pmai upgrade --to v0.1.0              # 锁定指定版本（回滚）

# --local 模式（团队仓重克隆 + 覆盖副本 + 提示 commit/push）
pmai upgrade --local /path/to/team-repo
pmai upgrade --local /path/to/team-repo --stable
pmai upgrade --local /path/to/team-repo --to v0.1.0

# 其他
pmai status               # 当前 install 模式 + VERSION + main HEAD diff
pmai doctor               # 完整性自检
pmai uninstall            # 清掉全局装；--local <dir> 清项目级
```

**Claude Code 内升级（推荐 — 带 AI 智能 What's New 摘要）**：

```
/pmai-upgrade
```

skill 自动检测 cwd 是 `--local` 安装目录还是全局环境，按 mode 走对应升级命令；升级完读 CHANGELOG diff + 用自然语言 5-7 bullet 总结新内容。`--local` 模式升级完会打印 `git add .claude/ + commit + push` 提示让 PM 自己执行（团队仓 commit message 由 PM 拍板）。

---

## 快速开始

> **TTHW 期望**：从 pmai install 跑通到落第一个 `brief.md` 草稿 ≤ 30 分钟。
> install 自身 ~5 秒（git clone + symlink），init-project 跑 ~10 秒，其余时间是 PM 思考第一个需求。

### 1. 初始化新业务项目

**PM 主动入口**：装好 pmai 后，**在任意 cwd**（不要求在本仓）的 Claude Code 窗口里发：

```
/pmai-init-project
```

agent 内部一气呵成 **4 阶段**：

- **阶段 A · 参数收集 + brownfield 检测** —— AskUserQuestion 5 步问 PM（项目名 → 落地路径 → brownfield 检测闸门 → 一句话背景 → 项目意图）。目标目录已含 `.git/` 或代码 → 拒 + 提示走 `/pmai-codebase-audit`
- **阶段 B · 骨架建设** —— agent 用 Bash 调 `init-project.sh`，创建业务仓 + git init + 首 commit `init: <name>`
- **阶段 C · QUESTIONING（方向讨论）** —— @读 `skills/_shared/project-questioning.md`（单一真相源），按提问纪律跑讨论 + Decision gate「创建 PROJECT.md / 继续探索」二选一 + Loop 回路，最后写 `docs/PROJECT.md` + `docs/ROADMAP.md` + atomic commit `docs: project direction settled`
- **阶段 D · 终态汇总 + Next Up** —— 输出「✅ <name> 已就绪 / cd <target> && /pmai-new-req "..."」

> `/pmai-init-project` 在装了 pmai 的任意 cwd 都能跑（无需在本仓）。

**非交互参数化 CLI**（`measure-tthw.sh` / smoke / 批量自动化依赖）：

```bash
# 优先：从 ~/.pmai/ 调用
bash ~/.pmai/scripts/init-project.sh \
  <project-name> \
  <target-dir> \
  "<background>" \
  [prototype|system|custom|unknown]

# 或在本仓内调用（fallback 路径，自动推 FRAMEWORK_DIR）
bash scripts/init-project.sh ...
```

参数：
- `<project-name>` — 业务项目名（也是 git 仓的名字）
- `<target-dir>` — 业务项目落地路径（**不能已存在**）
- `<background>` — 一句话项目背景
- `<project-intent>` — 工程结构意图（默认 `unknown`）：`prototype` / `system` / `custom` / `unknown`

> 脚本是骨架构建器，**不带方向讨论**（PROJECT.md / ROADMAP.md 留空骨架）；直接调脚本适合自动化场景，PM 主动起项目走 `/pmai-init-project` skill 拿到完整体验。

可量测 TTHW（从空项目到第一个 `status-view.py` 可识别的 active req）：

```bash
bash scripts/measure-tthw.sh
```

### 2. PM 在业务仓里的日常循环

> **注意**：装好 pmai 后，所有 skill 在 Claude Code 内都以 `pmai-` 前缀注册（防与 gstack / 其他框架命名冲突）。下面例子中的 `/pmai-*` 是真实的命令名。

```
/pmai-new-req          → 起一个 req（需求）
  ↓
/pmai-req-stage-gate   → 推进 req 阶段（analysis → PRD → gap-check → implementation-design → plan → spec）
  ↓
/pmai-task-confirm     → PM 同意启动一个 task → 输出新窗口启动指令
  ↓ （PM 开新窗口）
/pmai-task-execute     → 在新窗口里跑 codex 执行 task
  ↓ （task 状态全程「执行中」— commit 不切状态）
/pmai-task-submit      → task agent commit + 呈交验收信息块
  ↓ （PM 在 task 窗口决策：通过 / 打回；打回不切状态，AI 直接修代码）
                       → PM 通过 → 转「已完成」
  ↓ （PM 在 req 窗口）
/pmai-close-task       → 归档 runtime + 删 task worktree
  ↓
/pmai-close-req        → 整个 req 收尾，并入主分支
```

并行：PM 想多个 task 同时跑，开多个新窗口跑 `/pmai-task-execute` 即可（v4 单窗口 lifecycle，git worktree 天然隔离）。

### 3. 团队仓使用（`--local` 模式）

如果你的业务仓是团队共享仓（队友不愿装 pmai CLI），用 `--local` 把框架副本 commit 进仓：

```bash
# 你（PM）首装
cd /path/to/team-repo
curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash -s -- --local .
git add .claude/
git commit -m "chore: add PMAI framework (--local install)"
git push

# 队友
git clone <team-repo>
cd <team-repo>
# → 直接 Claude Code 里用 /pmai-* skill，0 setup

# 你（PM）升级
cd /path/to/team-repo
# 方式 A：Claude Code 内（推荐，带 AI 摘要）
/pmai-upgrade        # skill 自动按 --local 模式重克隆 + 覆盖副本
# 方式 B：shell
pmai upgrade --local .
# 然后按提示 commit + push：
git add .claude/
git commit -m "chore: upgrade PMAI to v<NEW>"
git push
```

**注意事项**：
- 检查 `.gitignore` 没把 `.claude/scripts/skills/agents/` ignore（默认不 ignore，但本仓如有自定义 `.gitignore` 需确认）
- 业务实例 template（如配过 token 的 `templates/lark-publish.json.tmpl`）重装前 backup 一份，重装后放回
- 升级建议由你一人负责，避免队友各自跑导致 commit 冲突

---

## 完整 Skill 命令汇总

按 PM 使用频率分组。所有 skill 都以 `/pmai-` 前缀注册（防命名冲突）。

### 启动新工作

| Skill | 用途 |
|---|---|
| `/pmai-init-project` | **项目级入口**：起一个新业务项目，4 阶段一气呵成（参数 → 骨架 → 方向 → Next Up）；装了 pmai 后**任意 cwd** 可跑 |
| `/pmai-project-solution` | **项目方向规划**：4 个独立场景（重做 / 产品路线规划 / 老板新方向 / brownfield 接入） |
| `/pmai-new-req` | **req 级入口**：起一个新 req（带 brief） |
| `/pmai-quick-fix` | 不走 req 流程的小补丁（适合改文案、修小 bug） |

### 推进 req（需求级）

| Skill | 用途 |
|---|---|
| `/pmai-req-stage-gate` | 推进 req 阶段闸门（analysis → PRD → 实现设计 → plan → spec） |
| `/pmai-req-analysis` | 起草 / 修订 analysis.md |
| `/pmai-prd-writing` | 起草 / 修订 req 级 prd.md（WHAT） |
| `/pmai-implementation-design` | 起草 req 级 implementation-design.md（HOW） |
| `/pmai-task-plan` | 把 PRD + 实现设计拆成 task 清单 |
| `/pmai-task-spec` | 把单个 task 写成单文件 typed contract |

### 执行 task（任务级）

| Skill | 用途 |
|---|---|
| `/pmai-task-confirm` | PM 同意启动 task → 输出新窗口启动指令（不调任何 agent） |
| `/pmai-task-execute` | **新窗口里运行**：自动 cd worktree + 跑 codex |
| `/pmai-task-submit` | task agent 呈交验收信息块（兜底；默认由 task-execute 自动呈交） |
| `/pmai-task-verify` | task agent 自审验收（task-execute 内部调） |
| `/pmai-task-status` | 多 task 状态总览（待启动 / 执行中 / 已完成） |
| `/pmai-close-task` | PM 验收通过 → 已完成 + 归档 runtime |

### 收尾 req

| Skill | 用途 |
|---|---|
| `/pmai-close-req` | req 完成，merge 进 main + 同步项目级文档 |
| `/pmai-cancel-req` | req 中止，回滚 worktree |

### 旁路 / 文档维护

| Skill | 用途 |
|---|---|
| `/pmai-doc-update` | 处理文档偏差 + 沉淀模块规格 |
| `/pmai-codebase-audit` | brownfield 项目代码现状审计 |
| `/pmai-publish-to-lark` | 把文档发布到飞书 |

### 框架维护（PM 操作 PMAI 本身）

| Skill | 用途 |
|---|---|
| `/pmai-upgrade` | 升级 PMAI 框架（自动检测 global / `--local` 模式 + AI 智能 What's New 摘要 + AskUser 4 选项：main / stable tag / 锁版本 / 暂缓） |
| `/pmai-skill-improve` | PM 用 AI 协作改 skill（限生成器仓内用） |

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

生成器骨架（scripts / skills / templates / tests）齐全，框架功能完整。

**当前进度、测试基线、下一步**见 [`RUNTIME.md`](./RUNTIME.md)「当前位置」—— 单一真相源，本文件不重复。
