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
~/.pmai/bin/pmai doctor --check
# 需要确认 /browse runtime 真能启动时再跑主动 smoke：
~/.pmai/bin/pmai doctor --browser-smoke
```

装好后，在任意业务项目目录里使用当前宿主的原生入口：

```text
Claude Code: /pmai-init-project
Codex:       $pmai-init-project
```

Kimi Code、OpenCode 和 Cursor Agent 不作为 PMAI 主控；它们只会在 `/pmai-build` 中被完整主控选作外部 Builder。

如果只是要验证骨架脚本，不走完整 PM 交互：

```bash
tmp=$(mktemp -d)
bash ~/.pmai/scripts/init-project.sh Demo "$tmp/Demo" "一句话项目背景"
python3 ~/.pmai/scripts/status-view.py "$tmp/Demo" --narrative
```

---

## 这是什么

PMAI 是面向 PM 的**产品上下文统一层**：它把产品文档、原型、反馈、决策和后续实现上下文接起来，让 AI 在每次协作时都知道这个产品是什么、已有原型长什么样、哪些规则和取舍已经确认。

PMAI 不和 Claude Design、design-html 或 Claude Code 比"谁更快生成第一版原型"。它负责把 Product Proposal 的产品澄清、模块设计、规格成文、prototype / product 构建、PM 看结果多轮修改、最终验收、合入 main 和正式文档对齐接成同一条链路。新需求从已有产品上下文继续生长，PM 只处理产品判断、看结果和明确定稿。

定位是 **PM 单人生产力工具**，不是团队 SOP / CI 平台 / 多租户基础设施。完整产品意义、非目标和成功标准见 [`PRODUCT.md`](./PRODUCT.md)。

**分发形态**：全局安装（单人多项目）。框架装到 `~/.pmai/`，公开 Skill 只链接到 `~/.claude/skills/pmai-*` 和 `~/.codex/skills/pmai-*`；Codex 通过 `$pmai-*`、Skill 选择器或自然语言调用，不生成 custom prompts。任意 cwd 可由 Claude Code 或 Codex 起新业务项目；`pmai upgrade` 一键升级全局 Skill、脚本和 Hook 源。项目级 `.claude/settings.json` / `.codex/hooks.json` 不会被全局升级静默改写：在消费仓使用 `/pmai-doctor` 只读检查漂移，PM 确认后再运行 `bash ~/.pmai/scripts/install-project-hooks.sh` 确定性刷新。Kimi Code、OpenCode 和 Cursor Agent 只保留 Builder adapter/profile；新安装、新升级和新消费仓不再创建它们的 PMAI 主控入口。已有 Kimi Skill/managed hooks 与 OpenCode commands 只由 Doctor 报告，并可在 PM 确认后通过 uninstall 清理。

---

## 如何使用？

用户反馈：「希望加个批量审核功能，一次能审多个待审项。」

```
# 起项目（只跑一次，整个产品的根基）

/pmai-init-project    项目初始化统一入口（AI 自动判断全新项目 / 资料目录 / 已有代码；全新项目搭底座，已有代码直接盘点现状）
/pmai-proposal        新项目默认完成产品澄清，形成完整 Product Proposal

# 正常循环（design 讨论，spec-writing 成文，build 看结果）

