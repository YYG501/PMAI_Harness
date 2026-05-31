---
name: pmai-codebase-audit
description: |
  Brownfield 一气呵成入口：已有代码库接入框架时，一个命令走完——扫码产出「代码现状档」
  （7 维度：技术栈 / 集成 / 架构 / 结构 / 约定 / 测试 / 隐患；带防 secret 扫描），PM 过目现状档后，
  在同一流程内内联跑项目方向讨论（被现状档喂着，和新项目一样），产出 docs/PROJECT.md + docs/TODO.md。
  与 GSD 的 map-codebase → new-project 同构。新项目（无已有代码）不用本 skill。
---

# /pmai-codebase-audit

## When To Use

- **brownfield 场景**：已有代码库要接入 PM-AI-Workflow 框架时调用。一个命令走完接入：扫码产现状档 → PM 过目 → 内联定方向。
- 新项目（空仓 / 全新）**不用**本 skill —— 直接 `/pmai-init-project`（greenfield 一气呵成入口）。

本 skill = brownfield 一气呵成入口，和 greenfield 的 `/pmai-init-project` 对称：greenfield 一个命令把骨架 + 方向讨论做完，brownfield 一个命令把现状盘点 + 方向讨论做完。中间隔一个「PM 过目现状档」的轻停顿（现状档是方向决策的输入材料，PM 点头再继续），不用 PM 手敲第二个命令。方向讨论这一段和新项目走同一套 `_shared/project-questioning.md`，只是多一份现状输入喂着。

> **与 `/pmai-project-solution` 的分工**：本 skill 内联跑的是 brownfield **首次接入定方向**；`/pmai-project-solution` 是**事后改方向**的按需入口（跑过几个 req 发现定位偏了 / 产品路线规划 / 老板新方向）。接入用本 skill 一条龙，不再需要先 audit 再手动 project-solution。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: codebase-audit"
```

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

向 PM 确认：要审计的代码库根目录（默认当前仓）；有无要排除的目录（如 `vendor/` /
`node_modules/` —— 这些本就该跳过）。

### 步骤 2：扫码 7 维度

用 read-only 工具（Glob / Grep / Read；大范围探索可派 read-only subagent fan-out）盘点
7 个维度，逐维写进 `docs/CODEBASE-AUDIT.md`（按 `$PMAI_HOME/skills/codebase-audit/templates/codebase-audit.md.tmpl`）：

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
你过目后说「继续」，我接着用这份现状档跟你定项目方向（产出 PROJECT.md + TODO.md）。
```

PM 提修正 → 改现状档 → 重新呈交。

> **这是一个轻停顿，不是流程终点**：现状档是方向决策的输入材料，留这个停顿让 PM 先把它看准（可以离线慢慢读）。PM 说「继续 / 接着定方向 / OK」→ 进 step 3.5 / 3.5.5 兜底，再进 step 4 内联方向讨论。**不要**让 PM 去手敲 `/pmai-project-solution`——方向讨论就在本流程内接着跑。

### 步骤 3.5：产品模块清单 + modulespec 主规格骨架（PM 选择性触发）

> **brownfield 项目专属步骤**：老代码库的模块边界往往已经稳定在代码里（菜单 / 路由 / 模块目录结构）。本步骤提取「产品模块清单」+ 按 `$PMAI_HOME/skills/codebase-audit/templates/module.md.tmpl` 生成 `docs/modules/<m>.md` 主规格骨架。
>
> **为什么有这步**：不建 modulespec → 后续 task 偏差表无 baseline 可 diff →「本 req 新建/改了稳定结构但 `docs/modules/` 无对应规格文件」常态化 → 每个 req close 时 §1.5 step 2.5 反复问「这次稳定结构要不要沉淀」。一次性建好 = 反查退化成真正的兜底。
>
> **新项目（greenfield）不需要本步骤** —— IA 还没定，过早建会写一堆空 placeholder；走 close-req §1.5 step 2.5 反查按需生长。

**PM 触发**：步骤 3 现状档确认后问 PM：

