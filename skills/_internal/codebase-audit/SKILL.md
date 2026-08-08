---
name: pmai-internal-codebase-audit
description: |
  已有代码库接入 PMAI 的内部子流程：由 /pmai-init-project 检测到源码后自动进入；扫码产出「代码现状档」（技术栈、集成、架构、结构、约定、测试、隐患七个维度，含密钥防护扫描）和经 PM 确认的模块现状清单，再在同一流程内梳理产品方向。代码只作为现状证据，不反向生成目标规格。全新项目无需使用，且不作为公开 /pmai-* 命令暴露。
---

# codebase-audit（内部子流程）

## When To Use

- **默认调用路径**：PM 只需要运行 `/pmai-init-project`。当 init A 步判断目标目录是已有代码库时，自动进入本流程；不要让 PM 在 init 和本子流程之间手动选命令。
- **恢复 / 重扫**：接入流程中断、现状档需要重扫、或 PM 明确要求“重扫已有代码现状”时，仍回到 `/pmai-init-project`，由 agent 读取本内部子流程续跑。
- 新项目（空仓 / 全新）**不用**本 skill —— 直接 `/pmai-init-project`。

本流程是 `/pmai-init-project` 的已有项目分支：一个入口完成判断 → 现状盘点 → PM 过目 → 方向讨论。中间保留「PM 过目现状档」的轻停顿（现状档是方向决策的输入材料，PM 点头再继续），但不要求 PM 手敲第二个命令。方向讨论这一段走 `_shared/project-questioning.md`；全新项目的 init 只做轻量起步，不跑这套完整问卷。

> **与 `/pmai-direction` 的分工**：本流程内联跑的是已有项目**首次接入定方向**；`/pmai-direction` 是**事后校准方向**的按需入口（跑过几轮模块工作发现定位偏了，或 PM 想整理待办）。接入用 init 自动分流的一条龙，不再需要先 audit 再手动 direction。

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
你过目后说「继续」，我接着用这份现状档跟你定项目方向（产出 PRODUCT.md + TODO.md）。
```

PM 提修正 → 改现状档 → 重新呈交。

> **这是一个轻停顿，不是流程终点**：现状档是方向决策的输入材料，留这个停顿让 PM 先把它看准（可以离线慢慢读）。PM 说「继续 / 接着定方向 / OK」→ 进 step 3.5 / 3.5.5 兜底，再进 step 4 内联方向讨论。**不要**让 PM 去手敲 `/pmai-direction`——首次接入的方向讨论就在本流程内接着跑。

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
| 产品定位一句话 | **留空占位**，step 4 拍定 PRODUCT.md 产品定位后回填（要对齐 PRODUCT.md，而它 step 4 才产出） |

**顶部状态行**（插在 H1 标题之前）：

```markdown
<!-- 状态：草稿 | 由 codebase-audit step 3.5.7 反推 bootstrap | 未经 PM 逐行确认 | 产品定位一句话待 step 4 回填 -->
```

**告知 PM**：

```
📝 PRODUCT-STATE.md 兜底：<已建骨架 + 反推填现状三段 / 已存在跳过>
  产品定位一句话留空，step 4 定方向后回填