/pmai-design "批量审核"    恢复旧上下文，讨论清楚并自动形成建造依据
/pmai-spec-writing          决定闭合后由 design 自动调用，编译已确认规格
/pmai-build 批量审核       后台读取项目定义和默认验收；PM 只确认工作环境与构建工具，然后看结果、多轮修改、说“可以提交”后自动收尾
```

新项目默认按 `init → proposal → design → spec-writing → build` 推进；成熟项目只有在已有资料完整覆盖产品定位、用户、核心问题与价值、边界和 MVP / 当前产品结果，并在 `PRODUCT.md` 记录真实仓内依据与 PM 确认日期、`PRODUCT.md` 与依据均已提交且无漂移、通过机器门后才可跳过 Proposal。一旦进入 Proposal 就会完成整份文档，不提供简版退出。PM 全程**只做产品决策、确认首个建造方案、开工时确认工作环境与构建工具、看结果和明确定稿**；meta / mockup / spec-writing 分流、默认验收、合同、证据和文档同步由框架兜。忘了当前停在哪里时再用 `/pmai-status` 恢复现状，它不是日常循环的一步。

上述主链只由 Claude Code 或 Codex 主控推进；外部 Builder 只接收已确认的实现任务，不能推进 lifecycle、写验收通过或触发 landing。

---

## 依赖

| 工具 | 必需性 | 用途 |
|---|---|---|
| **Claude Code** | 推荐 | 一等主控入口（slash skill 原生在这里跑）；当前主控不是 Claude Code 时，也可作为 `/pmai-build` 执行器 |
| **Codex** | 支持 | 原生 skill 暴露到 `~/.codex/skills/pmai-*`，通过 `$pmai-*`、skill 选择器或自然语言调用；不生成 custom prompts；读生成器仓 / 消费仓 `AGENTS.md` 作为主控入口；消费仓生成项目级 `.codex/hooks.json`；当前主控不是 Codex 时，也可作为 build 执行器 |
| **Kimi Code** | 可选 | 仅 `/pmai-build` 外部 Builder；通过 `kimi --prompt` 执行冻结任务，不安装 PMAI Skill 或 managed hooks；旧主控资产只诊断、清理 |
| **Cursor Agent** | 可选 | `/pmai-build` 外部执行器；当前主控不是 Cursor Agent 时可选 |
| **OpenCode CLI** | 可选 | 仅 `/pmai-build` 外部 Builder；通过 `opencode run` 执行冻结任务，不生成全局或项目级 PMAI commands；旧 command 资产只诊断、清理 |
| **gstack** | 可选能力层 | 可辅助视觉基线、mockup、browser/visual evidence、抓站和文档导出；初始化不依赖它。UI 验收需要主动浏览器能力，但可以由 gstack、runtime browser 或 Playwright 任一适配器提供 |
| **git** ≥ 2.30 | 必需 | worktree 是核心隔离机制 |
| **python3** ≥ 3.10 | 必需 | scripts 大多用 python（zero-dep stdlib） |
| **bash** ≥ 4 | 必需 | scripts 入口语言（macOS 自带 3.x 已知坑见 INVARIANTS） |
| **codex CLI** | 可选 | `/pmai-build` 外部执行器；Codex 作为当前主控时不重复进入外部候选，但当前主控直接构建始终可选。不装可走 Claude Code / OpenCode / Cursor Agent，或由当前会话直接构建 |

未检测到 gstack 时，`pmai install` / `pmai doctor --check` 只给 readiness warning，初始化和非 Web build 都不受阻塞。Web final checks 会在 PM 请求定稿后解析可用的主动浏览器适配器；完全没有适配器时 UI 验收阻塞，不能伪装通过。gstack 输出仍必须按 PMAI 规则接回 `DESIGN.md`、`mockups/`、evidence artifacts、`.pm-workflow/mirror/`、`docs/deliverables/` 或 `docs/engineering/`，不能把 `~/.gstack/...` 当长期真相源。

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
~/.pmai/bin/pmai doctor --check
```

或走 SSH：

```bash
ssh -T git@github.com
git clone git@github.com:YYG501/PMAI_Workflow.git /tmp/pmai-src
bash /tmp/pmai-src/bin/pmai install
~/.pmai/bin/pmai doctor --check
```

安装成功后，`pmai install` 末尾会：

