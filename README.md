# PM-AI-Workflow

PM AI 工作流框架的**生成器**仓库。

最终输出物：一份给 PM 单人使用的 LLM 协作工作流模板。

产品定位真相源：[`PRODUCT.md`](./PRODUCT.md)。

> 旧仓（参考用，不复用流程）：`<旧版 PMAI 仓库路径>`

---

## 最快路径

私有仓首次安装走这一条；其它安装方式放在后面作为备选：

```bash
gh auth status || gh auth login
rm -rf /tmp/pmai-src
gh repo clone YYG501/PMAI_Workflow /tmp/pmai-src
bash /tmp/pmai-src/bin/pmai install
~/.pmai/bin/pmai doctor
```

装好后，在任意业务项目目录里发：

```text
/pmai-init-project
```

如果只是要验证骨架脚本，不走完整 PM 交互：

```bash
tmp=$(mktemp -d)
bash ~/.pmai/scripts/init-project.sh Demo "$tmp/Demo" "一句话项目背景" prototype
python3 ~/.pmai/scripts/status-view.py "$tmp/Demo" --narrative
```

---

## 这是什么

PMAI 是面向 PM 的**产品上下文统一层**：它把产品文档、原型、反馈、决策和后续实现上下文接起来，让 AI 在每次协作时都知道这个产品是什么、已有原型长什么样、哪些规则和取舍已经确认。

PMAI 不和 Claude Design、design-html 或 Claude Code 比"谁更快生成第一版原型"。它更适合在方向逐渐明确后接管上下文、边界、文档和持续迭代：新需求基于已有产品上下文继续生长，PM 看着原型调整，原型确认后反向生成可评审 PRD 和 decision packet。

定位是 **PM 单人生产力工具**，不是团队 SOP / CI 平台 / 多租户基础设施。完整产品意义、非目标和成功标准见 [`PRODUCT.md`](./PRODUCT.md)。

**分发形态**：全局安装（单人多项目）。框架装到 `~/.pmai/`，当前 skill symlink 到 `~/.claude/skills/pmai-*` 和 `~/.codex/skills/pmai-*`；任意 cwd 跑 `/pmai-init-project` 起新业务项目；`pmai upgrade` 一键升级，所有项目自动跟随。skill 只装全局一处，项目里只放 host 配置 / 状态资产（`.claude/settings.json` / `.codex/hooks.json` / `.work-meta.json`）——这样每个 `/pmai-*` 命令永远唯一，不会和项目副本重复。

---

## 如何使用？

用户反馈：「希望加个批量审核功能，一次能审多个待审项。」

```
# 起项目（只跑一次，整个产品的根基）

/pmai-init-project    项目初始化统一入口（AI 自动判断全新项目 / 资料目录 / 已有代码；全新项目搭底座，已有代码直接盘点现状）

# 日常循环（模块规格先行，必要时再建）

/pmai-design "批量审核"    讨论清楚，写模块三件套：discussion.md / decisions.md / spec.md
/pmai-build 批量审核       大需求才建：对着 spec.md 或功能型规格文档在 prototype/ 里实现，可选隔离环境和执行器
/pmai-build-close                build 验收后收尾：提交/合并实现改动，对齐现状 / 规则 / 模块规格
/pmai-status          产品现状视图（产品长什么样 / 当前模块做到哪 / 下一步）
```

PM 全程**只做决策**（方向 / 结构 / 建造方式 / 验收 / 沉淀）；代码、commit、worktree 隔离、文档同步由框架兜。

---

## 依赖

