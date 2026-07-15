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
# 需要确认 /browse runtime 真能启动时再跑主动 smoke：
~/.pmai/bin/pmai doctor --browser-smoke
```

装好后，在任意业务项目目录里发：

```text
/pmai-init-project
```

如果只是要验证骨架脚本，不走完整 PM 交互：

```bash
tmp=$(mktemp -d)
bash ~/.pmai/scripts/init-project.sh Demo "$tmp/Demo" "一句话项目背景"
python3 ~/.pmai/scripts/status-view.py "$tmp/Demo" --narrative
```

---

## 这是什么

PMAI 是面向 PM 的**产品上下文统一层**：它把产品文档、原型、反馈、决策和后续实现上下文接起来，让 AI 在每次协作时都知道这个产品是什么、已有原型长什么样、哪些规则和取舍已经确认。

PMAI 不和 Claude Design、design-html 或 Claude Code 比"谁更快生成第一版原型"。它负责把方向讨论、prototype / product 构建、PM 看结果多轮修改、最终验收、合入 main 和正式文档对齐接成同一条链路。新需求从已有产品上下文继续生长，PM 只处理产品判断、看结果和明确定稿。

定位是 **PM 单人生产力工具**，不是团队 SOP / CI 平台 / 多租户基础设施。完整产品意义、非目标和成功标准见 [`PRODUCT.md`](./PRODUCT.md)。

**分发形态**：全局安装（单人多项目）。框架装到 `~/.pmai/`，当前 skill symlink 到 `~/.claude/skills/pmai-*` 和 `~/.codex/skills/pmai-*`；OpenCode 另生成 `~/.config/opencode/commands/pmai-*.md`。Codex 只使用原生 skills，通过 `$pmai-*` 或自然语言调用，不生成会在 Desktop 显示为 `prompts:pmai-*` 的 custom prompts。任意 cwd 可起新业务项目；`pmai upgrade` 一键升级，所有项目自动跟随。skill 只装全局一处，项目里只放 host 配置 / 状态资产（`.claude/settings.json` / `.codex/hooks.json` / `.opencode/commands` / `opencode.json` / `.work-meta.json`）——这样每个 PMAI 入口永远唯一，不会和项目副本重复。

---

## 如何使用？

用户反馈：「希望加个批量审核功能，一次能审多个待审项。」

```
# 起项目（只跑一次，整个产品的根基）

/pmai-init-project    项目初始化统一入口（AI 自动判断全新项目 / 资料目录 / 已有代码；全新项目搭底座，已有代码直接盘点现状）

# 日常循环（design 讨论，build 看结果）