- clone 到 `~/.pmai/`，只把公开 Skill 链接到 `~/.claude/skills/pmai-*` 和 `~/.codex/skills/pmai-*`，同时清理旧版遗留的 `~/.codex/prompts/pmai-*.md`
- 不创建或刷新 Kimi Skill、Kimi managed hooks、OpenCode commands；Doctor 只报告这些遗留主控资产，不自动删除
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
~/.pmai/bin/pmai doctor --check    # 只读完整性与消费仓检查
```

> 临时 `/tmp/pmai-src` clone 只是 installer 容器，装完可删；真正稳定的副本在 `~/.pmai/`（pmai 自己 clone 的，`pmai upgrade` 拉它）。如果你在本仓 checkout 内直接 `bash bin/pmai install`，`pmai install` 仍会按 `PMAI_REMOTE` / 默认 remote 另 clone 一份到 `~/.pmai/`。

### 安装模式：仅全局

PMAI 只有全局安装一种形态（`pmai install` → clone `~/.pmai/` + symlink `~/.claude/skills/pmai-*` / `~/.codex/skills/pmai-*`）。消费仓保持干净，Skill 不进项目；`pmai upgrade` 后所有项目自动使用新版全局 Skill / scripts / hooks 源，但项目级 Claude Code / Codex hook 配置需要在各消费仓由 `/pmai-doctor` 只读检测，并在 PM 确认后用 `bash ~/.pmai/scripts/install-project-hooks.sh` 刷新。Codex 不生成 custom prompts；Kimi/OpenCode 不注册 PMAI 主控入口。

> 旧的 `--local`（往项目 `.claude/` 拷实体副本）已移除：它和全局并存时会让每个 `/pmai-*` 命令在菜单里重复，且副本不跟随升级而陈旧。新消费仓只保留 `.claude/settings.json`、`.codex/hooks.json` 和工作流状态；已有项目级 Skill 副本、`.opencode/commands`、`opencode.json`、Kimi Skill 或 managed hooks 都是兼容清理对象。已有遗留副本用 `pmai uninstall --local <dir>` 清理。

**升级 / 卸载 / 状态**：

```bash
# 全局模式
pmai upgrade                          # 拉 main 最新（吃滚动版）
pmai upgrade --stable                 # 跳到最新 git tag（PM 打过的稳定 baseline）
pmai upgrade --to v0.1.0              # 锁定指定版本（回滚）

# 其它框架命令
pmai doctor --check       # 只读检查框架、宿主入口、消费仓文件归位与工作状态
pmai doctor --repair      # 明确修复全局宿主入口，执行前需确认
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
> - **产品基线 + 第一个模块规格草稿**：新项目从 `/pmai-init-project` 经完整 `/pmai-proposal`，再由 `/pmai-design` 调用 spec-writing 落出 `spec.md`；这段包含产品级和模块级 PM 决策，只能通过 dogfood 分段记录，不适合作无交互脚本硬测。
> - install 自身通常约 5 秒（git clone + symlink），剩余时间主要是 PM 思考第一个需求。

### 1. 初始化新业务项目

**PM 主动入口**：装好 pmai 后，**在任意 cwd**（不要求在本仓）的 Claude Code 或 Codex 窗口里使用对应原生入口：

```
Claude Code: /pmai-init-project
Codex:       $pmai-init-project
```

agent 内部先判断项目情况，再进入对应分支：

- **阶段 A · 参数收集 + 项目情况判断** —— 只拿项目名、落地路径和一句话背景，再判断全新项目、资料目录、已有代码库或已接入项目；不询问类型和技术栈。
- **全新项目 / 资料目录分支** —— 用 `init-project.sh` 只建上下文脊柱和 host 配置，不创建代码、prototype、mockup 看板或 `project.yml`；资料目录随后继续核验接入前材料，不能把骨架完成当成产品基线已通过。
- **已有代码库分支** —— 自动整理真实代码现状并补产品脊柱；现有技术事实进入 `docs/CODEBASE-AUDIT.md`，不在接入阶段提前冻结新的建造方案。
- **已接入过 PMAI 的项目** —— 不重跑 init；先看 `/pmai-status`。产品定位、目标用户、核心价值、职责边界或 MVP 证明目标需要纠正时走 `/pmai-proposal` 生成完整新版本；模块行为变化走 `/pmai-design`。

全新项目初始化完成后只进入 `/pmai-proposal`；成熟资料目录或已有代码库若已经有完整等价产品基线，且接入流程已经在 `PRODUCT.md` 记录依据路径和 PM 确认日期、产品基线与依据均已提交且无漂移、机器核验通过，才直接进入 `/pmai-design`，缺任一产品级关键判断则先补 Proposal。Proposal 定稿后由 design 收敛第一个模块，决定闭合时自动调用 spec-writing；首个可建造 design 定稿时，PM 一次确认 `prototype / product`、技术栈、代码入口和运行命令，框架生成 `.pm-workflow/project.yml`。

