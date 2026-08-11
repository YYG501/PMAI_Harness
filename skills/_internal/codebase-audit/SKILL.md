---
name: pmai-internal-codebase-audit
description: |
  已有代码库接入 PMAI 的内部子流程：由 /pmai-init-project 检测到源码后自动进入；扫码产出「代码现状档」（技术栈、集成、架构、结构、约定、测试、隐患七个维度，含密钥防护扫描）和经 PM 确认的模块现状清单，再核验接入前资料是否已经形成等价产品基线。代码只作为现状证据，不反向生成产品方向或目标规格。全新项目无需使用，且不作为公开 /pmai-* 命令暴露。
---

# codebase-audit（内部子流程）

## When To Use

- **默认调用路径**：PM 只需要运行 `/pmai-init-project`。当 init A 步判断目标目录是已有代码库时，自动进入本流程；不要让 PM 在 init 和本子流程之间手动选命令。
- **恢复 / 重扫**：接入流程中断、现状档需要重扫、或 PM 明确要求“重扫已有代码现状”时，仍回到 `/pmai-init-project`，由 agent 读取本内部子流程续跑。
- 新项目（空仓 / 全新）**不用**本 skill —— 直接 `/pmai-init-project`。

本流程是 `/pmai-init-project` 的已有项目分支：一个入口完成判断 → 现状盘点 → PM 过目 → 等价产品基线核验。中间保留「PM 过目现状档」的轻停顿；PM 点头后继续核验接入前已有产品材料，但不在本流程里补做产品方向讨论。

> **与 Proposal / design / record 的分工**：已有材料完整且 PM 确认仍有效，才可作为等价产品基线直接进入 design；产品定位、用户、核心问题与价值、边界或 MVP 有缺口或需要纠正时转 `/pmai-proposal`；模块问题转 `/pmai-design`；已确认事实的事后补录才可转 `/pmai-record`。

## Preamble

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
echo "SKILL: codebase-audit"
```

如果 preamble 提示当前目录还没有 PMAI 初始化：
- 从 `/pmai-init-project` 的已有代码分支自动进入时，继续本流程；这是初始化入口的内部子流程。
- PM 明确要求恢复 / 重扫现状档时，也从 `/pmai-init-project` 的恢复分支继续，不把本内部子流程展示成第二个公开入口。
- 其它情况停止，引导 PM 先发 `/pmai-init-project`，不要把本 skill 当成初始化菜单里的同级选项。

## ⚠️ 防 secret 扫描（强约束）

扫码过程会读到代码库里的配置 / 环境文件。**禁止把任何密钥 / token / 密码 / 连接串 /
私钥写进现状档**：

- 扫到敏感值 → 一律以 `<redacted>` 占位；现状档只记「这里有一个 X 类密钥，在 Y 文件」。
- `.env` / `*.pem` / `*.key` / `credentials*` / `secrets*` 等文件：只记**存在性 + 用途**，
  不抄内容。
- 隐患段如发现疑似硬编码密钥，记「发现 N 处疑似硬编码密钥，已 redact，位置 file:line」，
  **不抄密钥本身**。

## Workflow

### 步骤 0：固定接入前文件身份

在生成 `docs/CODEBASE-AUDIT.md`、补产品脊柱或写入任何其它 PMAI 文件前，先运行：

```bash
python3 "$PMAI_HOME/scripts/proposal-contract.py" capture-intake "$REPO_ROOT"
```

该命令只执行一次，生成 `.pm-workflow/intake-manifest.json`，固定接入前普通文件的仓内路径与 SHA-256；`.git`、`.pm-workflow`、依赖、缓存、构建产物目录和单文件超过 64 MiB 的大文件不进入清单，超过 100000 个候选文件则停止让 PM 先收窄目录。manifest 已存在、目录含不安全路径或固定失败时立即停止，不得在生成 audit / 脊柱后重建，也不得手改 manifest 把 PMAI 后生成材料伪装成接入前依据。

### 步骤 1：确认审计范围

向 PM 确认：要审计的代码库根目录（由 `/pmai-init-project` 自动分流进入时，默认就是 init A 步确认的目标目录）；有无要排除的目录（如 `vendor/` /
`node_modules/`、`.build/`、`DerivedData/` —— 这些本就该跳过）。

### 步骤 2：扫码 7 维度

用 read-only 工具（Glob / Grep / Read；大范围探索可派 read-only subagent fan-out）盘点
7 个维度，逐维写进 `docs/CODEBASE-AUDIT.md`（按 `$PMAI_HOME/skills/_internal/codebase-audit/templates/codebase-audit.md.tmpl`）：

| # | 维度 | 扫什么 |
|---|---|---|
| 1 | 技术栈 | 语言 / 框架 / 运行时 / 包管理器 / 构建工具 + 版本（读 package.json / 锁文件 / 配置）|
| 2 | 外部集成 | 依赖的外部服务 / API / 数据库 / 第三方 SDK（连接串一律 `<redacted>`）|
| 3 | 架构 | 整体形态（单体 / 前后端分离 / 微服务）/ 分层 / 数据流向 |
| 4 | 目录结构 | 顶层目录树 + 关键目录职责 |
| 5 | 代码约定 | 命名 / 文件组织 / 状态管理 / 错误处理 / 注释风格 |
| 6 | 测试现状 | 有无测试 / 框架 / 覆盖面 / 怎么跑 |
| 7 | 隐患 | 技术债 / 风险点 / 安全隐患（含疑似硬编码密钥，已 redact）|

### 步骤 3：产出现状档 + PM 确认

写完 `docs/CODEBASE-AUDIT.md` 后呈交 PM：

```
✅ 代码现状档：docs/CODEBASE-AUDIT.md

