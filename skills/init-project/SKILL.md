---
name: pmai-init-project
description: |
  项目初始化统一入口：判断全新项目、资料目录、已有代码库或已接入项目；只建立产品上下文脊柱，不提前决定 project.type、技术栈、框架或代码骨架。初始化完成后统一进入 /pmai-design。
---

# /pmai-init-project · 只建立产品上下文

执行前完整读取 `skills/_shared/pm-view/banner-rules.md`；所有 banner、确认门和 Next Up 按共享 PM 视图规则输出。

## 定位

初始化只回答一件事：**让后续 design 有稳定的产品上下文可以继续工作**。

统一主链是：

```text
/pmai-init-project
→ /pmai-design 明确第一个可建造需求
→ design 定稿时确定 project.type、技术栈和框架
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
| `PRODUCT.md` | 项目名、一句话背景及后续会长厚的产品上下文 |
| `PRODUCT-STATE.md` | 当前产品事实骨架 |
| `DESIGN.md` | 设计基线骨架；首个 UI design 再按真实需求补充 |
| `PRODUCT-RULES.md` | 跨模块现行规则 |
| `TODO.md` | PM 主动提过的待办池 |
| `docs/` | modules、decisions、inputs、engineering、deliverables、archive 等资料结构 |
| `.pm-workflow/config.yml` | 只保存 builder profile 等执行器偏好 |
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

已接入项目不重跑初始化：引导 `/pmai-status`；需要重定方向时走 `/pmai-direction`。

资料目录只有在 PM 明确确认接住现有内容后，才给脚本传 `--allow-existing`。脚本会在首次写入前列出与 PMAI 脊柱、索引或 host 配置同名的冲突并停止，不覆盖也不自动合并；已有代码库进入 E，不调用初始化脚本。

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

资料目录追加 `--allow-existing`。若有同名目标，先保留原资料并停止，让 PM 决定重命名或归档；无冲突时脚本只完成脊柱、目录、host 配置和初始 commit。返回 0 不代表已经做过 design。

### C · 写入一句话产品背景

将 A 步的一句话背景写入 `PRODUCT.md` 的「产品定位」段。只写已经知道的内容：

- 项目名；
- 一句话产品定位；
- PM 已主动提到的首批待办（若没有则不编造）。

`PRODUCT.md` 的用户、产品边界和术语未知时保留模板提示；不得为了填满表格提前猜测。技术栈只在首个可建造 design 定稿后进入 `.pm-workflow/project.yml`。`DESIGN.md` 只保留通用基线骨架，不在初始化阶段决定组件库或代码路径。

只暂存本步实际修改的脊柱文件并提交：

```bash
git -C "<target-dir>" add -- PRODUCT.md TODO.md DESIGN.md
git -C "<target-dir>" commit -m "docs: establish initial product context"
```

没有实际变化时不制造空提交。

### D · 单一 Next Up

终态只给一个正常入口：

```text
═══════════════════════════════════════
✅ <project-name> 的产品上下文已建立
📁 <target-dir>

▶ Next Up：/pmai-design "<第一个需求>"
   先把需求和产品方案讨论清楚；定稿时再确定 prototype/product、技术栈和框架。
═══════════════════════════════════════
```

不要追加“直接改 prototype”“先跑 mockup”“直接 build”或工具菜单。`/pmai-direction` 只在 PM 明确要做项目级方向重定时作为旁路，不与正常 Next Up 并列。

### E · 已有代码库接入

已有代码库执行 `skills/_internal/codebase-audit/SKILL.md` 的只读现状盘点和产品脊柱接入逻辑：

1. 先记录真实技术栈、入口、运行命令和现有页面，但只写入 `docs/CODEBASE-AUDIT.md`，不提前生成 `project.yml`；
2. 补齐缺失的根目录产品脊柱和 host 配置；
3. 不创建空 `prototype/`，不覆盖已有代码，不因 gstack 缺失阻塞；
4. 结束后同样只引导 `/pmai-design`；首次达到 `ready_to_build` 时，再由 design 基于现状档与新需求生成 `project.yml`。

## Rules

- 本 skill 是唯一初始化入口；消费仓已经接入后不能重复运行。
- 新项目脚本签名固定为 `<project-name> <target-dir> <background> [--allow-existing]`；旧第四个类型参数必须报迁移提示。
- 初始化成功不代表已确定建造对象；`.pm-workflow/project.yml` 缺失是 design 尚未定稿的正常状态。
- 初始化不依赖 gstack、browser、Playwright 或任何前端脚手架。
- 不把 `system / custom / unknown` 生成为新项目类型。
- 全程使用运行时路径与仓内相对路径，禁止沉淀机器绑定绝对路径。
- PM-facing 文案只讲产品上下文和第一个需求，不讲 greenfield、brownfield、intent、gate 等内部词。

## 失败兜底

| 场景 | 行为 |
|---|---|
| 目标目录已接入 PMAI | 停止，不覆盖；引导 `/pmai-status` |
| 资料目录未获 PM 同意接住 | 不传 `--allow-existing`，不修改目录 |
| 资料目录存在 PMAI 同名目标 | 写入前停止并列出冲突，不覆盖、不猜测合并 |
| 脚本失败 | 报 stderr，停在 B，不继续写脊柱 |
| gstack 不可用 | 忽略；初始化继续 |
| PM 中途停止 | 保留已经提交的骨架；未提交内容保持可见，不删除目录 |
| 初始化后直接要求 build | 引导先完成 `/pmai-design`，不得临时补选类型继续 |