> `/pmai-init-project` 是跨主控工作流名；Claude Code 使用 slash skill，Codex 使用 `$pmai-init-project`。装好 pmai 后可在任意 cwd 使用，无需先进入本仓。

如果一个目录还没有 PMAI 初始化，任何其它 `/pmai-*` skill 被调用时都应先引导 PM 回到 `/pmai-init-project`；该入口会自动判断全新项目、资料目录或已有代码库，不要求 PM 手动选择另一个接入口。

**Claude Code / Codex 主控与外部 Builder**：

- 在本生成器仓协同改框架：Codex 先读根目录 `AGENTS.md`，按 repo-local `skills/` / `scripts/` 工作。
- 在本生成器仓初始化消费仓：让 Codex 执行 `/pmai-init-project` 等价流程，内部读取 `skills/init-project/SKILL.md`，最后调用 `bash scripts/init-project.sh ...`。
- 在消费仓继续使用：`init-project.sh` 会生成消费仓根目录 `AGENTS.md` 和项目级 `.codex/hooks.json`；Codex 进入消费仓后先读 `AGENTS.md`。`pmai install/upgrade` 会把 `pmai-*` 暴露到 `~/.codex/skills/`，通过 `$pmai-*`、skill 选择器或自然语言调用，并清理旧版遗留的 `~/.codex/prompts/pmai-*.md`。Codex 首次启用项目 hooks 时可能要求信任确认，这是 Codex 自身的安全机制。
- Claude Code 和 Codex 负责读取产品真相源、执行完整 Skill、采集证据并推进 lifecycle；项目级 Hook 只为这两个主控生成和维护。
- Kimi Code、OpenCode 和 Cursor Agent 只能由 `/pmai-build` 通过 adapter/profile 启动，在已确认的 `BUILD_DIR` 中产出候选 diff。它们不能调用 PMAI Skill、修改产品权威文档、写验收通过或处理 landing。
- 旧 Kimi/OpenCode 主控资产不会被 install、upgrade 或 Doctor repair 刷新；Doctor 将其列为非阻断遗留项，清理由 PM 单独确认。

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

首个模块规格草稿的 TTHW 只能在真实 dogfood 后记录。新项目跑完 `/pmai-init-project` → `/pmai-proposal` → `/pmai-design`，并由 design 调用 spec-writing 落出 `spec.md` 后，在业务仓外用框架脚本写一条记录：

```bash
bash ~/.pmai/scripts/measure-tthw.sh record /path/to/project \
  --module "<module-name>" \
  --started-at "2026-07-07T10:00:00+08:00" \
  --ended-at "2026-07-07T10:25:00+08:00"
```

### 2. PM 在业务仓里的主路径

> **注意**：装好 pmai 后，所有 Skill 都以 `pmai-` 前缀注册（防与其它框架命名冲突）。下面用 `/pmai-*` 表示跨主控工作流名；Claude Code 使用 slash skill，Codex 对应 `$pmai-*`。

```
/pmai-init-project           → 每个项目只在首次初始化或首次接入已有代码时使用
  ↓
/pmai-proposal               → 新项目默认完成；澄清产品为何成立、为谁解决什么、先证明什么，并生成完整 Product Proposal
  ↓
/pmai-design "<一句话>"      → 恢复上下文、探索真问题，内部按需完成产品判断、界面探索和规格成文
  ↓
/pmai-spec-writing           → 决定闭合后由 design 自动调用；用通用内容模块和领域 Profile 编译规格，完整 PRD 按 Preset 编排
  ↓
/pmai-build <模块或文档>     → 构建 prototype 或 product；PM 看结果多轮修改，定稿后自动检查、合入 main 并更新文档
```

这是正常协作的完整主路径，不需要再从 Skill 菜单里挑下一步。成熟项目只有在完整等价产品基线经过接入核验、显式记录依据与 PM 确认日期、相关文件已提交且无漂移并通过机器门时，才可从 design 开始；一旦走 Proposal 就必须完成完整文档。Profile 负责补充领域内容，可叠加企业平台与 AI 两份；Preset 只决定文档形态，完整 PRD 使用唯一 Preset。忘了当前停在哪里时，用 `/pmai-status` 只读恢复现状；它不是主流程的固定一步。

