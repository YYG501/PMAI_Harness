---
name: pmai-init-project
description: |
  项目初始化统一入口：判断全新项目、资料目录、已有代码库或已接入项目；只建立产品上下文脊柱，不提前决定 project.type、技术栈、框架或代码骨架。全新项目和缺少等价产品基线的项目初始化后进入 /pmai-proposal；已有资料经核验并显式记录依据与 PM 确认日期、机器状态为 equivalent_baseline 时才可直接进入 /pmai-design。
---

# /pmai-init-project · 只建立产品上下文

执行前完整读取 `skills/_shared/pm-view/banner-rules.md`；所有 banner、确认门和 Next Up 按共享 PM 视图规则输出。

## 定位

初始化只回答一件事：**建立产品上下文骨架，并判断下一步是先澄清产品方向，还是已有等价基线可以直接设计模块**。

统一主链是：

```text
/pmai-init-project
→ /pmai-proposal 澄清用户、问题、价值、边界与 MVP
→ /pmai-design 明确第一个可建造需求
→ design 定稿时确定 project.type、技术栈和框架
→ design 自动调用 /pmai-spec-writing 编译已确认规格
→ /pmai-build
```

因此本 skill 不做以下事情：

- 不询问 `prototype / product`；
- 不创建 `.pm-workflow/project.yml`；
- 不创建 `prototype/`、真实产品代码、脚手架或 `.dev-port`；
- 不预设 Next.js、pnpm、dev server 或浏览器工具；
- 不把 mockup 或 build 列成初始化后的并列入口。

gstack 在初始化阶段完全可选。缺失 gstack 不阻塞项目建立；真正需要页面验收时，由 build 的 acceptance profile 要求主动浏览器能力。

## 初始化产物

全新项目或资料目录完成后只建立：

| 产物 | 作用 |
|---|---|
| `PRODUCT.md` | 项目名、一句话背景、当前 Proposal 指针及后续同步的精简产品基线 |
| `PRODUCT-STATE.md` | 当前产品事实骨架 |
| `DESIGN.md` | 设计基线骨架；首个 UI design 再按真实需求补充 |
| `PRODUCT-RULES.md` | 跨模块现行规则 |
| `TODO.md` | PM 主动提过的待办池 |
| `docs/` | proposals、modules、decisions、inputs、engineering、deliverables、archive 等资料结构 |
| `.pm-workflow/config.yml` | 只保存 builder profile 等执行器偏好 |
| `.pm-workflow/intake-manifest.json` | 资料目录 / 已有代码库接入前固定的原文件路径与 hash；全新项目不生成 |
| host 配置 | `AGENTS.md`、`CLAUDE.md`、hooks 和 OpenCode commands |

`mockups/` 在 design 真正需要交互分岔时由 `/pmai-mockup` 创建；代码目录和 `.pm-workflow/project.yml` 在 design 定稿后才创建或声明。

## Workflow

### A · 收集最小上下文并判断目录

先输出：

```bash
echo "━━━ PMAI ► INIT-PROJECT ▸ 项目识别 ━━━"
```

收集三个值：

1. 项目名；
2. 落地路径；
3. 一句话背景：这是什么产品、主要给谁、解决什么。

不得在本步询问项目类型、技术栈、框架或 dev server。

只读检查目标目录和当前目录，将情况分成四类：

- **全新项目**：目标不存在或为空；
- **资料目录**：只有文档、图片、表格等资料，没有代码工程标志；
- **已有代码库**：存在源码、依赖清单、工程文件或 Git 历史；
- **已接入 PMAI**：存在根目录产品脊柱、`.pm-workflow/config.yml`、PMAI host 配置或明确 PMAI 标记。

已接入项目不重跑初始化：引导 `/pmai-status`；需要重判定位、用户、价值、边界或 MVP 时走 `/pmai-proposal`。

资料目录只有在 PM 明确确认接住现有内容后，才给脚本传 `--allow-existing`。脚本会在任何 PMAI 骨架写入前生成 `.pm-workflow/intake-manifest.json`，固定接入前普通文件的仓内相对路径与 SHA-256；依赖、构建产物、缓存目录和单文件超过 64 MiB 的大文件不进入 manifest，超过 100000 个候选文件则停止让 PM 先收窄目录。脚本随后检查并写入脊柱，不覆盖也不自动合并。已有代码库进入 E，不调用初始化脚本，但必须先按 E 的步骤 0 生成同一 manifest。

### B · 建立上下文脊柱

先输出：

```bash
echo "━━━ PMAI ► INIT-PROJECT ▸ 建立产品上下文 ━━━"
```

全新项目：

```bash
PMAI_HOME="${PMAI_HOME:-$HOME/.pmai}" \
bash "$PMAI_HOME/scripts/init-project.sh" \
  "<project-name>" "<target-dir>" "<background>"
```

资料目录追加 `--allow-existing`。若有同名目标，先保留原资料并停止，让 PM 决定重命名或归档；无冲突时脚本先固定接入前 manifest，再完成脊柱、目录、host 配置和包含 manifest 的初始 commit，并提示继续当前初始化以核验接入前资料。返回 0 不代表产品基线已经通过，也不代表已经做过 design。

### C · 写入一句话产品背景

将 A 步的一句话背景写入 `PRODUCT.md` 的「产品定位」段。只写已经知道的内容：

- 项目名；
- 一句话产品定位；
- PM 已主动提到的首批待办（若没有则不编造）。

`PRODUCT.md` 的核心问题与价值、用户、产品边界、MVP Case 和术语未知时保留模板提示；不得为了填满结构提前猜测。新项目保留 `PMAI_PROPOSAL_REQUIRED` 标记，直到完整 Proposal 定稿并同步产品基线。技术栈只在首个可建造 design 定稿后进入 `.pm-workflow/project.yml`。`DESIGN.md` 只保留通用基线骨架，不在初始化阶段决定组件库或代码路径。