| 工具 | 必需性 | 用途 |
|---|---|---|
| **Claude Code** | 推荐 | 一等主控入口（slash skill 原生在这里跑）；也可作为 `/pmai-build` 执行器 |
| **Codex** | 支持 | skill 暴露到 `~/.codex/skills/pmai-*`；读生成器仓 / 消费仓 `AGENTS.md` 作为主控入口；消费仓生成项目级 `.codex/hooks.json`；也可作为 build 执行器 |
| **Gemini CLI** | 可选 | `/pmai-build` 执行器；适合在 Codex / Claude 主控下交给 Gemini 建 |
| **gstack** | 必需 | `/qa` `/review` `/codex` 等子流程依赖；`pmai install` / `pmai doctor` 会提示 readiness，`init-project.sh` 建全新项目骨架时检测 gstack CLI 或 `~/.claude/skills/gstack`；已有代码库盘点分支不应被 gstack 缺失阻塞 |
| **git** ≥ 2.30 | 必需 | worktree 是核心隔离机制 |
| **python3** ≥ 3.10 | 必需 | scripts 大多用 python（zero-dep stdlib） |
| **bash** ≥ 4 | 必需 | scripts 入口语言（macOS 自带 3.x 已知坑见 INVARIANTS） |
| **codex CLI** | 可选 | `/pmai-build` 执行器；不装可走 Claude Code / Gemini / cursor-agent / 手动 |

未检测到 gstack CLI 且没有 `~/.claude/skills/gstack` 时，`pmai install` / `pmai doctor` 会给 warning，但不阻塞 PMAI 安装；真正建全新项目骨架时，`init-project.sh` 会直接报错并指向 `https://github.com/garrytan/gstack`。如果只是 `command -v gstack` 找不到，但全局 gstack skill 目录存在，PMAI 视为 gstack 能力可用。已有代码库接入走现状盘点分支，不调用 `init-project.sh`，所以不能因为 gstack 缺失卡在“判断项目情况”这一步。

---

## 安装

PMAI 用全局 CLI 形态分发。一次性安装，全局生效。

### 私有仓安装（推荐）

本仓是私有仓时，先确认当前 GitHub 账号有 `YYG501/PMAI_Workflow` 访问权限，再 clone 后安装。推荐 `gh` 路径：

```bash
gh auth status || gh auth login
rm -rf /tmp/pmai-src
gh repo clone YYG501/PMAI_Workflow /tmp/pmai-src
bash /tmp/pmai-src/bin/pmai install
~/.pmai/bin/pmai doctor
```

或走 SSH：

```bash
ssh -T git@github.com
git clone git@github.com:YYG501/PMAI_Workflow.git /tmp/pmai-src
bash /tmp/pmai-src/bin/pmai install
~/.pmai/bin/pmai doctor
```

安装成功后，`pmai install` 末尾会：
- clone 到 `~/.pmai/` + symlink skill 到 `~/.claude/skills/pmai-*` / `~/.codex/skills/pmai-*`
- 自动检测 shell（zsh/bash）+ 给 `~/.pmai/bin` 加 PATH 的 oneshot 命令
- 提示 gstack readiness；缺 gstack 只 warning，起项目前补齐即可

### 公开镜像安装（仅 public repo / public mirror）

如果仓库或镜像是 public，才适合 raw curl 一行安装：

```bash
curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash
```

私有仓直接用上面的 clone 安装；raw URL 在未公开时通常只会返回 404。

### 手工模式（本地 checkout）

如果你想自己 clone + 检查脚本再装：

```bash
# 1. 已有本仓 checkout 时，直接在 checkout 内安装

# 2. install
bash bin/pmai install                       # 全局安装

# 3. 按 install 末尾的「📌 一步加 PATH」提示加 ~/.pmai/bin 到 PATH

# 4. 校验
~/.pmai/bin/pmai doctor    # 完整性自检
```

> 临时 `/tmp/pmai-src` clone 只是 installer 容器，装完可删；真正稳定的副本在 `~/.pmai/`（pmai 自己 clone 的，`pmai upgrade` 拉它）。如果你在本仓 checkout 内直接 `bash bin/pmai install`，`pmai install` 仍会按 `PMAI_REMOTE` / 默认 remote 另 clone 一份到 `~/.pmai/`。

### 安装模式：仅全局