📋 7 维度盘点完成：技术栈 <一句> / 集成 N 个 / 架构 <一句> / 隐患 M 项

这份现状档准吗？有补充 / 纠正直接说。
你过目后说「继续」，我接着核对已有产品材料能否作为接下来的产品基线。
```

PM 提修正 → 改现状档 → 重新呈交。

> **这是一个轻停顿，不是流程终点**：现状档是产品基线核验的证据之一，留这个停顿让 PM 先把代码事实看准。PM 说「继续 / OK」→ 进 step 3.5 / 3.5.5 兜底，再进 step 4。代码现状不能代替产品方向；step 4 发现产品级缺口时转 `/pmai-proposal`。

### 步骤 3.5：确认模块现状清单（只记代码事实）

代码目录、菜单和路由能证明当前实现分成哪些区域，但不能证明未来应该怎样划分产品模块，也不能证明角色、业务规则和目标边界。本步骤只把可核验的当前形态补进 `docs/CODEBASE-AUDIT.md`，不创建或更新任何模块 `spec.md`。

1. **抽候选区域**：扫描 `src/modules/*`、`src/pages/*`、`src/features/*`、`apps/*`、`packages/*`，以及路由 / 菜单配置里的顶级分组；合并明显重复的代码命名，但不把技术目录直接宣布为产品模块。
2. **请 PM 校准现状**：逐项展示当前名称、可见入口 / 页面、代码证据和不确定边界。明确说明“这是现状清单，不是目标规格”；PM 可以合并、拆分、改名、排除或补充。
3. **写回现状档**：PM 确认后，把清单写入 `docs/CODEBASE-AUDIT.md` 的“模块现状清单”段。每项只写当前可观察职责、入口和证据路径；无法确认的边界标“待后续 design 确认”。若没有稳定区域，如实写“暂未识别”，不要强凑模块。
4. **保持目标合同为空**：本流程不生成 `docs/modules/<m>/spec.md`，不刷新 `docs/modules/INDEX.md`。后续 `/pmai-design` 可把现状清单作为证据，但只有 PM 确认的产品判断才能进入目标规格。

### 步骤 3.5.5：缺失时建立统一 DESIGN.md 骨架

`DESIGN.md` 是涉及界面工作时的项目级设计上下文。codebase-audit 只保证基础文件存在，不从现有代码反推未来视觉规则，也不补写已有文件。

| 状态 | 行为 |
|---|---|
| 已有 `DESIGN.md` | 保持原文件不动；缺什么由后续真实 UI design 按需处理 |
| 缺少 `DESIGN.md` | 按 `$PMAI_HOME/templates/DESIGN.md.tmpl` 建立统一空骨架，只替换项目名占位符 |

统一模板已经说明 gstack `design-consultation` 只是可选辅助、不是依赖；结合边界见 `skills/_shared/gstack-integration.md`。本流程不要求 PM 另跑设计工具。

告知 PM：`DESIGN.md` 已存在并保持不动，或已按统一模板建立空骨架。不要追加固定段落清单或额外操作建议。

### 步骤 3.5.7：PRODUCT-STATE.md 首次接入兜底

> **跟 step 3.5 / 3.5.5 的关系**：同属首次接入的基础上下文准备；模块现状确认、DESIGN.md 缺失兜底和本步骤依次完成，不另设流程选择。

**为什么有这步**：`PRODUCT-STATE.md` 是产品「现状层」hub，下游 `/pmai-design` 开头**强制读它**（当前功能 / 主原型现状 / mock-真状态位）。greenfield 的 `init-project.sh` 会铺这个模板，但 brownfield 走 codebase-audit 从不建它 → PM 第一个模块设计退化成「白纸起步」，audit 已扫到的全部现状在 `/pmai-design` 入场时丢失。本步骤兜底建 + 从现状档反推填充。

> **防腐豁免（必读，否则 review 会误判 BLOCKER）**：`PRODUCT-STATE.md` 模板写「只在 landed 后自动文档编译或 record 的收敛点更新」（防腐铁律）。**brownfield 首次 bootstrap 不违反**——首次建档 vs 后续随手改是两回事；codebase-audit 填的是 audit 已扫到的**现状事实**，不是凭空编未来。bootstrap 态由顶部状态行明确标出，与后续事实编译态区分。**反推只引用 `CODEBASE-AUDIT.md` 已落事实 + 可验证代码扫描；扫不到的层填「未知 / 待确认」不猜测**（防 narrative 幻觉）。

```bash
PRODUCT_STATE_MD="$REPO_ROOT/PRODUCT-STATE.md"
HAS_PS=false
[ -f "$PRODUCT_STATE_MD" ] && HAS_PS=true
```

| 状态 | 行为 |
|---|---|
| HAS_PS=true | silent skip（已有，不覆盖） |
| HAS_PS=false | AI 用 Write 套 `$PMAI_HOME/templates/PRODUCT-STATE.md.tmpl` 建骨架 + 反推填三段 + 顶部状态行 |

**反推填充映射**（产品现状 = 已发生事实，直接反推、不设 PM 确认门——与反推未来待办需 PM 拍板顺序本质不同）：

| PRODUCT-STATE 段 | 从哪反推 |
|---|---|
| 当前功能 / 能力 | `CODEBASE-AUDIT.md` §3 架构 + §4 目录结构 + 路由 / 菜单扫描的功能面，每条 ≤ 一行 |
| 当前产品形态 | 按 audit §4 页面 / 路由列已有页面区域，备注「源自现有 codebase」；若连页面都没有，如实写「尚无可运行界面」。此处不预设未来代码根。 |
| 实现深度状态（mock / 真） | 按 audit §1 技术栈 + §2 外部集成反推每层真 / mock（brownfield 有真 DB / 真后端的层填「真系统」，何时转列填「接入时已是」或「—」；扫不到的层填「未知」） |
| 产品定位一句话 | **留空占位**，step 4 确认等价产品基线后回填；若转 Proposal，则继续留空等待 Proposal 同步产品基线 |

**顶部状态行**（插在 H1 标题之前）：

```markdown
<!-- 状态：草稿 | 由 codebase-audit step 3.5.7 反推 bootstrap | 未经 PM 逐行确认 | 产品定位一句话待产品基线确认后回填 -->
```

**告知 PM**：

```
📝 PRODUCT-STATE.md 兜底：<已建骨架 + 反推填现状三段 / 已存在跳过>
  产品定位一句话留空，待产品基线确认后回填
```

### 步骤 4：核验等价产品基线并分流

PM 在 step 3 轻停顿说「继续」后，核验接入前已有产品材料是否已经形成等价产品基线。**这里只验证已有判断，不通过一轮临时问卷补出产品方向。**

**怎么跑**：

1. **@读 `skills/_shared/project-questioning.md`**（等价产品基线核验的单一真相源）。
2. **全文读 `docs/CODEBASE-AUDIT.md`**，再按相关性读取 intake manifest 中路径与当前 hash 均一致的接入前产品立项、正式 PRD、产品说明、用户研究和已生效决定；audit 本身不能作为 `主要依据`。
3. 对照共享规则核验六项：产品定位、主用户、核心问题与价值、产品边界、MVP / 当前产品结果、当前有效性。每项必须有材料路径或 PM 本轮明确确认；不得从代码补出产品判断。model / API 命名只作为待核对的当前用词证据，不自动成为稳定业务术语。
4. **资料完整且一致**：展示证据卡，由 PM 确认是否仍有效。确认后按 `_shared/project-questioning.md` 的固定字段把稳定结论、至少一个命中 intake manifest 且 hash 未变的真实仓内依据路径和 PM 确认日期同步到 `PRODUCT.md`，再移除 `PMAI_PROPOSAL_REQUIRED` 标记；回填 `PRODUCT-STATE.md` 的定位一句话，并把 manifest、产品脊柱、audit 与依据一并精确提交。运行 `python3 "$PMAI_HOME/scripts/proposal-contract.py" status "$REPO_ROOT"`，只有机器状态返回 `equivalent_baseline`，唯一 Next Up 才是 `/pmai-design "<第一个模块结果>"`。
5. **任一项缺失、冲突或 PM 要重判**：保留 `PMAI_PROPOSAL_REQUIRED` 标记，不把临时答案写进 `PRODUCT.md`；提交 codebase audit 与已建立的上下文骨架后，唯一 Next Up 为 `/pmai-proposal`。
6. 两个分支都不生成 `.pm-workflow/project.yml`，不向旧 `config.yml` 写 `project.type`。TODO 只保留 PM 已经明确提出的事项，不从代码或基线缺口反推。

## Rules

- **代码只作现状证据**：步骤 1-3.5 只读代码，不改业务实现；代码扫描结果只进入 `docs/CODEBASE-AUDIT.md`，不得反向生成或改写目标 `spec.md`。
- **防 secret 是硬约束**：见上方「防 secret 扫描」段，违反 = 严重错误。
- **产品基线核验走共享真相源**：step 4 必须 @读 `skills/_shared/project-questioning.md`；缺口直接转 Proposal，不在本 skill 里补做产品讨论。
- **接入前身份先固定**：step 0 必须发生在任何 PMAI 写入前；后续只接受 intake manifest 中且 hash 未变的主要依据，禁止重建或改写 manifest。
- **与 `/pmai-init-project` 分工**：本 skill 是 init 的已有项目分支，不是初始化时让 PM 手动选择的并列入口。
- **与后续入口分工**：产品方向不清或纠正走 `/pmai-proposal`；模块对象、规则、流程、权限和交互未定走 `/pmai-design`；无 active work 时补录已确认事实才走 `/pmai-record`。
- 新项目不用本 skill（无已有代码可审）。
- step 3.5 模块现状清单由 PM 确认；它仍只是当前证据，不替 PM 决定目标模块边界。

## 边界

- **允许产出**：
  - `docs/CODEBASE-AUDIT.md`（默认）
  - `.pm-workflow/intake-manifest.json`（step 0，仅在任何 PMAI 写入前生成一次）
  - `PRODUCT-STATE.md` 兜底建骨架（**step 3.5.7 无条件**，反推填现状三段，产品定位一句话 step 4 回填）
  - `PRODUCT.md` + `TODO.md`（step 4 只同步接入前已有且经 PM 确认仍有效的产品基线与待办）
  - `DESIGN.md` 统一空骨架（**仅在文件缺失时**；已有文件不动）
- **允许动作**：read-only 扫码、7 维度盘点、防 secret redact、把 PM 确认的模块现状清单写回 `CODEBASE-AUDIT.md`、缺失时按统一模板建立 `DESIGN.md`、step 3.5.7 兜底 PRODUCT-STATE.md、step 4 核验并同步已有等价产品基线。
- **禁止**：改代码 / 从代码生成或改写 `docs/modules/<m>/spec.md` / 刷新模块规格索引 / 补写已有 `DESIGN.md` / 用问卷补齐产品级缺口 / 把代码现状当作产品价值或边界 / step 3.5 跳过模块现状清单 PM 确认环节。
- **退出条件**：现状档与模块现状清单经 PM 确认 + DESIGN.md / PRODUCT-STATE.md 兜底完成 + step 4 得出明确分流并提交接入文档。等价基线成立时 Next Up 为 `/pmai-design`；否则为 `/pmai-proposal`。目标 `spec.md` 与 `project.yml` 留给首个可建造 design 生成。