只暂存本步实际修改的脊柱文件并提交：

```bash
git -C "<target-dir>" add -- PRODUCT.md TODO.md DESIGN.md
git -C "<target-dir>" commit -m "docs: establish initial product context"
```

没有实际变化时不制造空提交。

### D · 全新项目的单一 Next Up

终态只给一个正常入口：

```text
═══════════════════════════════════════
✅ <project-name> 的产品上下文已建立
📁 <target-dir>

▶ Next Up：/pmai-proposal
   先把产品用户、核心问题、价值、边界和 MVP 讲清楚，再进入第一个 design。
═══════════════════════════════════════
```

不要追加“直接改 prototype”“先跑 mockup”“直接 build”或工具菜单。全新项目的正常下一步只有 `/pmai-proposal`。

### D.5 · 资料目录核验后分流

资料目录不是全新项目，也不能因为“有一些文档”就自动跳过 Proposal。完成 B/C 后，完整读取 `_shared/project-questioning.md`，使用 `.pm-workflow/intake-manifest.json` 固定的接入前资料清单执行同一套六项核验：

1. 只从接入前已有的立项、正式 PRD、产品说明、用户研究、范围说明和已生效决定提取产品判断；PMAI 刚生成的骨架不能充当依据。
2. 六项已有内容完整且一致时，先展示证据卡，再请 PM 确认这些判断是否仍有效；不得用初始化问卷现场补齐缺项。
3. PM 确认后，把稳定结论、至少一个 manifest 中路径与 hash 均仍一致的真实仓内依据和确认日期同步到 `PRODUCT.md`，移除 required marker，并精确提交实际更新文件。
4. 提交后运行 `proposal-contract.py status`。只有机器状态为 `equivalent_baseline`，唯一 Next Up 才是 `/pmai-design "<第一个模块结果>"`。
5. 任一项缺失、冲突、需要新推导，或 PM 要纠正方向时，保留 marker，唯一 Next Up 为 `/pmai-proposal`。

资料目录不执行 codebase-audit；没有代码时不要为了复用流程伪造 `docs/CODEBASE-AUDIT.md`。

### E · 已有代码库接入

已有代码库执行 `skills/_internal/codebase-audit/SKILL.md` 的只读现状盘点和产品脊柱接入逻辑：

0. 在生成 audit、脊柱或任何 PMAI 文件前运行 `python3 "$PMAI_HOME/scripts/proposal-contract.py" capture-intake "$REPO_ROOT"`；失败时停止，不得事后补造或覆盖 manifest；
1. 再记录真实技术栈、入口、运行命令和现有页面，但只写入 `docs/CODEBASE-AUDIT.md`，不提前生成 `project.yml`；
2. 补齐缺失的根目录产品脊柱和 host 配置；
3. 不创建空 `prototype/`，不覆盖已有代码，不因 gstack 缺失阻塞；
4. 判断 manifest 中且当前 hash 未变的现有资料是否已经形成等价产品基线：能够明确回答当前定位、主用户、核心问题与价值、产品边界和第一个 MVP 结果，并且 PM 确认这些判断仍有效；确认后必须按 `_shared/project-questioning.md` 在 `PRODUCT.md` 记录真实仓内依据与 PM 确认日期，移除 `PMAI_PROPOSAL_REQUIRED`，并以 `proposal-contract.py status` 返回 `equivalent_baseline` 为准，才能直接引导 `/pmai-design`；
5. 缺少任一关键判断、判断互相冲突或 PM 要重判方向时，引导 `/pmai-proposal`，不得把代码现状冒充产品方向；
6. 首次达到 `ready_to_build` 时，再由 design 基于现状档与新需求生成 `project.yml`。

## Rules

- 本 skill 是唯一初始化入口；消费仓已经接入后不能重复运行。
- 新项目脚本签名固定为 `<project-name> <target-dir> <background> [--allow-existing]`；旧第四个类型参数必须报迁移提示。
- 初始化成功不代表已确定建造对象；`.pm-workflow/project.yml` 缺失是 design 尚未定稿的正常状态。
- 初始化不依赖 gstack、browser、Playwright 或任何前端脚手架。
- 不把 `system / custom / unknown` 生成为新项目类型。
- 全程使用运行时路径与仓内相对路径，禁止沉淀机器绑定绝对路径。
- PM-facing 文案只讲产品上下文、产品方向和第一个需求，不讲 greenfield、brownfield、intent、gate 等内部词。
- 资料目录与已有代码库共用 `_shared/project-questioning.md` 的产品基线标准；codebase-audit 只属于已有代码分支。
- 接入前 manifest 只能在任何 PMAI 文件写入前生成一次；不得为了让后生成材料通过机器检查而重建或改写。

## 失败兜底

| 场景 | 行为 |
|---|---|
| 目标目录已接入 PMAI | 停止，不覆盖；引导 `/pmai-status` |
| 资料目录未获 PM 同意接住 | 不传 `--allow-existing`，不修改目录 |
| 资料目录存在 PMAI 同名目标 | 写入前停止并列出冲突，不覆盖、不猜测合并 |
| 脚本失败 | 报 stderr，停在 B，不继续写脊柱 |
| gstack 不可用 | 忽略；初始化继续 |
| PM 中途停止 | 保留已经提交的骨架；未提交内容保持可见，不删除目录 |
| 全新项目初始化后直接要求 design/build | 先完成 `/pmai-proposal`；不得临时补产品方向或项目类型继续 |
| 资料目录核验后机器状态不是 `equivalent_baseline` | 不进入 design；保留 marker 并转 `/pmai-proposal` |