PMAI 只有全局安装一种形态（`pmai install` → clone `~/.pmai/` + symlink `~/.claude/skills/pmai-*` / `~/.codex/skills/pmai-*`）。消费仓保持干净，skill 不进项目；升级一处 `pmai upgrade`，所有项目自动跟随。

> 旧的 `--local`（往项目 `.claude/` 拷实体副本）已移除：它和全局并存时会让每个 `/pmai-*` 命令在菜单里重复，且副本不跟随升级而陈旧。消费仓需要的 host 配置（`.claude/settings.json` / `.codex/hooks.json`）仍单独放项目里（不是 skill，不会重复）；hook 脚本本体仍走 `~/.pmai/hooks` / `~/.pmai/scripts`。已有遗留副本用 `pmai uninstall --local <dir>` 清理。

**升级 / 卸载 / 状态**：

```bash
# 全局模式
pmai upgrade                          # 拉 main 最新（吃滚动版）
pmai upgrade --stable                 # 跳到最新 git tag（PM 打过的稳定 baseline）
pmai upgrade --to v0.1.0              # 锁定指定版本（回滚）

# 其他
pmai status               # VERSION + main HEAD diff
pmai doctor               # 完整性自检
pmai uninstall            # 清掉全局装；--local <dir> 清理遗留项目副本
```

**Claude Code 内升级（推荐 — 带 AI 智能 What's New 摘要）**：

```
/pmai-upgrade
```

skill 跑全局升级命令；升级完读 CHANGELOG diff + 用自然语言 5-7 bullet 总结新内容。

---

## 快速开始

> **TTHW 口径拆分**：
> - **骨架 smoke**：`init-project.sh` 从空目录建出业务仓骨架，目标 ≤ 10 秒，可自动量。
> - **第一个模块规格草稿**：从 `/pmai-init-project` 到 `/pmai-design` 落出 `spec.md`，目标 ≤ 30 分钟；这一步包含 PM 决策，只能通过 dogfood 记录，不适合作无交互脚本硬测。
> - install 自身通常约 5 秒（git clone + symlink），剩余时间主要是 PM 思考第一个需求。

### 1. 初始化新业务项目

**PM 主动入口**：装好 pmai 后，**在任意 cwd**（不要求在本仓）的 Claude Code 或 Codex 窗口里发：

```
/pmai-init-project
```

agent 内部先判断项目情况，再进入对应分支：

- **阶段 A · 参数收集 + 项目情况判断** —— AskUserQuestion 拿项目名 / 落地路径后，AI 直接扫目录。PM 不需要预先判断，也不需要在“初始化 / 代码盘点”之间选命令。
- **全新项目 / 资料目录分支** —— B/C/D 一气呵成：用 `init-project.sh` 建上下文底座，填一句话方向、视觉基线和主原型，再输出 Next Up。
- **已有代码库分支** —— 自动进入已有项目接入子流程：先整理真实代码现状，产 `docs/CODEBASE-AUDIT.md`，PM 过目后在同一流程内定项目方向；不补空骨架、不起空 `prototype/`、不调用 `init-project.sh`。
- **已接入过 PMAI 的项目** —— 不重跑 init；先看 `/pmai-status`，PM 明确要重定方向再走 `/pmai-direction`。

> `/pmai-init-project` 在装了 pmai 的任意 cwd 都能跑（无需在本仓）。

如果一个目录还没有 PMAI 初始化，任何其它 `/pmai-*` skill 被调用时都应先引导 PM 回到 `/pmai-init-project`；该入口会自动判断全新项目、资料目录或已有代码库，不要求 PM 手动选择另一个接入口。

**Codex 主控入口**：