/pmai-design "批量审核"    恢复旧上下文，讨论清楚并自动形成建造依据
/pmai-build 批量审核       后台读取项目定义和默认验收；PM 只确认工作环境与构建工具，然后看结果、多轮修改、说“可以提交”后自动收尾
/pmai-status          产品现状视图（产品长什么样 / 当前模块做到哪 / 下一步）
```

PM 全程**只做产品决策、确认首个建造方案、开工时确认工作环境与构建工具、看结果和明确定稿**；meta / mockup / spec-writing 分流、默认验收、合同、证据和文档同步由框架兜。

---

## 依赖

| 工具 | 必需性 | 用途 |
|---|---|---|
| **Claude Code** | 推荐 | 一等主控入口（slash skill 原生在这里跑）；当前主控不是 Claude Code 时，也可作为 `/pmai-build` 执行器 |
| **Codex** | 支持 | 原生 skill 暴露到 `~/.codex/skills/pmai-*`，通过 `$pmai-*`、skill 选择器或自然语言调用；不生成 custom prompts；读生成器仓 / 消费仓 `AGENTS.md` 作为主控入口；消费仓生成项目级 `.codex/hooks.json`；当前主控不是 Codex 时，也可作为 build 执行器 |
| **Cursor Agent** | 可选 | `/pmai-build` 外部执行器；当前主控不是 Cursor Agent 时可选 |
| **OpenCode CLI** | 支持 | OpenCode commands 暴露到 `~/.config/opencode/commands/pmai-*.md`，可直接打开消费仓输入 `/pmai-*`；读 `AGENTS.md` 作为主控入口；消费仓生成 `.opencode/commands` 和 `opencode.json`；当前主控不是 OpenCode 时，也可作为 build 执行器。第一版不复刻 Codex hooks，保护依赖 OpenCode permission、git hooks、build contract 和 changed-path review |
| **gstack** | 可选能力层 | 可辅助视觉基线、mockup、browser/visual evidence、抓站和文档导出；初始化不依赖它。UI 验收需要主动浏览器能力，但可以由 gstack、runtime browser 或 Playwright 任一适配器提供 |
| **git** ≥ 2.30 | 必需 | worktree 是核心隔离机制 |
| **python3** ≥ 3.10 | 必需 | scripts 大多用 python（zero-dep stdlib） |
| **bash** ≥ 4 | 必需 | scripts 入口语言（macOS 自带 3.x 已知坑见 INVARIANTS） |
| **codex CLI** | 可选 | `/pmai-build` 执行器；Codex 作为当前主控时不进入候选，不装可走 Claude Code / OpenCode / Cursor Agent / 手动 |

未检测到 gstack 时，`pmai install` / `pmai doctor` 只给 readiness warning，初始化和非 Web build 都不受阻塞。Web required checks 会在 final_check 前解析可用的主动浏览器适配器；完全没有适配器时 UI 验收阻塞，不能伪装通过。gstack 输出仍必须按 PMAI 规则接回 `DESIGN.md`、`mockups/`、evidence artifacts、`.pm-workflow/mirror/`、`docs/deliverables/` 或 `docs/engineering/`，不能把 `~/.gstack/...` 当长期真相源。

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
- clone 到 `~/.pmai/` + symlink skill 到 `~/.claude/skills/pmai-*` / `~/.codex/skills/pmai-*` + 生成 OpenCode slash commands 到 `~/.config/opencode/commands/pmai-*.md`；同时清理旧版遗留的 `~/.codex/prompts/pmai-*.md`
- 自动检测 shell（zsh/bash）+ 给 `~/.pmai/bin` 加 PATH 的 oneshot 命令
- 提示 gstack readiness；缺 gstack 只 warning，不影响起项。`pmai doctor --browser-smoke` 可主动验证 gstack browse，但 UI build 也可使用其它受支持的主动浏览器适配器。

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

PMAI 只有全局安装一种形态（`pmai install` → clone `~/.pmai/` + symlink `~/.claude/skills/pmai-*` / `~/.codex/skills/pmai-*` + 生成 `~/.config/opencode/commands/pmai-*.md`）。消费仓保持干净，skill 不进项目；升级一处 `pmai upgrade`，所有项目自动跟随。Codex 不再生成 custom prompts，安装和升级会清理旧版遗留的 `~/.codex/prompts/pmai-*.md`。

> 旧的 `--local`（往项目 `.claude/` 拷实体副本）已移除：它和全局并存时会让每个 `/pmai-*` 命令在菜单里重复，且副本不跟随升级而陈旧。消费仓需要的 host 配置（`.claude/settings.json` / `.codex/hooks.json` / `.opencode/commands` / `opencode.json`）仍单独放项目里（不是 skill，不会重复）；hook 脚本本体仍走 `~/.pmai/hooks` / `~/.pmai/scripts`。已有遗留副本用 `pmai uninstall --local <dir>` 清理。

**升级 / 卸载 / 状态**：

```bash
# 全局模式
pmai upgrade                          # 拉 main 最新（吃滚动版）
pmai upgrade --stable                 # 跳到最新 git tag（PM 打过的稳定 baseline）
pmai upgrade --to v0.1.0              # 锁定指定版本（回滚）

# 其他
pmai status               # VERSION + main HEAD diff
pmai doctor               # 完整性自检
pmai whats-new --from v0.2.0 --max-lines 40
pmai whats-new --from v0.2.0 --full
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

**PM 主动入口**：装好 pmai 后，**在任意 cwd**（不要求在本仓）的 Claude Code、Codex 或 OpenCode 窗口里发：

```
/pmai-init-project
```

agent 内部先判断项目情况，再进入对应分支：