```
✅ 现状档已确认。

你这个老项目已经有稳定的产品模块边界（基于代码扫描识别出 N 个候选模块）。
要不要现在建 docs/modules/<m>.md 主规格骨架？

✅ 好处：后续 task 偏差表能直接 diff，close-req 不会反复问「这次稳定结构要不要沉淀」
⚠️ 代价：现在多花 N 分钟过一遍模块清单 + 看 AI 生成的骨架

[Y] 现在建（推荐 —— 项目 IA 已经稳定的老项目都应该建）
[N] 跳过（IA 还在演化，按需走，靠 close-req §1.5 step 2.5 兜底）
```

**PM 选 Y 时执行**：

1. **抽候选模块清单**：AI 扫代码识别候选模块 ——

   - 子目录信号：`src/modules/*` / `src/pages/*` / `src/features/*` / `apps/*` / `packages/*`
   - 多 app 项目：每个 app 当一个 module
   - 路由表 / 菜单配置里的顶级分组（找 `routes`/`navigation`/`menu`/`sidebar` 关键词文件）
   - `docs/PROJECT.md` 已有的「业务模块」段（若之前 project-solution 跑过）
   - 候选清单去重 / 合并明显同义的（如 `user-management` 和 `user-mgmt`）

2. **PM 确认候选清单**：呈交清单格式 ——

   ```
   候选模块清单（基于代码扫描）：

   1. <module-name>
      证据：<src/ 路径 + 文件数 + 关键文件>
      建议主规格路径：docs/modules/<module-name>.md
      简短定位（AI 草拟，≤30 字）：<...>
      检测到的稳定结构：菜单(src/.../X.ts) / 路由(src/.../Y.ts) / schema(src/.../Z.ts)

   2. ...
   ```

   PM 可以：合并 / 拆分 / 改名 / 排除某条 / 增加 AI 漏掉的。PM 修正 → AI 调整 → 重新呈交 → PM 确认。

3. **生成主规格骨架**：按 `$PMAI_HOME/skills/codebase-audit/templates/module.md.tmpl` 为每个确认模块建 `docs/modules/<m>.md` ——

   - **§摘要**：AI 写 1-3 句（基于代码扫到的功能形态 + PROJECT.md / 代码现状档）
   - **§一 模块定位 1.1-1.4**：AI 填能扫到的部分；**1.4 职责边界末尾追加「**稳定结构指针**」sub-bullet 列菜单 / 路由 / schema / config 文件路径**（指针不抄内容，防漂移）
   - **§二 功能清单**：保持模板空（后续 task close 时由 close-req §1.5 sediment 填）
   - **§三 页面与交互范围**：AI 填能扫到的（路由表 / 页面文件）
   - **§四 硬约束** / **§五 跨模块依赖与占位策略**：保持空，PM 后续按需补
   - **顶部状态行**：保留模板的「草稿 | 未经 PM 确认 | 生成时间」标记 —— 让 PM 后续知道哪些段是 AI bootstrap 的、哪些是后续 req sediment 的

4. **刷新 INDEX.md**：按生成的模块清单 patch `docs/modules/INDEX.md`（每个新模块一行：名称 / 路径 / 一句话定位），跑 `check-index-lint.py` 校验。

5. **PM 审 diff**：呈交 `git diff docs/modules/`，PM 满意 → 本步骤结束。不满意 → AI 调整。PM 大改 → 可以中止 step 3.5 走 [N] 路径。

**PM 选 N 时**：跳过本步骤；step 4 交接时提示「modulespec 骨架未建，后续 close-req §1.5 step 2.5 反查会兜底」。

### 步骤 3.5.5：docs/DESIGN.md inventory 段兜底（无条件兜底，独立于 step 3.5 选择）

> **跟 step 3.5 的关系**：3.5 是 PM 选择性建 modulespec 骨架；3.5.5 是**无条件**建 / 修复 DESIGN.md（不让 PM 选择 —— 它是 stage 4 4A 硬依赖，PM 没法绕过；3.5 [N] 也照样跑本步骤）。

**为什么有这步**：DESIGN.md 是 task executor 写代码时的硬约束（stage 4 4A gap-check 强制读「共享组件 inventory」段）。老项目接入框架前通常没建过这个文件，或建了但没 inventory 段 → stage 4 4A 隐性 break，PM 第一个 req 推不到 stage 5。本步骤兜底建 / 修复。

