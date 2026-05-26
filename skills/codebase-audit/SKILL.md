---
name: codebase-audit
description: |
  Brownfield 入口：已有代码库接入框架时，扫码产出「代码现状档」
  （7 维度：技术栈 / 集成 / 架构 / 结构 / 约定 / 测试 / 隐患；带防 secret 扫描），
  然后走和新项目一样的 /project-solution 讨论（被现状档喂着）。
  与 GSD 的 map-codebase → new-project 同构。新项目（无已有代码）不用本 skill。
---

# /codebase-audit

## When To Use

- **brownfield 场景**：已有代码库要接入 PM-AI-Workflow 框架时调用，**在 `/project-solution` 之前**。
- 新项目（空仓 / 全新）**不用**本 skill —— 直接 `/init-project` → `/project-solution`。

本 skill = brownfield 入口。它产出「代码现状档」喂给 `/project-solution`，让 project-solution
被已有代码库的实况喂着讨论项目方向 —— 和新项目一样的 project-solution，只是多一份现状输入。

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
7 个维度，逐维写进 `docs/代码现状档.md`（按 `$PMAI_HOME/templates/codebase-audit.md.tmpl`）：

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

写完 `docs/代码现状档.md` 后呈交 PM：

```
✅ 代码现状档：docs/代码现状档.md

📋 7 维度盘点完成：技术栈 <一句> / 集成 N 个 / 架构 <一句> / 隐患 M 项

这份现状档准吗？有补充 / 纠正直接说；确认后跑 /project-solution（它会读这份档作为
已有代码库的语境讨论项目方向）。
```

PM 提修正 → 改现状档 → 重新呈交。

### 步骤 3.5：产品模块清单 + modulespec 主规格骨架（PM 选择性触发）

> **brownfield 项目专属步骤**：老代码库的模块边界往往已经稳定在代码里（菜单 / 路由 / 模块目录结构）。本步骤提取「产品模块清单」+ 按 `templates/module.md.tmpl` 生成 `docs/modules/<m>.md` 主规格骨架。
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

3. **生成主规格骨架**：按 `templates/module.md.tmpl` 为每个确认模块建 `docs/modules/<m>.md` ——

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

### 步骤 4：交接 project-solution

PM 确认现状档后，引导 PM 跑 `/project-solution` —— project-solution 读 `docs/代码现状档.md`
作为已有代码库的语境，和新项目一样讨论项目方向、产出 `docs/PROJECT.md` + `docs/ROADMAP.md`。

## Rules

- **默认只读扫码**：步骤 1-4 + step 3.5 选 [N] 路径只产 `docs/代码现状档.md`，不改代码、不改其它业务文档。**例外**：step 3.5 选 [Y] 时允许生成 `docs/modules/<m>.md` 主规格骨架 + 刷新 `docs/modules/INDEX.md`（PM 确认模块清单后按 `module.md.tmpl` 生成）。
- **防 secret 是硬约束**：见上方「防 secret 扫描」段，违反 = 严重错误。
- **不替代 `/project-solution`** —— 本 skill 只产现状档 + 可选 modulespec 骨架；项目方向讨论由 project-solution 做。
- 新项目不用本 skill（无已有代码可审）。
- step 3.5 模块清单由 PM 确认 —— AI 不替 PM 决定模块边界（候选清单 PM 必须过一遍）。

## 边界

- **允许产出**：
  - `docs/代码现状档.md`（默认）
  - `docs/modules/<m>.md` 主规格骨架（**仅当 step 3.5 PM 选 [Y]**）
  - `docs/modules/INDEX.md` 刷新（**仅当 step 3.5 PM 选 [Y]**）
  - `docs/DESIGN.md` 兜底建 / 追加 inventory 段（**step 3.5.5 无条件，跟 step 3.5 选择无关**）
- **允许动作**：read-only 扫码、7 维度盘点、防 secret redact、step 3.5 选 [Y] 时按 `module.md.tmpl` 生成主规格骨架、step 3.5.5 兜底 DESIGN.md inventory 段
- **禁止**：改代码 / 改 step 3.5 / 3.5.5 范围外的业务文档 / 替 PM 做项目方向决策 / step 3.5 跳过模块清单 PM 确认环节 / step 3.5.5 替 gstack 写视觉基线 8 段（视觉基线由 PM 主动调 `/design-consultation`）
- **退出条件**：现状档经 PM 确认 + step 3.5 完成（建或跳过）+ step 3.5.5 兜底跑过，引导 PM 跑 `/project-solution`