产品方向纠正回 `/pmai-proposal`，并用完整新版本取代旧版；模块对象、规则、任务路径、权限或关键交互变化回 `/pmai-design`；没有 active work 时，已经确认的待办、术语、跨模块规则或历史理路才用 `/pmai-record` 补录。record 和其它下游 Skill 都不能修改 Proposal。简单改动、介绍型文档、飞书文档同步或评审回收等专项场景，PM 直接说明想做什么即可，AI 负责选择对应能力并接回当前产品上下文。飞书入口只按意图区分：本地内容发布或更新到飞书用 `/pmai-publish-to-lark`；明确以飞书为准、不需要判断时用 `/pmai-sync-from-lark`；需要理解正文或批注对产品的影响时用 `/pmai-lark-review`。完整需求进入 `/pmai-build` 后，AI 会在 PM 看结果期间持续修改；PM 说“定稿 / 可以提交 / 可以合并”即触发最终检查、自动落地主线和文档同步。

### 3. 多机 / 团队仓

PMAI 走纯全局：每台要用的机器各自 `pmai install` 一次（全局），消费仓里不放 Skill 副本。换机器 clone 业务仓后，在该机跑一次全局安装即可由 Claude Code 使用 `/pmai-*`，或由 Codex 使用 `$pmai-*`。Builder CLI 只需在准备把它选作构建工具的机器上安装。

> 旧的 `--local`（把框架副本 commit 进业务仓 `.claude/`）已移除——它和全局并存会让命令重复、副本陈旧。若仓里还有遗留副本，清理：`pmai uninstall --local <仓目录>`（只删项目内副本，不动全局）。`.claude/settings.json` 与 `.codex/hooks.json` 保留；旧 `.opencode/commands` 和 `opencode.json` 不再属于当前消费仓配置。

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
| 全局框架、宿主入口和当前消费仓的文件归位、原型/实现入口、活动工作是否健康 | `pmai doctor --check` |
| 明确修复 PMAI 管理的全局宿主入口 | `pmai doctor --repair` |
| 测试整个生成器仓 | `bash tests/run-all.sh` |
| 旧 `requirements/active|closed` 仓库是否还需要人工迁移 | `python3 scripts/migrate-reqs-to-modules.py --dry-run <repo>` |

在本仓里直接跑 `bash bin/pmai doctor --check` 时，它检查的仍是 `PMAI_HOME`
（默认 `~/.pmai`）这个安装目标；输出顶部会标明 `CLI source` 和 `Audit target`。
如果你想测真实用户入口，直接跑 `~/.pmai/bin/pmai doctor --check`。CLI 不再提供
`pmai status`；对话中的 `/pmai-status` 只查看产品进度。

消费仓检查按项目阶段执行：初始化完成时不要求代码、`mockups/` 或
`.pm-workflow/project.yml`，但新项目要求继续完成 Proposal；当前 Proposal 定稿或完整等价产品基线成立后才可进入 design，首个 design 定稿后才检查建造定义，进入 build 后再检查
真实实现入口、模块状态和恢复证据。探索稿固定在 `mockups/`，正式 prototype / product
的位置以 `project.yml:implementation` 为准。doctor 只列差异，不自动搬文档、移动代码或改状态。

### 反馈与问题报告

需要复盘一次 PMAI 协作、把流程问题交给框架仓时，PM 直接说“复盘这次对话”。当前只有 Codex 的消费仓当前会话精确定位已经验证；其它宿主在没有经过验证的定位适配前，不按“最近会话”猜测。

有 bug 时优先开 GitHub issue，使用
[`bug_report.md`](./.github/ISSUE_TEMPLATE/bug_report.md) 模板。请贴：

- 你跑的是 repo-local `bash bin/pmai ...` 还是 installed `~/.pmai/bin/pmai ...`
- 完整命令 / slash skill 名
- `pmai doctor --check` 输出
- 如果问题发生在生成器仓，附 `bash tests/run-all.sh` 汇总

---

## 当前状态

生成器骨架（scripts / skills / templates / tests）齐全，框架功能完整。

**当前进度、测试基线、下一步**见 [`RUNTIME.md`](./RUNTIME.md)「当前位置」—— 单一真相源，本文件不重复。