```

### 步骤 4：内联方向讨论（只产产品脊柱）

PM 在 step 3 轻停顿说「继续」后，**在本流程内直接接着跑项目方向讨论**——不交接出去、不让 PM 手敲 `/pmai-direction`。这是已有代码首次接入的专用方向讨论，走共享真相源；全新项目的 `/pmai-init-project` 不再跑完整 5 节方向问卷。

**怎么跑**：

1. **@读 `skills/_shared/project-questioning.md`**（**单一真相源**——提问纪律 / 问题库 / 写作规则 / Decision gate / 5 节检查）。
2. **全文读 `docs/CODEBASE-AUDIT.md`**（刚产出的现状档，作已有代码库的实况语境，AI 不准跳）。
3. 按 **已有代码接入提问顺序**问 PM（由 init-project 的已有代码分支触发，和 `project-questioning` 的首次接入约定一致；这不是 `/pmai-direction` 的公开分类）：
   - (1) 产品定位（现状档只提供当前产品形态线索；PM 确认或重新定义目标定位）
   - (2) 用户画像（代码层级 / API 角色只作为当前使用者证据；目标用户由 PM 确认）
   - (3) 现有技术事实（只从现状档抄进 audit，不在初始化阶段把它冻结成新建造方案）
   - (4) 业务术语表（**由 PM 定义**；model / API 命名只作为待核对的当前用词证据，不自动写入稳定术语）
   - (5) TODO 待办池（PM 给，AI 不反推填充——只记 PM 提过/讨论过想做的，不排序）
4. **未决问题闸门**（@读 `_shared/project-questioning.md` §4）：暂存文件 `docs/.project-solution-open-questions.md`，闸门必过。
5. **Decision gate 确认门**（@读 §6）：label = 动作描述，PM 选「创建产品上下文」才落盘；选「继续探索」回提问 Loop。
6. **写 `PRODUCT.md` + `TODO.md`**（@读 §5 写作规则）。现有技术栈、入口和运行命令只保留在 `CODEBASE-AUDIT.md`，供首个 `/pmai-design` 形成建造方案时取证；本步不生成 `.pm-workflow/project.yml`，也不向旧 `config.yml` 写 `project.type`。
7. **5 节齐不齐检查**（@读 §7）：跑 `check-project-sections.py`，有空节逐节补。
8. **PM 定稿**（@读 §8）：展示路径 + 摘要，PM 答「OK / 定了」。
9. **回填 PRODUCT-STATE 产品定位**：把 step 3.5.7 留空的 `PRODUCT-STATE.md` 产品定位一句话按 PRODUCT.md 拍定的定位填上，去掉顶部状态行里「产品定位待回填」那句。
10. **atomic commit**（@读 §9）：`git commit -m "docs: project direction settled"`（含 PRODUCT.md / TODO.md / PRODUCT-STATE.md 回填）。
11. 收尾向 PM 一句话说明 TODO 是 PM 自己维护的待办池（AI 不反推填充），给 ▶ Next Up 块引到第一个功能：`/pmai-design "<一句话>"`。

> **为什么内联而不是交接**：已有代码首次接入的方向讨论逻辑已沉淀在共享的 `_shared/project-questioning.md`；brownfield 现状档此刻已在手，没有必要再拆成第二个手敲命令。轻停顿（step 3）已经给了 PM 消化现状档的时间——「留消化时间」和「逼 PM 手敲命令」是两件事，本 skill 只保留前者。

## Rules

- **代码只作现状证据**：步骤 1-3.5 只读代码，不改业务实现；代码扫描结果只进入 `docs/CODEBASE-AUDIT.md`，不得反向生成或改写目标 `spec.md`。
- **防 secret 是硬约束**：见上方「防 secret 扫描」段，违反 = 严重错误。
- **方向讨论走共享真相源**：step 4 内联方向讨论必须 @读 `skills/_shared/project-questioning.md`，**不要**在本 skill 里重抄提问法 / 写作规则（必漂移；真相源单一，和 direction 共用同一套方向讨论内核）。
- **与 `/pmai-init-project` 分工**：本 skill 是 init 的已有项目分支，不是初始化时让 PM 手动选择的并列入口。
- **与 `/pmai-direction` 分工**：本流程管已有项目**首次接入定方向**（内联跑完）；`/pmai-direction` 管**事后方向校准**（方向重定 / 待办整理）。接入不再需要 PM 手敲 direction。
- 新项目不用本 skill（无已有代码可审）。
- step 3.5 模块现状清单由 PM 确认；它仍只是当前证据，不替 PM 决定目标模块边界。

## 边界

- **允许产出**：
  - `docs/CODEBASE-AUDIT.md`（默认）
  - `PRODUCT-STATE.md` 兜底建骨架（**step 3.5.7 无条件**，反推填现状三段，产品定位一句话 step 4 回填）
  - `PRODUCT.md` + `TODO.md`（**step 4 内联方向讨论，PM 在 Decision gate 拍板后**）
  - `docs/.project-solution-open-questions.md`（step 4 未决问题闸门暂存文件）
  - `DESIGN.md` 统一空骨架（**仅在文件缺失时**；已有文件不动）
- **允许动作**：read-only 扫码、7 维度盘点、防 secret redact、把 PM 确认的模块现状清单写回 `CODEBASE-AUDIT.md`、缺失时按统一模板建立 `DESIGN.md`、step 3.5.7 兜底 PRODUCT-STATE.md（反推填现状三段，定位 step 4 回填）、step 4 内联方向讨论并写产品脊柱（@读 `_shared/project-questioning.md`）
- **禁止**：改代码 / 从代码生成或改写 `docs/modules/<m>/spec.md` / 刷新模块规格索引 / 补写已有 `DESIGN.md` / step 4 替 PM 做方向决策（必过 Decision gate）/ step 3.5 跳过模块现状清单 PM 确认环节 / 在 step 4 重抄 `_shared/project-questioning.md` 的提问法与写作规则
- **退出条件**：现状档经 PM 确认 + step 3.5 模块现状清单已确认并写回 + step 3.5.5 检查完成（缺失时建统一骨架）+ step 3.5.7 PRODUCT-STATE 兜底跑过 + step 4 方向讨论定稿（PRODUCT.md / TODO.md 已落 + PRODUCT-STATE 产品定位已回填 + atomic commit）+ 给出 ▶ Next Up（`/pmai-design`）。目标 `spec.md` 与 `project.yml` 留给首个可建造 design 生成。
