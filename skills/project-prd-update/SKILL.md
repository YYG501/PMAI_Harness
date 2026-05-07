---
name: project-prd-update
description: |
  在 close-req 时（或 PM 手动触发时）把已定稿的 req 级 prd 增量并入项目主 PRD（`docs/prd.md`）。
  只在本 req 有产品功能变化时调用；纯文档/重构/bugfix 跳过。
  由 close-req 在 stage 6 完成后调用，也可由 PM 在多个 req 累积后批量整理时手动触发。
---

# /project-prd-update

## When To Use

- `close-req` 步骤 2b：req 级 prd 已定稿，且本 req 对产品功能有变化（新增模块 / 已有模块扩展 / 角色变更 / 路线推进）
- PM 手动触发：多个 req 累积后想批量整理项目主 PRD，或发现项目主 PRD 与现状脱节

**不调用的场景**：本 req 是纯文档基础设施增强、纯重构、纯 bugfix；或 req 级 prd 不存在（说明 close-req 跳过了 prd-writing）

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: project-prd-update"
```

## Required Inputs

1. `$ACTIVE_REQ_DIR/prd.md`（必需，req 级 prd，由 `/prd-writing` 产出）
2. `$REPO_ROOT/docs/prd.md`（必需，项目主 PRD，模板见 `$REPO_ROOT/templates/project-prd.md.tmpl`）
3. `$ACTIVE_REQ_DIR/.req-meta.json`（用于取 req id / name / 关闭日期作为产品路线时间戳）

## Workflow

### 步骤 1：读取并定位

读取 req prd 与项目 prd。识别 req prd 第六章「功能需求」表里的所有功能行，按一级功能归类。

### 步骤 2：生成增量草案（不写文件）

对项目主 PRD 的四个 section 分别生成增量草案：

| 项目 PRD section | 增量逻辑 |
|---|---|
| 产品概述 | 仅当 req 引入了新的"产品定位"层面变化时改；功能层面变化不动这里 |
| 功能清单 | 按一级功能匹配。已存在的一级功能 → 在该模块下补/改子项；不存在 → 新增模块块 |
| 用户画像 | 仅当 req prd 第 5.1 引入新角色或改变现有角色职责时改 |
| 产品路线 | "已交付"区块追加一行：`- {{REQ_ID}} {{REQ_NAME}}（{{关闭日期}}）：<一句话交付摘要>` |

**生成规则：**
- 每个 section 用 markdown diff 形式呈现（增/改/不动）
- 用语统一项目 PRD 已有的口径（不要把 req prd 的字段级描述原样灌进项目 PRD——项目 PRD 是模块级累积视图，不展开字段细节）
- 一句话交付摘要从 req prd 摘要章节提取，不超过 30 字

### 步骤 3：PM 确认增量

把四个 section 的 diff 草案贴 chat（不是贴全文，是 diff 段落），让 PM 逐 section 确认：

```
docs/prd.md 增量草案（基于 $ACTIVE_REQ_DIR/prd.md）：

【功能清单】
+ 新增模块「XXX」
  + 子功能 A
  + 子功能 B
~ 已有模块「YYY」
  + 追加子功能 C

【产品路线 → 已交付】
+ - req-NNN-<slug>（YYYY-MM-DD）：<一句话>

【产品概述】不动
【用户画像】不动

A) 全部确认，写入 docs/prd.md
B) 我要改某些段落（请说明 section + 改法）
C) 跳过本次同步（保持 docs/prd.md 不动）
```

### 步骤 4：写入

PM 选 A 或修订后，写回 `$REPO_ROOT/docs/prd.md`。**只改 PM 确认的 section**，其它保持原状。

写完报告：

```
✅ docs/prd.md 已更新
变更：[功能清单 / 产品路线]
未变更：[产品概述 / 用户画像]
```

### 步骤 5（PM 选 C 时）

不写文件，记录跳过理由：

```
⏭️ docs/prd.md 未更新（PM 跳过）
理由：[PM 给的理由，记在 close-report.md 的"文档变更"section]
```

## Rules

- **只增量，不重写**：不重排已有的功能清单或产品路线条目；不替换原有措辞
- **跨 section 不顺手**：本次 diff 涉及哪些 section 就只改哪些；不顺便整理排版/标点
- **不重复展开**：req prd 已经写清楚的字段级细节，项目 PRD 用模块名引用即可，不复制
- **跳过有记录**：PM 选 C 时，理由必须落到 close-report.md，避免后续审计找不到为什么没同步
- **不调 prd-writing**：本 skill 只做合并，不重新写 PRD；req prd 是真相源

## Common Mistakes

- 把 req prd 9 章原样灌进项目 PRD（错位：项目 PRD 是累积视图，不是单 req 切片）
- 改了 PM 没确认的 section（顺手整理）
- 跳过却不记理由（close-report 里看不到为什么主 PRD 没同步）
- 在没产品功能变化的 req 上硬调（应该由 close-req 判断后跳过）

## 边界

- **允许产出**：`$REPO_ROOT/docs/prd.md`（修改）
- **允许动作**：增量并入、记录跳过理由
- **禁止顺手**：不写 req prd、不动 close-report 主体（只追加跳过理由那一行）、不动 task / solution / analysis
- **退出条件**：docs/prd.md 已写入或显式跳过；控制权交回 `/close-req`