```bash
DESIGN_MD="$REPO_ROOT/docs/DESIGN.md"
HAS_FILE=false; HAS_INVENTORY=false
[ -f "$DESIGN_MD" ] && HAS_FILE=true
$HAS_FILE && grep -q "^## 共享组件 inventory" "$DESIGN_MD" && HAS_INVENTORY=true
```

| 状态 | 行为 |
|---|---|
| HAS_FILE=true + HAS_INVENTORY=true | silent skip |
| HAS_FILE=true + HAS_INVENTORY=false | AI 用 Edit 在末尾追加 inventory 空段（模板见下方） |
| HAS_FILE=false | AI 用 Write 建空骨架（含顶部状态行 + inventory 空段，模板见下方） |

**inventory 空段模板**（追加 / 包含在新建骨架）：

```markdown

## 共享组件 inventory

> **这是什么**：stage 4 gap-check 的查询底座。每个 req 动手前逐组件查这里：
> **有 → 复用**；**没有 → 新建并加进本表**。req 间累积，越来越全，reuse 率随之上升。

| 组件名 | 用途 | 视觉 | 状态 | 交互 | 出处 req |
|---|---|---|---|---|---|
| <!-- stage 4 4A 累积，目前为空 --> | | | | | |
```

**新建 DESIGN.md 时的空骨架**（仅当 HAS_FILE=false 时，套上方 inventory 模板）：

```markdown
<!-- 状态：兜底骨架 | 由 codebase-audit step 3.5.5 建 | 视觉基线段未建 -->

# 设计系统

> **本文件目的**：项目级设计系统约束。stage 4 4A gap-check 查这里的「共享组件 inventory」段；task executor 写代码时按视觉基线段（gstack 写的 8 段）做硬约束。
>
> **视觉基线段未建** —— 建议 PM 跑 gstack `/design-consultation` 补全 8 段（颜色 / 字体 / 间距 / 布局 / 动效 / 美学方向 / 竞品研究 / 视觉预览板）。本框架不替 gstack 写视觉基线，本骨架只兜 inventory 段（stage 4 4A 硬依赖）。
>
> **inventory 段**由本框架管，stage 4 4A 累积，gstack 不写。

<!-- 套入上方 inventory 空段模板 -->
```

**告知 PM**：

```
📝 DESIGN.md 兜底：<已建空骨架 / 追加 inventory 段 / 已是完整态>
  视觉基线段建议：跑 gstack `/design-consultation` 补全 8 段（PM 主动入口）
```

### 步骤 3.5.7：docs/PRODUCT-STATE.md 兜底（无条件兜底，独立于 step 3.5 选择）

> **跟 step 3.5 / 3.5.5 的关系**：和 step 3.5.5（DESIGN.md inventory 兜底）同款**无条件**模式——PM 没法绕过、跟 step 3.5 的 Y/N 无关。

**为什么有这步**：`docs/PRODUCT-STATE.md` 是产品「现状层」hub，下游 `/pmai-new-req` 范围确认开头**强制读它**（当前功能 / 主原型现状 / mock-真状态位）。greenfield 的 `init-project.sh` 会铺这个模板，但 brownfield 走 codebase-audit 从不建它 → PM 第一个 req 范围确认退化成「白纸起步」，audit 已扫到的全部现状在 new-req 入场时丢失。本步骤兜底建 + 从现状档反推填充。

> **防腐豁免（必读，否则 review 会误判 BLOCKER）**：`PRODUCT-STATE.md` 模板写「只在 close-req 沉淀那刻更新」（防腐铁律）。**brownfield 首次 bootstrap 不违反**——首次建档 vs 后续随手改是两回事（类比 greenfield init-project 也在 close-req 之外先铺模板，codebase-audit 只是多一步反推填，填的是 audit 已扫到的**现状事实**，不是凭空编未来）。bootstrap 态由顶部状态行明确标出，与 close-req 沉淀态区分。**反推只引用 `CODEBASE-AUDIT.md` 已落事实 + 可验证代码扫描；扫不到的层填「未知 / 待确认」不猜测**（防 narrative 幻觉）。