- **阶段 A · 参数收集 + 项目情况判断** —— 只拿项目名、落地路径和一句话背景，再判断全新项目、资料目录、已有代码库或已接入项目；不询问类型和技术栈。
- **全新项目 / 资料目录分支** —— 用 `init-project.sh` 只建上下文脊柱和 host 配置，不创建代码、prototype、mockup 看板或 `project.yml`。
- **已有代码库分支** —— 自动整理真实代码现状并补产品脊柱；现有技术事实进入 `docs/CODEBASE-AUDIT.md`，不在接入阶段提前冻结新的建造方案。
- **已接入过 PMAI 的项目** —— 不重跑 init；先看 `/pmai-status`，PM 明确要重定方向再走 `/pmai-direction`。

两类初始化完成后都只进入 `/pmai-design`。首个可建造 design 定稿时，PM 一次确认 `prototype / product`、技术栈、代码入口和运行命令，框架生成 `.pm-workflow/project.yml`。

> `/pmai-init-project` 在装了 pmai 的任意 cwd 都能跑（无需在本仓）。

如果一个目录还没有 PMAI 初始化，任何其它 `/pmai-*` skill 被调用时都应先引导 PM 回到 `/pmai-init-project`；该入口会自动判断全新项目、资料目录或已有代码库，不要求 PM 手动选择另一个接入口。

**Codex / OpenCode 主控入口**：

- 在本生成器仓协同改框架：Codex 先读根目录 `AGENTS.md`，按 repo-local `skills/` / `scripts/` 工作。
- 在本生成器仓初始化消费仓：让 Codex 执行 `/pmai-init-project` 等价流程，内部读取 `skills/init-project/SKILL.md`，最后调用 `bash scripts/init-project.sh ...`。
- 在消费仓继续使用：`init-project.sh` 会生成消费仓根目录 `AGENTS.md` 和项目级 `.codex/hooks.json`；Codex 进入消费仓后先读 `AGENTS.md`。`pmai install/upgrade` 会把 `pmai-*` 暴露到 `~/.codex/skills/`，通过 `$pmai-*`、skill 选择器或自然语言调用，并清理旧版遗留的 `~/.codex/prompts/pmai-*.md`。Codex 首次启用项目 hooks 时可能要求信任确认，这是 Codex 自身的安全机制。
- OpenCode 进入消费仓后同样先读 `AGENTS.md`。`pmai install/upgrade` 会生成全局 `~/.config/opencode/commands/pmai-*.md`；`init-project.sh` 会生成项目级 `.opencode/commands/pmai-*.md` 和 `opencode.json`，命令同样只路由回 `PMAI_HOME` / `~/.pmai` 下的已安装 `SKILL.md`。OpenCode 第一版不做 PMAI 专属 plugin hooks，也不假装 Codex hooks 生效。

**非交互参数化 CLI**（smoke / 批量自动化依赖）：

```bash
# 优先：从 ~/.pmai/ 调用
bash ~/.pmai/scripts/init-project.sh \
  <project-name> \
  <target-dir> \
  "<background>"

# 或在本仓内调用（fallback 路径，自动推 FRAMEWORK_DIR）
bash scripts/init-project.sh ...
```

参数：
- `<project-name>` — 业务项目名（也是 git 仓的名字）
- `<target-dir>` — 业务项目落地路径（**不能已存在**）
- `<background>` — 一句话项目背景

项目类型和技术栈不属于初始化参数；旧第四参数会报迁移提示。首个可建造 design 定稿后才生成 `.pm-workflow/project.yml`。

> 脚本是骨架构建器，**不带方向讨论**；直接调脚本适合自动化场景，PM 主动起项目走 `/pmai-init-project` skill 拿到完整体验。

可量测骨架 smoke（从空目录到 `status-view.py` 可识别的项目骨架）：

```bash
bash ~/.pmai/scripts/measure-tthw.sh smoke
# 本仓调试时也可：bash scripts/measure-tthw.sh smoke
```

首个模块规格草稿的 TTHW 只能在真实 dogfood 后记录。跑完 `/pmai-init-project` → `/pmai-design` 并落出 `spec.md` 后，在业务仓外用框架脚本写一条记录：