- 在本生成器仓协同改框架：Codex 先读根目录 `AGENTS.md`，按 repo-local `skills/` / `scripts/` 工作。
- 在本生成器仓初始化消费仓：让 Codex 执行 `/pmai-init-project` 等价流程，内部读取 `skills/init-project/SKILL.md`，最后调用 `bash scripts/init-project.sh ...`。
- 在消费仓继续使用：`init-project.sh` 会生成消费仓根目录 `AGENTS.md` 和项目级 `.codex/hooks.json`；Codex 进入消费仓后先读 `AGENTS.md`。`pmai install/upgrade` 会把 `pmai-*` 暴露到 `~/.codex/skills/`；如果当前 Codex runtime 没有 slash skill UI，再按 `AGENTS.md` 把 `/pmai-*` 解析到 `PMAI_HOME` / `~/.pmai` 下的已安装 skill。Codex 首次启用项目 hooks 时可能要求信任确认，这是 Codex 自身的安全机制。

**非交互参数化 CLI**（smoke / 批量自动化依赖）：

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

> 脚本是骨架构建器，**不带方向讨论**；直接调脚本适合自动化场景，PM 主动起项目走 `/pmai-init-project` skill 拿到完整体验。

可量测骨架 smoke（从空目录到 `status-view.py` 可识别的项目骨架）：

```bash
tmp=$(mktemp -d)
bash scripts/init-project.sh Demo "$tmp/Demo" "一句话项目背景" prototype
python3 scripts/status-view.py "$tmp/Demo" --narrative
```

### 2. PM 在业务仓里的日常循环

> **注意**：装好 pmai 后，所有 skill 在 Claude Code / Codex 的 host skill 目录里都以 `pmai-` 前缀注册（防与 gstack / 其他框架命名冲突）。下面例子中的 `/pmai-*` 是真实的命令名。

```
/pmai-design "<一句话>"      → 探索真问题、理清信息结构、写模块三件套
  ↓
/pmai-build <模块或文档>     → 大需求才建；对着模块 spec 或 docs/modules/<按内容命名>.md 改 prototype/
  ↓
/pmai-status             → 忘了当前停在哪时，用它读状态并提示下一步
  ↓
/pmai-build-close                 → build 经 PM 验收后，提交/合并实现改动并对齐产品现状、规则、模块规格
```

简单改动可以跳过完整流程：直接改完后用 `/pmai-record` 做轻量记录；大需求才进入 `/pmai-build`，build 验收后再用 `/pmai-build-close`。

### 3. 多机 / 团队仓

PMAI 走纯全局：每台要用的机器各自 `pmai install` 一次（全局），消费仓里不放 skill 副本。换机器 clone 业务仓后，在该机跑一次全局安装即可在 Claude Code / Codex 里用 `/pmai-*`。

> 旧的 `--local`（把框架副本 commit 进业务仓 `.claude/`）已移除——它和全局并存会让命令重复、副本陈旧。若仓里还有遗留副本，清理：`pmai uninstall --local <仓目录>`（只删项目内副本，不动全局）。需要的 `.claude/settings.json` + `.codex/hooks.json` 保留（那些不是 skill，不会重复）。

---

## 完整 Skill 命令汇总

按 PM 使用频率分组。所有 skill 都以 `/pmai-` 前缀注册（防命名冲突）。

### 启动新工作

| Skill | 用途 |
|---|---|
| `/pmai-init-project` | **项目级入口**：全新项目建底座，已有代码库自动盘点现状；装了 pmai 后**任意 cwd** 可跑 |
| `/pmai-direction` | **项目方向校准**：已接入项目的方向重定 / 路线规划；已有代码首次接入由 `/pmai-init-project` 自动分流，不需要手动来这里 |
| `/pmai-design` | **模块设计入口**：起新功能 / 重做模块，写 discussion / decisions / spec |
| `/pmai-quick-fix` | 不走完整流程的小补丁（适合改文案、修小 bug） |

### 推进模块工作

| Skill | 用途 |
|---|---|
| `/pmai-status` | **续跑辅助**：读当前阶段做下一步（设计 → build → 复审 → 沉淀），先说再动 |
| `/pmai-build` | 对着模块 `spec.md` 或功能型规格文档在 `prototype/` 建；PM 选择执行器和是否开隔离环境 |
| `/pmai-spec-writing` | 功能型规格文档成文器：生成/修改模块规格；PRD、功能需求、功能描述、功能规格、功能评审稿都走这里 |
| `/pmai-doc-writing` | 介绍型文档成文器：产品介绍、产品功能清单、优势说明、一页纸、汇报材料，默认落 `docs/deliverables/` |