```bash
PRODUCT_STATE_MD="$REPO_ROOT/docs/PRODUCT-STATE.md"
HAS_PS=false
[ -f "$PRODUCT_STATE_MD" ] && HAS_PS=true
```

| 状态 | 行为 |
|---|---|
| HAS_PS=true | silent skip（已有，不覆盖） |
| HAS_PS=false | AI 用 Write 套 `$PMAI_HOME/templates/PRODUCT-STATE.md.tmpl` 建骨架 + 反推填三段 + 顶部状态行 |

**反推填充映射**（产品现状 = 已发生事实，直接反推、不设 PM 确认门——与反推未来 req 需 PM 拍板顺序本质不同）：

| PRODUCT-STATE 段 | 从哪反推 |
|---|---|
| 当前功能 / 能力 | `CODEBASE-AUDIT.md` §3 架构 + §4 目录结构 + 路由 / 菜单扫描的功能面，每条 ≤ 一行 |
| 主原型现状 | brownfield 无 `prototype/` 脚手架 → 按 audit §4 页面 / 路由列已有页面区域，备注统一标「源自现有 codebase，非 prototype/ 脚手架」；若连页面都没有，如实写「主原型尚未立」 |
| 实现深度状态（mock / 真） | 按 audit §1 技术栈 + §2 外部集成反推每层真 / mock（brownfield 有真 DB / 真后端的层填「真系统」，何时转列填「接入时已是」或「—」；扫不到的层填「未知」） |
| 产品定位一句话 | **留空占位**，step 4 拍定 PROJECT.md 产品定位后回填（要对齐 PROJECT.md，而它 step 4 才产出） |

**顶部状态行**（插在 H1 标题之前）：

```markdown
<!-- 状态：草稿 | 由 codebase-audit step 3.5.7 反推 bootstrap | 未经 PM 逐行确认 | 产品定位一句话待 step 4 回填 -->
```

**告知 PM**：

```
📝 PRODUCT-STATE.md 兜底：<已建骨架 + 反推填现状三段 / 已存在跳过>
  产品定位一句话留空，step 4 定方向后回填
```

### 步骤 4：内联方向讨论（产 PROJECT.md + TODO.md）

PM 在 step 3 轻停顿说「继续」后，**在本流程内直接接着跑项目方向讨论**——不交接出去、不让 PM 手敲 `/pmai-project-solution`。逻辑和 greenfield（`/pmai-init-project` 阶段 C）完全同一套，走共享真相源。

**怎么跑**：

1. **@读 `skills/_shared/project-questioning.md`**（**单一真相源**——提问纪律 / 问题库 / 写作规则 / Decision gate / 5 节检查）。
2. **全文读 `docs/CODEBASE-AUDIT.md`**（刚产出的现状档，作已有代码库的实况语境，AI 不准跳）。
3. 按 **brownfield 提问顺序**问 PM（场景特定，与 `/pmai-project-solution` 段 0 表「D brownfield 接入」一致）：
   - (1) 产品定位（**从 codebase 反推 + PM 确认**）
   - (2) 用户画像（从代码层级 / API 角色反推 + PM 补）
   - (3) 技术栈（**从现状档抄**，PM 确认）
   - (4) 业务术语表（**从 model / API 命名反推 + PM 补**）
   - (5) TODO 待办池（PM 给，AI 不反推填充——只记 PM 提过/讨论过想做的，不排序）
4. **未决问题闸门**（@读 `_shared/project-questioning.md` §4）：暂存文件 `docs/.project-solution-open-questions.md`，闸门必过。
5. **Decision gate 确认门**（@读 §6）：label = 动作描述，PM 选「创建 PROJECT.md」才落盘；选「继续探索」回提问 Loop。
6. **写 `docs/PROJECT.md` + `docs/TODO.md`**（@读 §5 写作规则）。
7. **5 节齐不齐检查**（@读 §7）：跑 `check-project-sections.py`，有空节逐节补。
8. **PM 定稿**（@读 §8）：展示路径 + 摘要，PM 答「OK / 定了」。
9. **回填 PRODUCT-STATE 产品定位**：把 step 3.5.7 留空的 `docs/PRODUCT-STATE.md` 产品定位一句话按 PROJECT.md 拍定的定位填上，去掉顶部状态行里「产品定位待回填」那句。
10. **atomic commit**（@读 §9）：`git commit -m "docs: project direction settled"`（含 PROJECT.md / TODO.md / PRODUCT-STATE.md 回填）。
11. 收尾向 PM 一句话说明 TODO 是 PM 自己维护的待办池（AI 不反推填充），给 ▶ Next Up 块引到第一个需求：`/pmai-new-req "<一句话需求>"`。