```bash
bash ~/.pmai/scripts/measure-tthw.sh record /path/to/project \
  --module "<module-name>" \
  --started-at "2026-07-07T10:00:00+08:00" \
  --ended-at "2026-07-07T10:25:00+08:00"
```

### 2. PM 在业务仓里的日常循环

> **注意**：装好 pmai 后，所有 skill 在 Claude Code / Codex 的 host skill 目录和 OpenCode commands 里都以 `pmai-` 前缀注册（防与 gstack / 其他框架命名冲突）。下面例子中的 `/pmai-*` 是真实的命令名。

```
/pmai-design "<一句话>"      → 恢复上下文、探索真问题、按需调 meta / mockup / spec-writing，并提交建造依据
  ↓
/pmai-build <模块或文档>     → 构建 prototype 或 product；PM 看结果多轮修改，定稿后自动检查、合入 main 并更新文档
  ↓
/pmai-status             → 忘了当前停在哪时，用它读状态并提示下一步
```

简单改动可以跳过完整流程：用 `/pmai-quick-fix` 修复，需要长期归位时再用 `/pmai-record`。完整需求进入 `/pmai-build` 后，PM 说“定稿 / 可以提交 / 可以合并”即触发自动 finalize；`/pmai-build-close` 只用于兼容或中断恢复。

### 3. 多机 / 团队仓

PMAI 走纯全局：每台要用的机器各自 `pmai install` 一次（全局），消费仓里不放 skill 副本。换机器 clone 业务仓后，在该机跑一次全局安装即可在 Claude Code / Codex / OpenCode 里用 `/pmai-*`。

> 旧的 `--local`（把框架副本 commit 进业务仓 `.claude/`）已移除——它和全局并存会让命令重复、副本陈旧。若仓里还有遗留副本，清理：`pmai uninstall --local <仓目录>`（只删项目内副本，不动全局）。需要的 `.claude/settings.json` + `.codex/hooks.json` + `.opencode/commands` + `opencode.json` 保留（那些不是 skill，不会重复）。

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
| `/pmai-status` | **续跑辅助**：读当前状态和建议下一步；不向 PM 暴露 worktree、合同或证据 JSON |
| `/pmai-build` | 统一构建前台：读取 design 定稿的项目建造定义和默认验收，推荐工作环境与构建工具；PM 一次确认后构建，定稿后自动落地主线并完成文档对账 |
| `/pmai-spec-writing` | 最终目标规格成文器：把已确认决定编译成指导研发实现的模块规格、PRD、功能需求、功能描述、功能规格或功能评审稿 |
| `/pmai-doc-writing` | 介绍型文档成文器：产品介绍、产品功能清单、优势说明、一页纸、汇报材料，默认落 `docs/deliverables/` |

### 收尾 / 放弃

| Skill | 用途 |
|---|---|
| `/pmai-build-close` | **兼容与恢复入口**：中断续跑、merge 冲突恢复或 `landed/docs_pending` 文档恢复；正常链路不需要手动调用 |
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
| [`INVARIANTS.md`](./INVARIANTS.md) | 框架当前不变量（初始化、project definition、生命周期、验收、分支与文档边界） |
| [`TODOS.md`](./TODOS.md) | 待决项 / 延迟决策（v2/v4/UP/DX/Eng/TD-1~4） |
| [`docs/归档/废弃/框架同步-SOP.md`](./docs/归档/废弃/框架同步-SOP.md) | 生成器 → 业务仓 hotfix 同步流程（**DEPRECATED + 已归档**；pmai install/upgrade 承接）|
| [`docs/归档/完成/v0/`](./docs/归档/完成/v0/) | v0 原始档案（需求.md / 设计.md / 需求-v0-原始草稿.md；不再活跃，归档保留作历史）|
| [`docs/归档/完成/`](./docs/归档/完成/) | 历史设计文档（21 份，2026-04~05 阶段决策档案；v3.5 收口后归档） |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | 贡献者入口：改代码前读什么、跑什么验证、怎么报 bug |

### 开发者自检入口

| 你要确认 | 命令 |
|---|---|
| 当前安装状态 / Claude+Codex skill 暴露 / OpenCode command 是否漂移 | `pmai status` |
| 全局安装完整性（含 Claude+Codex 暴露和 OpenCode commands） | `pmai doctor` |
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