### 收尾 / 放弃

| Skill | 用途 |
|---|---|
| `/pmai-build-close` | build 验收后的收尾：提交 / 合并实现改动，按最终原型对齐模块决策与规格，更新产品现状 / 规则 / 术语 |
| `/pmai-record` | 轻量记录：main 小改或 design 后暂不 build 时，把稳定术语 / 规则 / 当前设计状态写回项目底座 |
| `/pmai-build-cancel` | 放弃当前 build，不合并，清活跃状态并排队清理隔离环境 |

### 旁路 / 文档维护

| Skill | 用途 |
|---|---|
| `/pmai-meta` | 讨论前对焦与压力测试：没靶子时找本质 / 判断标准 / 根因，有靶子时用少量多视角找盲区、冲突和风险 |
| `/pmai-lark-sync` | 本地规格与飞书在线文档安全同步：先判断真相源，再选择精细修改、覆盖发布、飞书回拉或只 diff |
| `/pmai-publish-to-lark` | 把本地 markdown 整篇发布 / 覆盖到飞书 |

### 框架维护（PM 操作 PMAI 本身）

| Skill | 用途 |
|---|---|
| `/pmai-upgrade` | 升级 PMAI 框架（全局；AI 智能 What's New 摘要 + AskUser 4 选项：main / stable tag / 锁版本 / 暂缓） |
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
| [`docs/归档/废弃/框架同步-SOP.md`](./docs/归档/废弃/框架同步-SOP.md) | 生成器 → 业务仓 hotfix 同步流程（**DEPRECATED + 已归档**；pmai install/upgrade 承接）|
| [`docs/归档/完成/v0/`](./docs/归档/完成/v0/) | v0 原始档案（需求.md / 设计.md / 需求-v0-原始草稿.md；不再活跃，归档保留作历史）|
| [`docs/归档/完成/`](./docs/归档/完成/) | 历史设计文档（21 份，2026-04~05 阶段决策档案；v3.5 收口后归档） |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | 贡献者入口：改代码前读什么、跑什么验证、怎么报 bug |

### 开发者自检入口

| 你要确认 | 命令 |
|---|---|
| 当前安装状态 / Claude+Codex skill 暴露是否漂移 | `pmai status` |
| 全局安装完整性（含 Claude+Codex 暴露） | `pmai doctor` |
| 测试整个生成器仓 | `bash tests/run-all.sh` |
| 旧 `requirements/active|closed` 仓库是否还需要人工迁移 | `python3 scripts/migrate-reqs-to-modules.py --dry-run <repo>` |

在本仓里直接跑 `bash bin/pmai status` / `bash bin/pmai doctor` 时，它检查的仍是
`PMAI_HOME`（默认 `~/.pmai`）这个安装目标；输出顶部会标明 `CLI source` 和
`Status/Audit target`。如果你想测真实用户入口，直接跑 `~/.pmai/bin/pmai status`
或 `~/.pmai/bin/pmai doctor`。

### 反馈与问题报告

有 bug 时优先开 GitHub issue，使用
[`bug_report.md`](./.github/ISSUE_TEMPLATE/bug_report.md) 模板。请贴：

- 你跑的是 repo-local `bash bin/pmai ...` 还是 installed `~/.pmai/bin/pmai ...`
- 完整命令 / slash skill 名
- `pmai status` 或 `pmai doctor` 输出
- 如果问题发生在生成器仓，附 `bash tests/run-all.sh` 汇总

---

## 当前状态

生成器骨架（scripts / skills / templates / tests）齐全，框架功能完整。

**当前进度、测试基线、下一步**见 [`RUNTIME.md`](./RUNTIME.md)「当前位置」—— 单一真相源，本文件不重复。