> **为什么内联而不是交接**：方向讨论的全部逻辑已沉淀在共享的 `_shared/project-questioning.md`，greenfield 的 init-project 阶段 C 就是这么内联跑的；brownfield 现状档此刻已在手，没有任何技术理由再拆成第二个手敲命令。轻停顿（step 3）已经给了 PM 消化现状档的时间——「留消化时间」和「逼 PM 手敲命令」是两件事，本 skill 只保留前者。

## Rules

- **扫码阶段只读**：步骤 1-3（扫码 + 产现状档）只读代码、不改代码。step 4 内联方向讨论才写 `docs/PROJECT.md` + `docs/TODO.md`（PM 在 Decision gate 拍板后落盘）。
- **防 secret 是硬约束**：见上方「防 secret 扫描」段，违反 = 严重错误。
- **方向讨论走共享真相源**：step 4 内联方向讨论必须 @读 `skills/_shared/project-questioning.md`，**不要**在本 skill 里重抄提问法 / 写作规则（必漂移；真相源单一，和 init-project 阶段 C / project-solution 共用同一套）。
- **与 `/pmai-project-solution` 分工**：本 skill 管 brownfield **首次接入定方向**（内联跑完）；`/pmai-project-solution` 管**事后改方向**（场景 A 重做 / B 路线规划 / C 新方向）。接入不再需要 PM 手敲 project-solution。
- 新项目不用本 skill（无已有代码可审）。
- step 3.5 模块清单由 PM 确认 —— AI 不替 PM 决定模块边界（候选清单 PM 必须过一遍）。

## 边界

- **允许产出**：
  - `docs/CODEBASE-AUDIT.md`（默认）
  - `docs/PRODUCT-STATE.md` 兜底建骨架（**step 3.5.7 无条件**，反推填现状三段，产品定位一句话 step 4 回填）
  - `docs/PROJECT.md` + `docs/TODO.md`（**step 4 内联方向讨论，PM 在 Decision gate 拍板后**）
  - `docs/.project-solution-open-questions.md`（step 4 未决问题闸门暂存文件）
  - `docs/modules/<m>.md` 主规格骨架（**仅当 step 3.5 PM 选 [Y]**）
  - `docs/modules/INDEX.md` 刷新（**仅当 step 3.5 PM 选 [Y]**）
  - `docs/DESIGN.md` 兜底建 / 追加 inventory 段（**step 3.5.5 无条件，跟 step 3.5 选择无关**）
- **允许动作**：read-only 扫码、7 维度盘点、防 secret redact、step 3.5 选 [Y] 时按 `$PMAI_HOME/skills/codebase-audit/templates/module.md.tmpl` 生成主规格骨架、step 3.5.5 兜底 DESIGN.md inventory 段、step 3.5.7 兜底 PRODUCT-STATE.md（反推填现状三段，定位 step 4 回填）、step 4 内联方向讨论（@读 `_shared/project-questioning.md`）
- **禁止**：改代码 / 改 step 3.5 / 3.5.5 范围外的业务文档 / step 4 替 PM 做方向决策（必过 Decision gate）/ step 3.5 跳过模块清单 PM 确认环节 / step 3.5.5 替 gstack 写视觉基线 8 段（视觉基线由 PM 主动调 `/design-consultation`）/ 在 step 4 重抄 `_shared/project-questioning.md` 的提问法与写作规则
- **退出条件**：现状档经 PM 确认 + step 3.5 完成（建或跳过）+ step 3.5.5 兜底跑过 + step 3.5.7 PRODUCT-STATE 兜底跑过 + step 4 方向讨论定稿（PROJECT.md / TODO.md 已落 + PRODUCT-STATE 产品定位已回填 + atomic commit）+ 给出 ▶ Next Up（`/pmai-new-req`）
